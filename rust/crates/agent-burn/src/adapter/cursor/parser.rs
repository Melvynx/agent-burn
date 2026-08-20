use std::sync::Arc;

use jiff::tz::TimeZone as JiffTimeZone;
use serde_json::Value;

use crate::{
    LoadedEntry, PricingMap, TimestampMs, TokenUsageRaw, UsageEntry, UsageMessage,
    calculate_cost_for_usage, cli::CostMode, format_date_tz, format_rfc3339_millis,
    missing_pricing_model_for_candidates,
};

#[cfg(test)]
use crate::{parse_iso_date, parse_ts_timestamp};

#[cfg(test)]
const DATE: &str = "Date";
#[cfg(test)]
const MODEL: &str = "Model";
#[cfg(test)]
const CACHE_WRITE: &str = "Input (w/ Cache Write)";
#[cfg(test)]
const INPUT: &str = "Input (w/o Cache Write)";
#[cfg(test)]
const CACHE_READ: &str = "Cache Read";
#[cfg(test)]
const OUTPUT: &str = "Output Tokens";

#[derive(Debug, Clone, PartialEq)]
pub(super) struct CursorUsageRow {
    pub(super) timestamp: TimestampMs,
    pub(super) date: String,
    pub(super) model: String,
    pub(super) input_tokens: u64,
    pub(super) output_tokens: u64,
    pub(super) cache_creation_tokens: u64,
    pub(super) cache_read_tokens: u64,
    pub(super) cost_usd: Option<f64>,
}

#[cfg(test)]
pub(super) fn parse_csv(csv: &str, timezone: Option<&JiffTimeZone>) -> Vec<CursorUsageRow> {
    let mut lines = csv.lines().filter(|line| !line.trim().is_empty());
    let Some(header) = lines.next() else {
        return Vec::new();
    };
    let headers = parse_csv_row(header);
    let date_i = column_index(&headers, DATE);
    let model_i = column_index(&headers, MODEL);
    let cache_write_i = column_index(&headers, CACHE_WRITE);
    let input_i = column_index(&headers, INPUT);
    let cache_read_i = column_index(&headers, CACHE_READ);
    let output_i = column_index(&headers, OUTPUT);
    let (
        Some(date_i),
        Some(model_i),
        Some(cache_write_i),
        Some(input_i),
        Some(cache_read_i),
        Some(output_i),
    ) = (
        date_i,
        model_i,
        cache_write_i,
        input_i,
        cache_read_i,
        output_i,
    )
    else {
        return Vec::new();
    };
    let cost_i = headers
        .iter()
        .enumerate()
        .find_map(|(index, header)| cost_column_kind(header).map(|kind| (index, kind)));

    let mut rows = Vec::new();
    for line in lines {
        let fields = parse_csv_row(line);
        let Some(date) = fields
            .get(date_i)
            .map(String::as_str)
            .filter(|value| !value.is_empty())
        else {
            continue;
        };
        let Some(model) = fields
            .get(model_i)
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty())
        else {
            continue;
        };
        let Some(cache_creation_tokens) =
            fields.get(cache_write_i).and_then(|value| parse_u64(value))
        else {
            continue;
        };
        let Some(input_tokens) = fields.get(input_i).and_then(|value| parse_u64(value)) else {
            continue;
        };
        let Some(cache_read_tokens) = fields.get(cache_read_i).and_then(|value| parse_u64(value))
        else {
            continue;
        };
        let Some(output_tokens) = fields.get(output_i).and_then(|value| parse_u64(value)) else {
            continue;
        };
        if input_tokens == 0
            && output_tokens == 0
            && cache_creation_tokens == 0
            && cache_read_tokens == 0
        {
            continue;
        }
        let Some((timestamp, date)) = parse_usage_date(date, timezone) else {
            continue;
        };
        let cost_usd = cost_i
            .and_then(|(index, kind)| fields.get(index).and_then(|value| parse_cost(value, kind)));
        rows.push(CursorUsageRow {
            timestamp,
            date,
            model,
            input_tokens,
            output_tokens,
            cache_creation_tokens,
            cache_read_tokens,
            cost_usd,
        });
    }
    rows
}

pub(super) fn parse_aggregations(
    value: &Value,
    date: &str,
    timestamp: TimestampMs,
) -> Vec<CursorUsageRow> {
    let Some(aggregations) = value.get("aggregations").and_then(Value::as_array) else {
        return Vec::new();
    };
    aggregations
        .iter()
        .filter_map(|row| {
            let model = row
                .get("modelIntent")
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|model| !model.is_empty())?
                .to_string();
            let input_tokens = json_u64(row.get("inputTokens"));
            let output_tokens = json_u64(row.get("outputTokens"));
            let cache_creation_tokens = json_u64(row.get("cacheWriteTokens"));
            let cache_read_tokens = json_u64(row.get("cacheReadTokens"));
            if input_tokens == 0
                && output_tokens == 0
                && cache_creation_tokens == 0
                && cache_read_tokens == 0
            {
                return None;
            }
            let cost_usd = row.get("totalCents").and_then(json_cents);
            Some(CursorUsageRow {
                timestamp,
                date: date.to_string(),
                model,
                input_tokens,
                output_tokens,
                cache_creation_tokens,
                cache_read_tokens,
                cost_usd,
            })
        })
        .collect()
}

pub(super) fn rows_to_entries(
    rows: &[CursorUsageRow],
    mode: CostMode,
    pricing: &PricingMap,
    timezone: Option<&JiffTimeZone>,
) -> Vec<LoadedEntry> {
    rows.iter()
        .map(|row| {
            let usage = TokenUsageRaw {
                input_tokens: row.input_tokens,
                output_tokens: row.output_tokens,
                cache_creation_input_tokens: row.cache_creation_tokens,
                cache_read_input_tokens: row.cache_read_tokens,
                speed: None,
                cache_creation: None,
            };
            let candidates = model_candidates(&row.model);
            let priced_model = candidates
                .iter()
                .find(|candidate| pricing.find(candidate).is_some())
                .cloned();
            let cost = calculate_cost_for_usage(
                priced_model.as_deref(),
                usage,
                row.cost_usd,
                mode,
                Some(pricing),
            );
            let missing_pricing_model = if mode == CostMode::Display
                || (mode == CostMode::Auto && row.cost_usd.is_some())
            {
                None
            } else {
                missing_pricing_model_for_candidates(
                    &row.model,
                    candidates,
                    row.input_tokens
                        + row.output_tokens
                        + row.cache_creation_tokens
                        + row.cache_read_tokens,
                    Some(pricing),
                )
            };
            let date = if row.date.is_empty() {
                format_date_tz(row.timestamp, timezone)
            } else {
                row.date.clone()
            };
            LoadedEntry {
                date,
                timestamp: row.timestamp,
                project: Arc::from("cursor"),
                session_id: Arc::from(row.date.as_str()),
                project_path: Arc::from("Cursor"),
                cost,
                extra_total_tokens: 0,
                credits: None,
                model: Some(row.model.clone()),
                usage_limit_reset_time: None,
                missing_pricing_model,
                message_count: None,
                data: UsageEntry {
                    session_id: Some(row.date.clone()),
                    timestamp: format_rfc3339_millis(row.timestamp),
                    version: None,
                    message: UsageMessage {
                        usage,
                        model: Some(row.model.clone()),
                        id: Some(format!("{}:{}", row.date, row.model)),
                    },
                    cost_usd: row.cost_usd,
                    request_id: None,
                    is_api_error_message: None,
                    is_sidechain: None,
                },
            }
        })
        .collect()
}

pub(super) fn model_candidates(model: &str) -> Vec<String> {
    let mut candidates = vec![model.to_string()];
    let stripped = model.strip_prefix("cursor-").unwrap_or(model).to_string();
    if stripped != model {
        candidates.push(stripped.clone());
    }
    let mut current = stripped;
    for suffix in [
        "-xhigh-fast",
        "-high-fast",
        "-medium-fast",
        "-low-fast",
        "-thinking-high",
        "-thinking-medium",
        "-thinking-low",
        "-medium-thinking",
        "-high-thinking",
        "-low-thinking",
        "-thinking",
        "-xhigh",
        "-high",
        "-medium",
        "-fast",
        "-low",
    ] {
        if let Some(next) = current.strip_suffix(suffix) {
            current = next.to_string();
            candidates.push(current.clone());
        }
    }
    let mut seen = std::collections::HashSet::new();
    candidates.retain(|candidate| seen.insert(candidate.clone()));
    candidates
}

#[cfg(test)]
fn column_index(headers: &[String], name: &str) -> Option<usize> {
    headers.iter().position(|header| header == name)
}

#[cfg(test)]
#[derive(Clone, Copy)]
enum CostKind {
    Cents,
    Dollars,
}

#[cfg(test)]
fn cost_column_kind(header: &str) -> Option<CostKind> {
    let header = header.to_ascii_lowercase();
    if header.contains("cent") {
        Some(CostKind::Cents)
    } else if header == "cost" || header.contains("cost (usd)") || header == "total cost" {
        Some(CostKind::Dollars)
    } else {
        None
    }
}

#[cfg(test)]
fn parse_cost(raw: &str, kind: CostKind) -> Option<f64> {
    let value = raw.trim();
    if value.is_empty() {
        return None;
    }
    let number = value.trim_start_matches('$').parse::<f64>().ok()?;
    if !number.is_finite() || number < 0.0 {
        return None;
    }
    Some(match kind {
        CostKind::Cents => number / 100.0,
        CostKind::Dollars => number,
    })
}

fn parse_u64(raw: &str) -> Option<u64> {
    let value = raw.trim();
    if value.is_empty() {
        return Some(0);
    }
    let parsed = value.parse::<i64>().ok()?;
    u64::try_from(parsed).ok()
}

fn json_u64(value: Option<&Value>) -> u64 {
    match value {
        Some(Value::Number(number)) => number.as_u64().or_else(|| {
            number
                .as_f64()
                .and_then(|value| (value >= 0.0).then_some(value as u64))
        }),
        Some(Value::String(text)) => parse_u64(text),
        _ => Some(0),
    }
    .unwrap_or(0)
}

fn json_cents(value: &Value) -> Option<f64> {
    let cents = match value {
        Value::Number(number) => number.as_f64(),
        Value::String(text) => text.parse().ok(),
        _ => None,
    }?;
    (cents.is_finite() && cents > 0.0).then_some(cents / 100.0)
}

#[cfg(test)]
fn parse_usage_date(raw: &str, timezone: Option<&JiffTimeZone>) -> Option<(TimestampMs, String)> {
    let raw = raw.trim();
    if let Some(timestamp) = parse_ts_timestamp(raw).or_else(|| parse_loose_datetime(raw)) {
        return Some((timestamp, format_date_tz(timestamp, timezone)));
    }
    let date = parse_iso_date(raw)?;
    let timestamp = crate::TimestampMs::from_millis(
        date.days_since_epoch()
            .checked_mul(crate::MILLIS_PER_DAY)?
            .checked_add(12 * crate::MILLIS_PER_HOUR)?,
    );
    Some((
        timestamp,
        format!("{:04}-{:02}-{:02}", date.year, date.month, date.day),
    ))
}

#[cfg(test)]
fn parse_loose_datetime(raw: &str) -> Option<TimestampMs> {
    if raw.len() == 19 && raw.as_bytes().get(10) == Some(&b' ') {
        let iso = format!("{}T{}Z", &raw[..10], &raw[11..]);
        return parse_ts_timestamp(&iso);
    }
    None
}

#[cfg(test)]
fn parse_csv_row(line: &str) -> Vec<String> {
    let mut fields = Vec::new();
    let mut current = String::new();
    let mut chars = line.chars().peekable();
    let mut in_quotes = false;
    while let Some(ch) = chars.next() {
        match ch {
            '"' if in_quotes => {
                if chars.peek() == Some(&'"') {
                    chars.next();
                    current.push('"');
                } else {
                    in_quotes = false;
                }
            }
            '"' => in_quotes = true,
            ',' if !in_quotes => {
                fields.push(std::mem::take(&mut current));
            }
            _ => current.push(ch),
        }
    }
    fields.push(current);
    fields
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::PricingMap;

    const CSV: &str = "Date,Model,Input (w/ Cache Write),Input (w/o Cache Write),Cache Read,Output Tokens,totalCents\n\
2026-08-19,claude-4.6-sonnet,10,20,30,40,250\n\
2026-08-19 11:22:33,composer-2.5,0,5,0,7,\n\
2026-08-20,bad-row,nope,1,1,1,0\n\
2026-08-20,,1,1,1,1,0\n";

    #[test]
    fn parses_csv_token_splits_and_native_cents() {
        let rows = parse_csv(CSV, None);
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[0].model, "claude-4.6-sonnet");
        assert_eq!(rows[0].input_tokens, 20);
        assert_eq!(rows[0].cache_creation_tokens, 10);
        assert_eq!(rows[0].cache_read_tokens, 30);
        assert_eq!(rows[0].output_tokens, 40);
        assert_eq!(rows[0].date, "2026-08-19");
        assert_eq!(rows[0].cost_usd, Some(2.5));
        assert_eq!(rows[1].model, "composer-2.5");
        assert_eq!(rows[1].input_tokens, 5);
        assert_eq!(rows[1].output_tokens, 7);
        assert_eq!(rows[1].cost_usd, None);
    }

    #[test]
    fn drops_csv_when_required_columns_are_missing() {
        let rows = parse_csv("Date,Model,Output Tokens\n2026-08-19,claude,4\n", None);
        assert!(rows.is_empty());
    }

    #[test]
    fn parses_aggregated_usage_events_for_one_day() {
        let value = serde_json::json!({
            "aggregations": [
                {
                    "modelIntent": "cursor-grok-4.6-high-fast",
                    "inputTokens": "11",
                    "outputTokens": "22",
                    "cacheReadTokens": "33",
                    "tier": 2
                },
                { "modelIntent": "empty-model", "tier": 1 },
                {
                    "modelIntent": "claude-4.6-sonnet-medium-thinking",
                    "inputTokens": "1",
                    "outputTokens": "2",
                    "cacheWriteTokens": "3",
                    "cacheReadTokens": "4",
                    "totalCents": 150.0
                }
            ]
        });
        let timestamp = TimestampMs::from_millis(1_755_561_600_000);
        let rows = parse_aggregations(&value, "2026-08-19", timestamp);
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[0].model, "cursor-grok-4.6-high-fast");
        assert_eq!(rows[0].input_tokens, 11);
        assert_eq!(rows[0].cache_read_tokens, 33);
        assert_eq!(rows[0].cost_usd, None);
        assert_eq!(rows[1].cost_usd, Some(1.5));
        assert_eq!(rows[1].cache_creation_tokens, 3);
    }

    #[test]
    fn calculate_mode_ignores_native_cents() {
        let row = CursorUsageRow {
            timestamp: TimestampMs::from_millis(1_755_561_600_000),
            date: "2026-08-19".into(),
            model: "unknown-cursor-model".into(),
            input_tokens: 10,
            output_tokens: 10,
            cache_creation_tokens: 0,
            cache_read_tokens: 0,
            cost_usd: Some(9.99),
        };
        let entries = rows_to_entries(
            &[row],
            CostMode::Calculate,
            &PricingMap::load_embedded(),
            None,
        );
        assert_eq!(entries[0].cost, 0.0);
        assert_eq!(
            entries[0].missing_pricing_model.as_deref(),
            Some("unknown-cursor-model")
        );
    }

    #[test]
    fn zero_native_cents_fall_back_to_pricing() {
        let value = serde_json::json!({
            "aggregations": [{
                "modelIntent": "unknown-cursor-model",
                "inputTokens": "10",
                "outputTokens": "10",
                "totalCents": 0
            }]
        });
        let rows = parse_aggregations(&value, "2026-08-19", TimestampMs::from_millis(1));
        assert_eq!(rows[0].cost_usd, None);
        let entries = rows_to_entries(&rows, CostMode::Auto, &PricingMap::load_embedded(), None);
        assert_eq!(
            entries[0].missing_pricing_model.as_deref(),
            Some("unknown-cursor-model")
        );
    }

    #[test]
    fn auto_mode_keeps_native_cents() {
        let row = CursorUsageRow {
            timestamp: TimestampMs::from_millis(1_755_561_600_000),
            date: "2026-08-19".into(),
            model: "unknown-cursor-model".into(),
            input_tokens: 10,
            output_tokens: 10,
            cache_creation_tokens: 0,
            cache_read_tokens: 0,
            cost_usd: Some(9.99),
        };
        let entries = rows_to_entries(&[row], CostMode::Auto, &PricingMap::load_embedded(), None);
        assert_eq!(entries[0].cost, 9.99);
        assert_eq!(entries[0].missing_pricing_model, None);
    }

    #[test]
    fn strips_cursor_quality_suffixes_for_pricing_candidates() {
        assert_eq!(
            model_candidates("cursor-grok-4.6-high-fast"),
            vec![
                "cursor-grok-4.6-high-fast",
                "grok-4.6-high-fast",
                "grok-4.6",
            ]
        );
    }
}
