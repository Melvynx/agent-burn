use std::time::Duration;

use jiff::tz::TimeZone as JiffTimeZone;
use serde_json::{Value, json};

use crate::{
    IsoDate, LoadedEntry, PricingMap, Result, TimestampMs, cli::SharedArgs, debug_log,
    parse_iso_date, parse_tz, utc_now,
};

use super::{
    parser::{parse_aggregations, rows_to_entries},
    paths::credentials,
};

const AGGREGATED_USAGE_URL: &str =
    "https://api2.cursor.sh/aiserver.v1.DashboardService/GetAggregatedUsageEvents";
const PERIOD_USAGE_URL: &str =
    "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage";
const FETCH_TIMEOUT_SECONDS: u64 = 8;
const FETCH_MAX_BYTES: u64 = 4_000_000;
const DEFAULT_LOOKBACK_DAYS: i64 = 31;

pub(crate) fn load_entries(shared: &SharedArgs, pricing: &PricingMap) -> Result<Vec<LoadedEntry>> {
    crate::progress::track_usage_load(crate::progress::UsageLoadAgent::Cursor, shared.json, || {
        Ok(load_entries_inner(shared, pricing))
    })
}

fn load_entries_inner(shared: &SharedArgs, pricing: &PricingMap) -> Vec<LoadedEntry> {
    if shared.offline {
        return Vec::new();
    }
    let Some(token) = credentials().token else {
        return Vec::new();
    };
    let timezone = parse_tz(shared.timezone.as_deref());
    let agent = http_agent();
    let Some((from, to)) = usage_window(&agent, shared, &token, timezone.as_ref()) else {
        return Vec::new();
    };
    let mut rows = Vec::new();
    let mut date = from;
    let mut consecutive_failures = 0u8;
    while date.days_since_epoch() <= to.days_since_epoch() {
        let Some((start, end)) = day_bounds(date, timezone.as_ref()) else {
            break;
        };
        let day = format!("{:04}-{:02}-{:02}", date.year, date.month, date.day);
        match fetch_json(
            &agent,
            AGGREGATED_USAGE_URL,
            &token,
            json!({
                "teamId": -1,
                "startDate": start.as_millis(),
                "endDate": end.as_millis(),
            }),
        ) {
            Some(value) => {
                consecutive_failures = 0;
                rows.extend(parse_aggregations(&value, &day, start));
            }
            None => {
                consecutive_failures += 1;
                debug_log(shared, format!("Failed to load Cursor usage for {day}"));
                if consecutive_failures >= 3 && rows.is_empty() {
                    eprintln!("WARN  Failed to load Cursor usage from the dashboard API.");
                    break;
                }
            }
        }
        let Some(next) = date.checked_add_days(1) else {
            break;
        };
        date = next;
    }
    rows_to_entries(&rows, shared.mode, pricing, timezone.as_ref())
}

fn usage_window(
    agent: &ureq::Agent,
    shared: &SharedArgs,
    token: &str,
    timezone: Option<&JiffTimeZone>,
) -> Option<(IsoDate, IsoDate)> {
    let today = parse_iso_date(&crate::format_date_tz(utc_now(), timezone))?;
    let until = shared
        .until
        .as_deref()
        .and_then(parse_compact_date)
        .unwrap_or(today);
    if let Some(since) = shared.since.as_deref().and_then(parse_compact_date) {
        return Some((since, until));
    }
    if let Some(start) = billing_cycle_start(agent, token, timezone) {
        return Some((start, until));
    }
    let from = today.checked_add_days(1 - DEFAULT_LOOKBACK_DAYS)?;
    Some((from, until))
}

fn billing_cycle_start(
    agent: &ureq::Agent,
    token: &str,
    timezone: Option<&JiffTimeZone>,
) -> Option<IsoDate> {
    let value = fetch_json(agent, PERIOD_USAGE_URL, token, json!({}))?;
    let millis = value.get("billingCycleStart").and_then(json_millis)?;
    parse_iso_date(&crate::format_date_tz(
        TimestampMs::from_millis(millis),
        timezone,
    ))
}

fn parse_compact_date(value: &str) -> Option<IsoDate> {
    let digits = value.replace('-', "");
    if digits.len() != 8 {
        return None;
    }
    let year = digits[0..4].parse().ok()?;
    let month = digits[4..6].parse().ok()?;
    let day = digits[6..8].parse().ok()?;
    IsoDate::from_ymd(year, month, day)
}

fn day_bounds(
    date: IsoDate,
    timezone: Option<&JiffTimeZone>,
) -> Option<(TimestampMs, TimestampMs)> {
    Some((
        local_midnight(date, timezone)?,
        local_midnight(date.checked_add_days(1)?, timezone)?,
    ))
}

fn local_midnight(date: IsoDate, timezone: Option<&JiffTimeZone>) -> Option<TimestampMs> {
    let year = i16::try_from(date.year).ok()?;
    let month = i8::try_from(date.month).ok()?;
    let day = i8::try_from(date.day).ok()?;
    let civil = jiff::civil::Date::new(year, month, day).ok()?;
    let tz = timezone.cloned().unwrap_or_else(JiffTimeZone::system);
    let zoned = civil.at(0, 0, 0, 0).to_zoned(tz).ok()?;
    Some(TimestampMs::from_millis(zoned.timestamp().as_millisecond()))
}

fn json_millis(value: &Value) -> Option<i64> {
    match value {
        Value::Number(number) => number.as_i64(),
        Value::String(text) => text.parse().ok(),
        _ => None,
    }
}

fn http_agent() -> ureq::Agent {
    ureq::Agent::config_builder()
        .timeout_global(Some(Duration::from_secs(FETCH_TIMEOUT_SECONDS)))
        .build()
        .new_agent()
}

fn fetch_json(agent: &ureq::Agent, url: &str, token: &str, body: Value) -> Option<Value> {
    let payload = serde_json::to_vec(&body).ok()?;
    let mut response = agent
        .post(url)
        .header("Authorization", &format!("Bearer {token}"))
        .header("Content-Type", "application/json")
        .header("Accept", "application/json")
        .header("Connect-Protocol-Version", "1")
        .header(
            "User-Agent",
            concat!("agent-burn/", env!("CARGO_PKG_VERSION")),
        )
        .send(payload)
        .ok()?;
    if response.status().as_u16() != 200 {
        return None;
    }
    let text = response
        .body_mut()
        .with_config()
        .limit(FETCH_MAX_BYTES)
        .read_to_string()
        .ok()?;
    serde_json::from_str(&text).ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cli::SharedArgs;

    #[test]
    fn offline_loads_no_cursor_rows() {
        let shared = SharedArgs {
            offline: true,
            ..SharedArgs::default()
        };
        let rows = load_entries_inner(&shared, &PricingMap::load_embedded());
        assert!(rows.is_empty());
    }

    #[test]
    fn parses_compact_date_bounds() {
        let date = parse_compact_date("20260819").unwrap();
        assert_eq!((date.year, date.month, date.day), (2026, 8, 19));
        assert_eq!(parse_compact_date("2026-08-19").unwrap().day, 19);
    }

    #[test]
    fn day_bounds_use_timezone_midnight() {
        let date = IsoDate::from_ymd(2026, 8, 19).unwrap();
        let tz = JiffTimeZone::get("Europe/Zurich").unwrap();
        let (start, end) = day_bounds(date, Some(&tz)).unwrap();
        assert_eq!(start.as_millis(), 1_787_090_400_000);
        assert_eq!(end.as_millis() - start.as_millis(), crate::MILLIS_PER_DAY);
    }
}
