use std::{env, fs, path::PathBuf};

use serde_json::{Value, json};

use crate::{TimestampMs, home};

/// Anthropic's OAuth usage endpoint answers 429 when polled by several
/// processes each minute, so every `agent-burn` process shares one response.
pub(super) const FRESH_MS: i64 = 55_000;
/// Oldest body the quota collector records as a live observation; the app
/// rejects readings more than 90 seconds old.
pub(super) const LIVE_MS: i64 = 85_000;
/// How long a cached body may stand in for the live meter in reports.
pub(super) const STALE_MS: i64 = 15 * 60_000;
const MIN_BACKOFF_MS: i64 = 60_000;
/// Anthropic's Retry-After is honored in full (it reached 19 minutes and more).
/// Retrying earlier is answered with another 429, which kept the meter blocked
/// for hours. The cap only guards against a nonsensical header.
const MAX_BACKOFF_MS: i64 = 2 * 60 * 60_000;
/// A refused refresh token stays refused until `claude` signs in again, so
/// retries are spaced instead of hitting the token endpoint every minute.
const RENEW_BACKOFF_MS: i64 = 10 * 60_000;

#[derive(Clone, Debug, Default, PartialEq)]
pub(super) struct UsageCache {
    pub(super) fetched_at: Option<TimestampMs>,
    pub(super) body: Option<String>,
    pub(super) blocked_until: Option<TimestampMs>,
    pub(super) renew_blocked_until: Option<TimestampMs>,
}

impl UsageCache {
    pub(super) fn load() -> Self {
        path()
            .and_then(|path| fs::read_to_string(path).ok())
            .map(|text| Self::parse(&text))
            .unwrap_or_default()
    }

    fn parse(text: &str) -> Self {
        let Ok(value) = serde_json::from_str::<Value>(text) else {
            return Self::default();
        };
        let millis = |key: &str| {
            value
                .get(key)
                .and_then(Value::as_i64)
                .map(TimestampMs::from_millis)
        };
        Self {
            fetched_at: millis("fetchedAt"),
            body: value
                .get("body")
                .and_then(Value::as_str)
                .map(str::to_string),
            blocked_until: millis("blockedUntil"),
            renew_blocked_until: millis("renewBlockedUntil"),
        }
    }

    /// Body younger than `max_age_ms`, with the time it was fetched.
    pub(super) fn body_within(
        &self,
        now: TimestampMs,
        max_age_ms: i64,
    ) -> Option<(&str, TimestampMs)> {
        let fetched_at = self.fetched_at?;
        let age = now.duration_since(fetched_at);
        ((0..max_age_ms).contains(&age))
            .then_some(())
            .and(self.body.as_deref())
            .map(|body| (body, fetched_at))
    }

    pub(super) fn is_blocked(&self, now: TimestampMs) -> bool {
        self.blocked_until.is_some_and(|until| now < until)
    }

    pub(super) fn store_body(&mut self, body: String, now: TimestampMs) {
        self.fetched_at = Some(now);
        self.body = Some(body);
        self.blocked_until = None;
        self.save();
    }

    pub(super) fn store_rate_limit(&mut self, retry_after_seconds: Option<i64>, now: TimestampMs) {
        self.blocked_until = now.checked_add_millis(backoff_ms(retry_after_seconds));
        self.save();
    }

    /// Keeps a reading another client (Claude Code) fetched when it is newer
    /// than ours, so it outlives that client's cache and is shared with every
    /// `agent-burn` process. Rate-limit state is left untouched.
    pub(super) fn adopt(&mut self, reading: Option<(String, TimestampMs)>, now: TimestampMs) {
        let Some((body, fetched_at)) = reading else {
            return;
        };
        if fetched_at > now || self.fetched_at.is_some_and(|ours| ours >= fetched_at) {
            return;
        }
        self.fetched_at = Some(fetched_at);
        self.body = Some(body);
        self.save();
    }

    /// A hard refresh retries a refused refresh right away.
    pub(super) fn renew_due(&self, now: TimestampMs, force: bool) -> bool {
        force || self.renew_blocked_until.is_none_or(|until| now >= until)
    }

    pub(super) fn store_renewal(&mut self, renewed: bool, now: TimestampMs) {
        let blocked_until = if renewed {
            None
        } else {
            now.checked_add_millis(RENEW_BACKOFF_MS)
        };
        if self.renew_blocked_until != blocked_until {
            self.renew_blocked_until = blocked_until;
            self.save();
        }
    }

    fn to_json(&self) -> Value {
        json!({
            "fetchedAt": self.fetched_at.map(TimestampMs::as_millis),
            "body": self.body,
            "blockedUntil": self.blocked_until.map(TimestampMs::as_millis),
            "renewBlockedUntil": self.renew_blocked_until.map(TimestampMs::as_millis),
        })
    }

    fn save(&self) {
        let Some(path) = path() else { return };
        if let Some(parent) = path.parent() {
            let _ = fs::create_dir_all(parent);
        }
        let temp = path.with_extension(format!("json.{}", std::process::id()));
        if fs::write(&temp, self.to_json().to_string()).is_ok() {
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                let _ = fs::set_permissions(&temp, fs::Permissions::from_mode(0o600));
            }
            if fs::rename(&temp, &path).is_err() {
                let _ = fs::remove_file(&temp);
            }
        }
    }
}

fn backoff_ms(retry_after_seconds: Option<i64>) -> i64 {
    retry_after_seconds
        .and_then(|seconds| seconds.checked_mul(1000))
        .unwrap_or(MIN_BACKOFF_MS)
        .clamp(MIN_BACKOFF_MS, MAX_BACKOFF_MS)
}

fn path() -> Option<PathBuf> {
    if cfg!(test) {
        return None;
    }
    if let Some(dir) = env::var_os("AGENT_BURN_CACHE_DIR") {
        return Some(PathBuf::from(dir).join("claude-usage.json"));
    }
    let home = home::home_dir()?;
    #[cfg(target_os = "macos")]
    let base = home.join("Library/Caches/agent-burn");
    #[cfg(not(target_os = "macos"))]
    let base = env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| home.join(".cache"))
        .join("agent-burn");
    Some(base.join("claude-usage.json"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(seconds: i64) -> TimestampMs {
        TimestampMs::from_unix_seconds(1_800_000_000 + seconds).unwrap()
    }

    #[test]
    fn serves_body_only_inside_the_requested_age() {
        let cache = UsageCache {
            fetched_at: Some(at(0)),
            body: Some("{}".into()),
            ..UsageCache::default()
        };
        assert_eq!(cache.body_within(at(30), FRESH_MS), Some(("{}", at(0))));
        assert_eq!(cache.body_within(at(60), FRESH_MS), None);
        assert!(cache.body_within(at(600), STALE_MS).is_some());
        assert_eq!(cache.body_within(at(-5), FRESH_MS), None);
    }

    #[test]
    fn round_trips_through_json() {
        let cache = UsageCache {
            fetched_at: Some(at(0)),
            body: Some(r#"{"five_hour":null}"#.into()),
            blocked_until: Some(at(174)),
            renew_blocked_until: Some(at(600)),
        };
        assert_eq!(UsageCache::parse(&cache.to_json().to_string()), cache);
        assert_eq!(UsageCache::parse("not json"), UsageCache::default());
    }

    #[test]
    fn spaces_refused_renewals_and_lets_a_hard_refresh_retry() {
        let mut cache = UsageCache::default();
        assert!(cache.renew_due(at(0), false));
        cache.store_renewal(false, at(0));
        assert!(!cache.renew_due(at(60), false));
        assert!(cache.renew_due(at(60), true));
        assert!(cache.renew_due(at(600), false));
        cache.store_renewal(true, at(600));
        assert_eq!(cache.renew_blocked_until, None);
    }

    #[test]
    fn clamps_retry_after_into_a_sane_backoff() {
        assert_eq!(backoff_ms(Some(174)), 174_000);
        assert_eq!(backoff_ms(Some(1149)), 1_149_000);
        assert_eq!(backoff_ms(Some(1)), MIN_BACKOFF_MS);
        assert_eq!(backoff_ms(None), MIN_BACKOFF_MS);
        assert_eq!(backoff_ms(Some(86_400)), MAX_BACKOFF_MS);
        let cache = UsageCache {
            blocked_until: at(0).checked_add_millis(backoff_ms(Some(174))),
            ..UsageCache::default()
        };
        assert!(cache.is_blocked(at(173)));
        assert!(!cache.is_blocked(at(174)));
    }
}
