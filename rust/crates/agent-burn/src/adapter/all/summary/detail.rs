use serde_json::{Value, json};

use super::{AllRow, Summary};
use crate::{adapter::cursor, json_float};

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
        value["daily"] = if agent.agent == "cursor" {
            cursor_daily_json(&own, &own_rows)
        } else {
            daily_json(&own)
        };
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

fn cursor_daily_json(summary: &Summary, rows: &[AllRow]) -> Value {
    json!(
        summary
            .days
            .iter()
            .map(|day| {
                let (cursor_cost, cursor_tokens) = cursor_models_for_day(rows, &day.date);
                json!({
                    "date": day.date,
                    "cost": json_float(day.cost),
                    "tokens": day.tokens,
                    "cursorModelsCost": json_float(cursor_cost),
                    "cursorModelsTokens": cursor_tokens,
                })
            })
            .collect::<Vec<_>>()
    )
}

fn cursor_models_for_day(rows: &[AllRow], date: &str) -> (f64, u64) {
    rows.iter()
        .filter(|row| row.period == date)
        .flat_map(|row| row.model_breakdowns.iter())
        .filter(|model| cursor::is_cursor_model(&model.model_name))
        .fold((0.0, 0), |(cost, tokens), model| {
            (
                cost + model.cost,
                tokens
                    + model.input_tokens
                    + model.output_tokens
                    + model.cache_creation_tokens
                    + model.cache_read_tokens
                    + model.extra_total_tokens,
            )
        })
}
