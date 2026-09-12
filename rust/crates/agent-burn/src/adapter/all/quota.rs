use serde_json::{Value, json};

use crate::{
    TimestampMs,
    adapter::{claude, codex, cursor},
    utc_now,
};

/// Private app collector protocol. Never scan logs or label a cached limit as live.
pub(super) fn snapshot(agent: &str, offline: bool) -> Option<Value> {
    let (used, minutes, reset) = match agent {
        "codex" => {
            let window = codex::usage_limits(offline)?.weekly_window()?;
            (
                window.used_percent,
                window.window_minutes,
                TimestampMs::from_unix_seconds(window.resets_at?)?,
            )
        }
        "claude" => {
            let window = claude::usage_limits(offline)?.seven_day?;
            (window.utilization, 10080, window.resets_at?)
        }
        "cursor" => {
            let account = cursor::load_account(offline)?;
            cursor::live_window(&account, utc_now())?
        }
        _ => return None,
    };
    reading(agent, used, minutes, reset, utc_now())
}

/// Cursor promo credits are optional. A skip payload keeps collection green
/// when the signed-in account has no burning promotional grant.
pub(super) fn cursor_snapshot(offline: bool) -> Value {
    snapshot("cursor", offline).unwrap_or_else(|| {
        json!({
            "agent": "cursor",
            "observedAt": utc_now().as_millis(),
        })
    })
}

fn reading(
    agent: &str,
    used: f64,
    minutes: u64,
    reset: TimestampMs,
    now: TimestampMs,
) -> Option<Value> {
    let duration = i64::try_from(minutes).ok()?.checked_mul(60_000)?;
    let start = reset.checked_sub_millis(duration)?;
    if duration == 0
        || !used.is_finite()
        || !(0.0..=100.0).contains(&used)
        || now < start
        || now >= reset
    {
        return None;
    }
    Some(json!({
        "agent": agent,
        "observedAt": now.as_millis(),
        "window": {
            "windowMinutes": minutes,
            "usedPercent": used,
            "elapsedPercent": now.duration_since(start) as f64 / duration as f64 * 100.0,
            "apiEquivalentSpent": 0
        }
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_expired_and_invalid_live_windows() {
        let now = TimestampMs::from_unix_seconds(1_800_000_000).unwrap();
        assert!(reading("codex", 14.0, 10080, now, now).is_none());
        let reset = now.checked_add_millis(86_400_000).unwrap();
        assert!(reading("codex", -1.0, 10080, reset, now).is_none());
        assert!(reading("codex", 101.0, 10080, reset, now).is_none());
        let output = reading("codex", 14.0, 10080, reset, now).unwrap();
        assert_eq!(output["observedAt"], now.as_millis());
        assert_eq!(output["window"]["usedPercent"], 14.0);
    }
}
