use std::fs;

use serde_json::Value;

use super::paths::{codex_usage_sources, collect_codex_usage_files};

/// A single rate-limit window reported by Codex (e.g. the 5h or weekly window).
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct RateWindow {
    pub(crate) used_percent: f64,
    pub(crate) window_minutes: u64,
    pub(crate) resets_at: Option<i64>,
}

/// The most recent plan / rate-limit snapshot found in the Codex session logs.
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct CodexPlanSnapshot {
    pub(crate) plan_type: String,
    pub(crate) primary: Option<RateWindow>,
    pub(crate) secondary: Option<RateWindow>,
}

/// Scan the newest Codex session files for the latest `rate_limits` payload,
/// which carries the user's `plan_type` and current limit utilization.
///
/// Only the most recent handful of session files are inspected, newest first,
/// so this stays cheap even with a large history.
pub(crate) fn latest_plan_snapshot() -> Option<CodexPlanSnapshot> {
    const MAX_FILES_SCANNED: usize = 8;

    let sources = codex_usage_sources().ok()?;
    let mut files = Vec::new();
    for source in &sources {
        files.extend(collect_codex_usage_files(&source.dir));
    }
    // Session file names are timestamp-prefixed, so lexical order is chronological.
    files.sort();
    for file in files.iter().rev().take(MAX_FILES_SCANNED) {
        if let Some(snapshot) = snapshot_from_file(file) {
            return Some(snapshot);
        }
    }
    None
}

fn snapshot_from_file(path: &std::path::Path) -> Option<CodexPlanSnapshot> {
    let contents = fs::read_to_string(path).ok()?;
    contents.lines().rev().find_map(|line| {
        line.contains("plan_type")
            .then(|| snapshot_from_line(line))?
    })
}

fn snapshot_from_line(line: &str) -> Option<CodexPlanSnapshot> {
    let value = serde_json::from_str::<Value>(line).ok()?;
    let rate_limits = find_rate_limits(&value)?;
    let plan_type = rate_limits.get("plan_type")?.as_str()?.to_string();
    Some(CodexPlanSnapshot {
        plan_type,
        primary: rate_window(rate_limits.get("primary")),
        secondary: rate_window(rate_limits.get("secondary")),
    })
}

fn find_rate_limits(value: &Value) -> Option<&Value> {
    if let Some(rate_limits) = value
        .get("payload")
        .and_then(|payload| payload.get("rate_limits"))
        && rate_limits.get("plan_type").is_some()
    {
        return Some(rate_limits);
    }
    find_rate_limits_recursive(value)
}

fn find_rate_limits_recursive(value: &Value) -> Option<&Value> {
    match value {
        Value::Object(map) => {
            if let Some(rate_limits) = map.get("rate_limits")
                && rate_limits.get("plan_type").is_some()
            {
                return Some(rate_limits);
            }
            map.values().find_map(find_rate_limits_recursive)
        }
        Value::Array(items) => items.iter().find_map(find_rate_limits_recursive),
        _ => None,
    }
}

fn rate_window(value: Option<&Value>) -> Option<RateWindow> {
    let window = value?;
    Some(RateWindow {
        used_percent: window.get("used_percent")?.as_f64()?,
        window_minutes: window.get("window_minutes")?.as_u64()?,
        resets_at: window.get("resets_at").and_then(Value::as_i64),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_plan_and_windows_from_token_count_line() {
        let line = r#"{"timestamp":"2026-06-13T10:09:32.856Z","type":"event_msg","payload":{"type":"token_count","info":{},"rate_limits":{"limit_id":"codex","primary":{"used_percent":17.0,"window_minutes":300,"resets_at":1781347306},"secondary":{"used_percent":7.0,"window_minutes":10080,"resets_at":1781764829},"plan_type":"pro"}}}"#;

        let snapshot = snapshot_from_line(line).unwrap();

        assert_eq!(snapshot.plan_type, "pro");
        assert_eq!(
            snapshot.primary,
            Some(RateWindow {
                used_percent: 17.0,
                window_minutes: 300,
                resets_at: Some(1781347306),
            })
        );
        assert_eq!(
            snapshot.secondary,
            Some(RateWindow {
                used_percent: 7.0,
                window_minutes: 10080,
                resets_at: Some(1781764829),
            })
        );
    }

    #[test]
    fn ignores_lines_without_plan_type() {
        let line = r#"{"type":"event_msg","payload":{"type":"token_count","info":{}}}"#;
        assert!(snapshot_from_line(line).is_none());
    }
}
