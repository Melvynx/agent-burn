use serde_json::{Value, json};

use super::report::agent_label;
use super::types::AllRow;
use crate::{Color, cli::SharedArgs, fast::FxHashMap, json_float, short_model_name};

/// Width, in cells, of the stacked daily bar in the terminal chart.
const CHART_WIDTH: usize = 30;
/// Distinct top models given their own colour in the CLI chart; rest = "other".
const TOP_MODELS: usize = 5;
/// CLI palette per top-model slot; "other" uses grey. No white (too harsh).
const CLI_PALETTE: [Color; TOP_MODELS] = [
    Color::Green,
    Color::Magenta,
    Color::Blue,
    Color::Yellow,
    Color::Cyan,
];

/// Web palette (hex): a refined dark-mode categorical scale, deliberately
/// avoiding pure white so the dominant model doesn't blow out the chart. Top-8
/// models get a distinct colour; the rest fold into the grey "other".
const WEB_PALETTE: [&str; 8] = [
    "#7c83ff", // indigo  (rank 0 — was harsh white)
    "#2dd4bf", // teal
    "#f59e0b", // amber
    "#f472b6", // pink
    "#60a5fa", // blue
    "#a3e635", // lime
    "#c084fc", // purple
    "#fb7185", // rose
];
/// Colour for every model outside the top palette (folded into "other").
const OTHER_COLOR: &str = "#52525b";

/// Hex colour for an agent, keyed off its canonical name (family colours).
fn agent_hex(agent: &str) -> &'static str {
    match agent {
        "claude" => "#d96bf5",
        "codex" => "#34d399",
        "gemini" => "#60a5fa",
        "droid" => "#fbbf24",
        "openclaw" | "opencode" => "#22d3ee",
        "pi" => "#a78bfa",
        "amp" => "#fb7185",
        _ => "#94a3b8",
    }
}

/// Total token count across a model breakdown.
fn model_tokens(model: &crate::ModelBreakdown) -> u64 {
    model.input_tokens
        + model.output_tokens
        + model.cache_creation_tokens
        + model.cache_read_tokens
        + model.extra_total_tokens
}

/// All models ranked by all-time cost (descending): `(name, cost, tokens)`.
fn ranked_models(rows: &[AllRow]) -> Vec<(String, f64, u64)> {
    let mut totals: FxHashMap<String, (f64, u64)> = FxHashMap::default();
    for row in rows {
        for model in &row.model_breakdowns {
            let entry = totals.entry(model.model_name.clone()).or_default();
            entry.0 += model.cost;
            entry.1 += model_tokens(model);
        }
    }
    let mut ranked: Vec<(String, f64, u64)> = totals
        .into_iter()
        .map(|(name, (cost, tokens))| (name, cost, tokens))
        .collect();
    ranked.sort_by(|a, b| b.1.total_cmp(&a.1));
    ranked
}

/// Web colour for a model at the given all-time cost rank.
fn web_model_color(rank: usize) -> &'static str {
    WEB_PALETTE.get(rank).copied().unwrap_or(OTHER_COLOR)
}

/// Full interactive dashboard payload: every model and agent with a stable
/// colour, plus a per-day cost/token matrix so the browser can re-filter any
/// date range client-side without re-reading the logs.
pub(super) fn dashboard_data(rows: &[AllRow]) -> Value {
    let ranked = ranked_models(rows);
    let model_index: FxHashMap<&str, usize> = ranked
        .iter()
        .enumerate()
        .map(|(i, (name, _, _))| (name.as_str(), i))
        .collect();

    // Agents, ranked by all-time cost.
    let mut agent_totals: FxHashMap<&'static str, (f64, u64)> = FxHashMap::default();
    for row in rows {
        if let Some(breakdowns) = row.agent_breakdowns.as_ref() {
            for b in breakdowns {
                let entry = agent_totals.entry(b.agent).or_default();
                entry.0 += b.total_cost;
                entry.1 += b.total_tokens;
            }
        }
    }
    let mut agents: Vec<(&'static str, f64, u64)> = agent_totals
        .into_iter()
        .map(|(agent, (cost, tokens))| (agent, cost, tokens))
        .collect();
    agents.sort_by(|a, b| b.1.total_cmp(&a.1));
    let agent_index: FxHashMap<&str, usize> = agents
        .iter()
        .enumerate()
        .map(|(i, (agent, _, _))| (*agent, i))
        .collect();

    let days = rows
        .iter()
        .map(|row| {
            let mut mc = vec![0.0_f64; ranked.len()];
            let mut mt = vec![0u64; ranked.len()];
            for model in &row.model_breakdowns {
                if let Some(&i) = model_index.get(model.model_name.as_str()) {
                    mc[i] += model.cost;
                    mt[i] += model_tokens(model);
                }
            }
            let mut ac = vec![0.0_f64; agents.len()];
            let mut at = vec![0u64; agents.len()];
            if let Some(breakdowns) = row.agent_breakdowns.as_ref() {
                for b in breakdowns {
                    if let Some(&i) = agent_index.get(b.agent) {
                        ac[i] += b.total_cost;
                        at[i] += b.total_tokens;
                    }
                }
            }
            json!({
                "d": row.period,
                "mc": mc.iter().map(|c| json_float(*c)).collect::<Vec<_>>(),
                "mt": mt,
                "ac": ac.iter().map(|c| json_float(*c)).collect::<Vec<_>>(),
                "at": at,
            })
        })
        .collect::<Vec<_>>();

    json!({
        "models": ranked.iter().enumerate().map(|(i, (name, cost, tokens))| json!({
            "model": name,
            "short": short_model_name(name),
            "color": web_model_color(i),
            "cost": json_float(*cost),
            "tokens": tokens,
        })).collect::<Vec<_>>(),
        "agents": agents.iter().map(|(agent, cost, tokens)| json!({
            "agent": agent_label(agent),
            "color": agent_hex(agent),
            "cost": json_float(*cost),
            "tokens": tokens,
        })).collect::<Vec<_>>(),
        "history": {
            "otherColor": OTHER_COLOR,
            "days": days,
        },
    })
}

// ---- Terminal chart (burn summary --chart) ---------------------------------

struct DailyByModel {
    legend: Vec<String>,
    days: Vec<(String, Vec<f64>, f64)>,
}

fn daily_by_model(rows: &[AllRow], limit: usize) -> DailyByModel {
    let ranked = ranked_models(rows);
    let top: Vec<String> = ranked
        .iter()
        .take(TOP_MODELS)
        .map(|(name, _, _)| name.clone())
        .collect();
    let index: FxHashMap<&str, usize> = top
        .iter()
        .enumerate()
        .map(|(i, name)| (name.as_str(), i))
        .collect();
    let has_other = ranked.len() > top.len();
    let series_len = (top.len() + usize::from(has_other)).max(1);

    let recent = &rows[rows.len().saturating_sub(limit)..];
    let days = recent
        .iter()
        .map(|row| {
            let mut per = vec![0.0_f64; series_len];
            for model in &row.model_breakdowns {
                let slot = index
                    .get(model.model_name.as_str())
                    .copied()
                    .unwrap_or(top.len());
                if slot < per.len() {
                    per[slot] += model.cost;
                }
            }
            let total = per.iter().sum();
            (row.period.clone(), per, total)
        })
        .collect();

    let mut legend: Vec<String> = top.iter().map(|name| short_model_name(name)).collect();
    if has_other {
        legend.push("other".to_string());
    }
    DailyByModel { legend, days }
}

fn series_color(index: usize) -> Color {
    CLI_PALETTE.get(index).copied().unwrap_or(Color::Grey)
}

pub(super) fn print_daily_by_model(rows: &[AllRow], shared: &SharedArgs) {
    let chart = daily_by_model(rows, 21);
    if chart.days.is_empty() {
        return;
    }
    let mut out = format!("\n  daily cost by model · last {}d\n", chart.days.len());

    out.push_str("  ");
    for (i, label) in chart.legend.iter().enumerate() {
        out.push_str(&crate::color(shared, "\u{2588} ", series_color(i)));
        out.push_str(&crate::color(shared, format!("{label}  "), Color::Grey));
    }
    out.push('\n');

    let max_total = chart
        .days
        .iter()
        .map(|(_, _, total)| *total)
        .fold(0.0, f64::max);
    let cost_width = chart
        .days
        .iter()
        .map(|(_, _, total)| crate::format_currency(*total).len())
        .max()
        .unwrap_or(0);
    for (date, per, total) in &chart.days {
        out.push_str("    ");
        out.push_str(&crate::color(shared, date.clone(), Color::Grey));
        out.push_str("  ");
        out.push_str(&stacked_bar(shared, per, *total, max_total));
        out.push_str("  ");
        out.push_str(&crate::color(
            shared,
            format!("{:>cost_width$}", crate::format_currency(*total)),
            Color::Green,
        ));
        out.push('\n');
    }
    print!("{out}");
}

/// A single day's stacked bar: length scaled to the busiest day, segments
/// proportional to each model's share of that day.
fn stacked_bar(shared: &SharedArgs, per: &[f64], total: f64, max_total: f64) -> String {
    let bar_len = if max_total > 0.0 && total > 0.0 {
        ((total / max_total) * CHART_WIDTH as f64).round().max(1.0) as usize
    } else {
        0
    }
    .min(CHART_WIDTH);

    let mut bar = String::new();
    let mut filled = 0usize;
    if bar_len > 0 && total > 0.0 {
        let last = per.iter().rposition(|cost| *cost > 0.0);
        for (i, cost) in per.iter().enumerate() {
            if *cost <= 0.0 {
                continue;
            }
            let mut seg = ((cost / total) * bar_len as f64).round() as usize;
            if Some(i) == last {
                seg = bar_len.saturating_sub(filled);
            }
            seg = seg.min(bar_len - filled);
            if seg == 0 {
                continue;
            }
            bar.push_str(&crate::color(
                shared,
                "\u{2588}".repeat(seg),
                series_color(i),
            ));
            filled += seg;
        }
    }
    bar.push_str(&crate::color(
        shared,
        "\u{2591}".repeat(CHART_WIDTH - filled),
        Color::Grey,
    ));
    bar
}
