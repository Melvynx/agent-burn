use serde_json::{Value, json};

use super::{AllRow, Summary};
use crate::json_float;

/// Add daily and per-harness detail without changing existing summary totals.
pub(super) fn to_json(summary: &Summary, rows: &[AllRow]) -> Value {
    let mut output = summary.to_json();
    output["daily"] = daily_json(summary);
    for (agent, value) in summary
        .agents
        .iter()
        .zip(output["agents"].as_array_mut().unwrap())
    {
        let own_rows: Vec<AllRow> = rows
            .iter()
            .filter_map(|row| {
                let own = if row.agent == agent.agent {
                    Some(row)
                } else {
                    row.agent_breakdowns
                        .as_ref()?
                        .iter()
                        .find(|item| item.agent == agent.agent)
                }?;
                Some(AllRow {
                    period: row.period.clone(),
                    ..own.clone()
                })
            })
            .collect();
        let own = Summary::from_rows(&own_rows);
        value["models"] = own.to_json()["models"].take();
        value["daily"] = daily_json(&own);
        value["tokenBreakdown"] = json!({
            "input": own_rows.iter().map(|row| row.input_tokens).sum::<u64>(),
            "output": own_rows.iter().map(|row| row.output_tokens).sum::<u64>(),
            "cacheWrite": own_rows.iter().map(|row| row.cache_creation_tokens).sum::<u64>(),
            "cacheRead": own_rows.iter().map(|row| row.cache_read_tokens).sum::<u64>(),
        });
    }
    output
}

fn daily_json(summary: &Summary) -> Value {
    json!(
        summary
            .days
            .iter()
            .map(|day| json!({
                "date": day.date,
                "cost": json_float(day.cost),
                "tokens": day.tokens,
            }))
            .collect::<Vec<_>>()
    )
}
