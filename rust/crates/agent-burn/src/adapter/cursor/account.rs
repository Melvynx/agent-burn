use serde_json::{Value, json};

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
    json!({
        "billingCycleStartMs": millis(&period["billingCycleStart"]),
        "billingCycleEndMs": millis(&period["billingCycleEnd"]),
        "includedLimitUSD": usd(&plan["limit"]),
        "includedRemainingUSD": usd(&plan["remaining"]),
        "includedPercentUsed": number(&plan["totalPercentUsed"]).filter(|n| *n <= 100.0),
        "onDemandSpentUSD": usd(&spend["totalSpend"]),
        "onDemandLimitUSD": usd(&policy["currentOnDemandLimitCents"]),
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
    }
}
