use std::{fs, time::Duration};

use serde_json::Value;

use super::{
    paths::codex_home_paths,
    plan::{CodexPlanSnapshot, RateWindow},
};

const USAGE_URL: &str = "https://chatgpt.com/backend-api/wham/usage";
const FETCH_TIMEOUT_SECONDS: u64 = 5;
const FETCH_MAX_BYTES: u64 = 1_000_000;

/// Prefer the live ChatGPT account meter. Fall back to session logs only when
/// the live snapshot is missing, or is missing a weekly window or plan name.
pub(crate) fn resolve_plan_snapshot(offline: bool) -> Option<CodexPlanSnapshot> {
    match usage_limits(offline) {
        Some(live) if live.weekly_window().is_some() && has_known_plan(&live) => Some(live),
        Some(live) => Some(overlay_logs(live)),
        None => super::latest_plan_snapshot(),
    }
}

fn has_known_plan(snapshot: &CodexPlanSnapshot) -> bool {
    !snapshot.plan_type.is_empty() && snapshot.plan_type != "unknown"
}

fn overlay_logs(mut live: CodexPlanSnapshot) -> CodexPlanSnapshot {
    if let Some(logs) = super::latest_plan_snapshot() {
        if !has_known_plan(&live) && has_known_plan(&logs) {
            live.plan_type = logs.plan_type;
        }
        if live.weekly_window().is_none() {
            live.primary = logs.primary;
            live.secondary = logs.secondary;
        }
    }
    live
}

/// Fetch the signed-in Codex account weekly limit from ChatGPT, mirroring the
/// dashboard meter. Returns `None` when offline, when no token is available, or
/// on any network error (never fatal).
fn usage_limits(offline: bool) -> Option<CodexPlanSnapshot> {
    if offline {
        return None;
    }
    let token = access_token()?;
    fetch_usage_limits(&token)
}

fn access_token() -> Option<String> {
    for home in codex_home_paths().ok()? {
        let path = home.join("auth.json");
        if let Some(token) = fs::read_to_string(path)
            .ok()
            .as_deref()
            .and_then(access_token_from_auth)
        {
            return Some(token);
        }
    }
    None
}

fn access_token_from_auth(json: &str) -> Option<String> {
    let value = serde_json::from_str::<Value>(json.trim()).ok()?;
    value
        .get("tokens")?
        .get("access_token")?
        .as_str()
        .filter(|token| !token.is_empty())
        .map(str::to_string)
}

fn fetch_usage_limits(token: &str) -> Option<CodexPlanSnapshot> {
    let agent = ureq::Agent::config_builder()
        .timeout_global(Some(Duration::from_secs(FETCH_TIMEOUT_SECONDS)))
        .build()
        .new_agent();
    let mut response = agent
        .get(USAGE_URL)
        .header("Authorization", &format!("Bearer {token}"))
        .header("Accept", "application/json")
        .header(
            "User-Agent",
            concat!("agent-burn/", env!("CARGO_PKG_VERSION")),
        )
        .call()
        .ok()?;
    if response.status().as_u16() != 200 {
        return None;
    }
    let body = response
        .body_mut()
        .with_config()
        .limit(FETCH_MAX_BYTES)
        .read_to_string()
        .ok()?;
    parse_usage_limits(&body)
}

pub(super) fn parse_usage_limits(body: &str) -> Option<CodexPlanSnapshot> {
    let value = serde_json::from_str::<Value>(body).ok()?;
    let plan_type = value
        .get("plan_type")
        .and_then(Value::as_str)
        .filter(|plan| !plan.is_empty())
        .unwrap_or("unknown")
        .to_string();
    let rate_limit = value.get("rate_limit")?;
    Some(CodexPlanSnapshot {
        plan_type,
        limit_id: Some("codex".to_string()),
        primary: rate_window(rate_limit.get("primary_window")),
        secondary: rate_window(rate_limit.get("secondary_window")),
    })
}

fn rate_window(value: Option<&Value>) -> Option<RateWindow> {
    let window = value.filter(|window| !window.is_null())?;
    let seconds = window.get("limit_window_seconds")?.as_u64()?;
    Some(RateWindow {
        used_percent: window.get("used_percent")?.as_f64()?,
        window_minutes: seconds / 60,
        resets_at: window.get("reset_at").and_then(Value::as_i64),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const LIVE_BODY: &str = r#"{
      "plan_type": "pro",
      "rate_limit": {
        "primary_window": {
          "used_percent": 85,
          "limit_window_seconds": 604800,
          "reset_at": 1788954006
        },
        "secondary_window": null
      },
      "additional_rate_limits": [
        {
          "limit_name": "GPT-5.3-Codex-Spark",
          "rate_limit": {
            "primary_window": {"used_percent": 0, "limit_window_seconds": 18000, "reset_at": 1},
            "secondary_window": {"used_percent": 100, "limit_window_seconds": 604800, "reset_at": 2}
          }
        }
      ]
    }"#;

    #[test]
    fn reads_account_weekly_used_percent_and_ignores_spark() {
        let snapshot = parse_usage_limits(LIVE_BODY).unwrap();

        assert_eq!(snapshot.plan_type, "pro");
        assert_eq!(snapshot.limit_id.as_deref(), Some("codex"));
        assert_eq!(
            snapshot.weekly_window(),
            Some(RateWindow {
                used_percent: 85.0,
                window_minutes: 10080,
                resets_at: Some(1788954006),
            })
        );
        assert!(snapshot.short_window().is_none());
    }

    #[test]
    fn reads_access_token_from_auth_json() {
        let json = r#"{"tokens":{"access_token":"tok-live","refresh_token":"r"}}"#;
        assert_eq!(access_token_from_auth(json).as_deref(), Some("tok-live"));
    }

    #[test]
    fn ignores_empty_access_token() {
        assert_eq!(
            access_token_from_auth(r#"{"tokens":{"access_token":""}}"#),
            None
        );
    }
}
