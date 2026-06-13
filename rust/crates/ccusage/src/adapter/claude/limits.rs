use std::{fs, time::Duration};

use serde_json::Value;

use crate::{TimestampMs, home, parse_ts_timestamp};

const USAGE_URL: &str = "https://api.anthropic.com/api/oauth/usage";
const FETCH_TIMEOUT_SECONDS: u64 = 5;
const FETCH_MAX_BYTES: u64 = 1_000_000;

/// A live Claude rate-limit window from the OAuth usage endpoint.
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct UsageWindow {
    pub(crate) utilization: f64,
    pub(crate) resets_at: Option<TimestampMs>,
}

/// The 5h and 7-day usage windows reported for the signed-in Claude account.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub(crate) struct ClaudeUsageLimits {
    pub(crate) five_hour: Option<UsageWindow>,
    pub(crate) seven_day: Option<UsageWindow>,
}

/// Fetch the signed-in account's live usage limits from Anthropic, mirroring
/// the call Claude Code's status line makes. Returns `None` when offline, when
/// no OAuth token is available, or on any network error (never fatal).
pub(crate) fn usage_limits(offline: bool) -> Option<ClaudeUsageLimits> {
    if offline {
        return None;
    }
    let token = oauth_token()?;
    fetch_usage_limits(&token)
}

fn oauth_token() -> Option<String> {
    #[cfg(target_os = "macos")]
    if let Some(token) = keychain_token() {
        return Some(token);
    }
    file_token()
}

#[cfg(target_os = "macos")]
fn keychain_token() -> Option<String> {
    let output = std::process::Command::new("security")
        .args([
            "find-generic-password",
            "-s",
            "Claude Code-credentials",
            "-w",
        ])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let json = String::from_utf8(output.stdout).ok()?;
    token_from_credentials(&json)
}

fn file_token() -> Option<String> {
    let path = home::home_dir()?.join(".claude").join(".credentials.json");
    token_from_credentials(&fs::read_to_string(path).ok()?)
}

fn token_from_credentials(json: &str) -> Option<String> {
    let value = serde_json::from_str::<Value>(json.trim()).ok()?;
    value
        .get("claudeAiOauth")?
        .get("accessToken")?
        .as_str()
        .map(str::to_string)
}

fn fetch_usage_limits(token: &str) -> Option<ClaudeUsageLimits> {
    let agent = ureq::Agent::config_builder()
        .timeout_global(Some(Duration::from_secs(FETCH_TIMEOUT_SECONDS)))
        .build()
        .new_agent();
    let mut response = agent
        .get(USAGE_URL)
        .header("Authorization", &format!("Bearer {token}"))
        .header("anthropic-beta", "oauth-2025-04-20")
        .header("Accept", "application/json")
        .header("User-Agent", concat!("ccusage/", env!("CARGO_PKG_VERSION")))
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

fn parse_usage_limits(body: &str) -> Option<ClaudeUsageLimits> {
    let value = serde_json::from_str::<Value>(body).ok()?;
    Some(ClaudeUsageLimits {
        five_hour: parse_window(value.get("five_hour")),
        seven_day: parse_window(value.get("seven_day")),
    })
}

fn parse_window(value: Option<&Value>) -> Option<UsageWindow> {
    let window = value.filter(|window| !window.is_null())?;
    Some(UsageWindow {
        utilization: window.get("utilization")?.as_f64()?,
        resets_at: window
            .get("resets_at")
            .and_then(Value::as_str)
            .and_then(parse_reset_time),
    })
}

/// Parse an RFC 3339 reset time, tolerating the sub-millisecond precision the
/// usage endpoint emits (e.g. `…:59.434813+00:00`) which the strict shared
/// parser rejects. Sub-second digits are truncated to milliseconds.
fn parse_reset_time(value: &str) -> Option<TimestampMs> {
    if let Some(timestamp) = parse_ts_timestamp(value) {
        return Some(timestamp);
    }
    let dot = value.find('.')?;
    let after = &value[dot + 1..];
    let fractional_len = after.bytes().take_while(u8::is_ascii_digit).count();
    let millis: String = after[..fractional_len]
        .chars()
        .chain(std::iter::repeat('0'))
        .take(3)
        .collect();
    let normalized = format!("{}.{millis}{}", &value[..dot], &after[fractional_len..]);
    parse_ts_timestamp(&normalized)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::format_rfc3339_millis;

    #[test]
    fn parses_usage_windows_from_response_body() {
        let body = r#"{"five_hour":{"utilization":23,"resets_at":"2026-06-13T15:39:59.434793+00:00"},"seven_day":{"utilization":12,"resets_at":"2026-06-14T08:59:59.434813+00:00"}}"#;

        let limits = parse_usage_limits(body).unwrap();

        let seven_day = limits.seven_day.unwrap();
        assert_eq!(seven_day.utilization, 12.0);
        assert_eq!(
            format_rfc3339_millis(seven_day.resets_at.unwrap()),
            "2026-06-14T08:59:59.434Z"
        );
        assert_eq!(limits.five_hour.unwrap().utilization, 23.0);
    }

    #[test]
    fn treats_null_windows_as_absent() {
        let limits = parse_usage_limits(r#"{"five_hour":null,"seven_day":null}"#).unwrap();
        assert_eq!(limits, ClaudeUsageLimits::default());
    }

    #[test]
    fn reads_access_token_from_credentials_json() {
        let json = r#"{"claudeAiOauth":{"accessToken":"sk-ant-oat-abc","refreshToken":"r","expiresAt":1}}"#;
        assert_eq!(
            token_from_credentials(json).as_deref(),
            Some("sk-ant-oat-abc")
        );
    }
}
