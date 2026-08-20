use crate::{
    BucketKind, LoadedEntry, Result,
    cli::{AgentReportKind, WeekDay},
    summarize_by_key, summarize_summaries_by_bucket,
};

pub(crate) fn summarize_entries(
    entries: &[LoadedEntry],
    kind: AgentReportKind,
) -> Result<Vec<crate::UsageSummary>> {
    match kind {
        AgentReportKind::Daily => summarize_by_key(
            entries,
            |entry| entry.date.clone(),
            |date| (date.to_string(), None),
        ),
        AgentReportKind::Monthly => {
            let daily = summarize_entries(entries, AgentReportKind::Daily)?;
            Ok(summarize_summaries_by_bucket(
                &daily,
                BucketKind::Monthly,
                WeekDay::Sunday,
            ))
        }
        AgentReportKind::Session => summarize_by_key(
            entries,
            |entry| entry.session_id.to_string(),
            |session_id| (session_id.to_string(), None),
        )
        .map(|mut rows| {
            for row in &mut rows {
                row.session_id = row.date.take();
            }
            rows
        }),
        AgentReportKind::Weekly => {
            let daily = summarize_entries(entries, AgentReportKind::Daily)?;
            Ok(summarize_summaries_by_bucket(
                &daily,
                BucketKind::Weekly,
                WeekDay::Sunday,
            ))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{PricingMap, TimestampMs, cli::CostMode};

    use super::super::parser::{CursorUsageRow, rows_to_entries};

    #[test]
    fn summarizes_fixture_day_into_cursor_totals() {
        let row = CursorUsageRow {
            timestamp: TimestampMs::from_millis(1_787_097_600_000),
            date: "2026-08-19".into(),
            model: "claude-4.6-sonnet".into(),
            input_tokens: 20,
            output_tokens: 40,
            cache_creation_tokens: 10,
            cache_read_tokens: 30,
            cost_usd: Some(2.5),
        };
        let entries = rows_to_entries(&[row], CostMode::Auto, &PricingMap::load_embedded(), None);
        let daily = summarize_entries(&entries, AgentReportKind::Daily).unwrap();
        assert_eq!(daily.len(), 1);
        assert_eq!(daily[0].date.as_deref(), Some("2026-08-19"));
        assert_eq!(daily[0].input_tokens, 20);
        assert_eq!(daily[0].output_tokens, 40);
        assert_eq!(daily[0].cache_creation_tokens, 10);
        assert_eq!(daily[0].cache_read_tokens, 30);
        assert_eq!(daily[0].total_cost, 2.5);
    }
}
