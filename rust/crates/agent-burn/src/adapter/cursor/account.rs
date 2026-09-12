use serde_json::{json, Value};

use super::{
    loader::{fetch_json, http_agent},
    paths::credentials,
};

pub(crate) fn load_account(offline: bool) -> Option<Value> {
    if offline {
        return None;
    }
    let token = credentials().token?;
    let client = http_agent();
    let period = fetch_json(
        &client,
        "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage",
        &token,
        json!({"includePooledUsage": true}),
    );
    let grants = fetch_json(
        &client,
        "https://api2.cursor.sh/aiserver.v1.DashboardService/GetUsageLimitStatusAndActiveGrants",
        &token,
        json!({}),
    );
    if period.is_none() && grants.is_none() {
        return None;
    }
    Some(normalize(
        &period.unwrap_or(Value::Null),
        &grants.unwrap_or(Value::Null),
    ))
}

fn number(value: &Value) -> Option<f64> {
    value
        .as_f64()
        .or_else(|| value.as_str()?.parse().ok())
        .filter(|n| n.is_finite() && *n >= 0.0)
}

fn millis(value: &Value) -> Option<i64> {
    value
        .as_i64()
        .or_else(|| value.as_str()?.parse().ok())
        .filter(|n| *n > 0)
}

fn usd(value: &Value) -> Option<f64> {
    number(value).map(|n| n / 100.0)
}

fn percent_used(remaining: Option<f64>, limit: Option<f64>) -> Option<f64> {
    match (remaining, limit) {
        (Some(remaining), Some(limit)) if limit > 0.0 => {
            Some(((limit - remaining) / limit * 100.0).clamp(0.0, 100.0))
        }
        _ => None,
    }
}

fn grant_balance(grants: &[Value]) -> (Option<f64>, Option<f64>) {
    let remaining = grants
        .iter()
        .filter_map(|grant| number(&grant["remainingUSD"]))
        .reduce(|left, right| left + right);
    let total = grants
        .iter()
        .filter_map(|grant| number(&grant["totalUSD"]))
        .reduce(|left, right| left + right);
    (remaining, total)
}

fn normalize(period: &Value, credit: &Value) -> Value {
    let plan = &period["planUsage"];
    let spend = &period["spendLimitUsage"];
    let policy = &credit["usageLimitPolicyStatus"];
    let grants: Vec<Value> = credit["activeGrants"]
        .as_array()
        .into_iter()
        .flatten()
        .map(|grant| {
            json!({
                "kind": grant["grantType"].as_str(),
                "totalUSD": usd(&grant["totalCents"]),
                "remainingUSD": usd(&grant["remainingCents"]),
                "expiresAtMs": millis(&grant["expiresAtMs"]),
            })
        })
        .collect();
    let included_limit = usd(&plan["limit"]);
    let included_remaining = usd(&plan["remaining"]);
    let included_percent = number(&plan["totalPercentUsed"]).filter(|n| *n <= 100.0);
    let (grant_remaining, grant_total) = grant_balance(&grants);
    let credits_active = grant_remaining.is_some_and(|remaining| remaining > 0.0);
    let (active_remaining, active_limit, active_percent) = if credits_active {
        (
            grant_remaining,
            grant_total,
            percent_used(grant_remaining, grant_total),
        )
    } else {
        (
            included_remaining,
            included_limit,
            included_percent.or_else(|| percent_used(included_remaining, included_limit)),
        )
    };
    json!({
        "billingCycleStartMs": millis(&period["billingCycleStart"]),
        "billingCycleEndMs": millis(&period["billingCycleEnd"]),
        "includedLimitUSD": included_limit,
        "includedRemainingUSD": included_remaining,
        "includedPercentUsed": included_percent,
        "includedSpendUSD": usd(&plan["includedSpend"]),
        "bonusSpendUSD": usd(&plan["bonusSpend"]),
        "planSpendUSD": usd(&plan["totalSpend"]),
        "onDemandSpentUSD": usd(&spend["totalSpend"]),
        "onDemandLimitUSD": usd(&policy["currentOnDemandLimitCents"]),
        "activeRemainingUSD": active_remaining,
        "activeLimitUSD": active_limit,
        "activePercentUsed": active_percent,
        "grants": grants,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn separates_plan_allowance_from_promotional_credits() {
        let result = normalize(
            &json!({"billingCycleStart":"1000","billingCycleEnd":"2000","planUsage":{"remaining":40000,"limit":40000,"totalPercentUsed":0}}),
            &json!({"activeGrants":[{"totalCents":"1000000","remainingCents":"913000","expiresAtMs":"3000","grantType":"promo"}],"usageLimitPolicyStatus":{"currentOnDemandLimitCents":"5000"}}),
        );
        assert_eq!(result["includedLimitUSD"], 400.0);
        assert_eq!(result["includedRemainingUSD"], 400.0);
        assert_eq!(result["grants"][0]["remainingUSD"], 9130.0);
        assert_eq!(result["onDemandLimitUSD"], 50.0);
        assert_eq!(result["billingCycleEndMs"], 2000);
    }

    #[test]
    fn absent_amounts_remain_unknown_instead_of_zero() {
        let result = normalize(&json!({}), &json!({}));
        assert!(result["includedRemainingUSD"].is_null());
        assert!(result["onDemandLimitUSD"].is_null());
        assert!(result["includedPercentUsed"].is_null());
        assert!(result["activeRemainingUSD"].is_null());
        assert!(result["activePercentUsed"].is_null());
        assert!(result["includedSpendUSD"].is_null());
    }

    #[test]
    fn uses_promotional_credits_as_active_balance_when_included_is_unused() {
        let result = normalize(
            &json!({"planUsage":{"remaining":40000,"limit":40000,"totalPercentUsed":0}}),
            &json!({"activeGrants":[{"totalCents":"1000000","remainingCents":"750000","grantType":"promo"}]}),
        );
        assert_eq!(result["includedPercentUsed"], 0.0);
        assert_eq!(result["activeRemainingUSD"], 7500.0);
        assert_eq!(result["activeLimitUSD"], 10000.0);
        assert_eq!(result["activePercentUsed"], 25.0);
    }

    #[test]
    fn falls_back_to_included_allowance_when_credits_are_exhausted() {
        let result = normalize(
            &json!({"planUsage":{"remaining":20000,"limit":40000,"totalPercentUsed":50}}),
            &json!({"activeGrants":[{"totalCents":"1000000","remainingCents":"0","grantType":"promo"}]}),
        );
        assert_eq!(result["activeRemainingUSD"], 200.0);
        assert_eq!(result["activeLimitUSD"], 400.0);
        assert_eq!(result["activePercentUsed"], 50.0);
    }

    #[test]
    fn maps_plan_spend_fields_when_present() {
        let result = normalize(
            &json!({"planUsage":{"includedSpend":1234,"bonusSpend":5000,"totalSpend":6234}}),
            &json!({}),
        );
        assert_eq!(result["includedSpendUSD"], 12.34);
        assert_eq!(result["bonusSpendUSD"], 50.0);
        assert_eq!(result["planSpendUSD"], 62.34);
    }
}
