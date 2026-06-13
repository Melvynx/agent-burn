use std::collections::BTreeSet;

use serde_json::{Value, json};

use crate::{
    Color, IsoDate, Result, TimestampMs,
    adapter::{claude, codex},
    cli::{AgentReportKind, SharedArgs, SummaryArgs, SummaryRange},
    fast::FxHashMap,
    format_currency, format_date_tz, format_utc_date, json_float, parse_iso_date, parse_tz,
    print_json_or_jq, utc_now, wants_json,
};

use super::{
    loader,
    report::agent_label,
    subscription::{self, ClaudeInput, CodexInput, Subscription, WeeklyView, WindowCost},
    types::AllRow,
};

/// Width, in cells, of the proportional cost bar drawn next to each model.
const BAR_WIDTH: usize = 16;

/// Number of top models shown in the table before the remainder is collapsed
/// into a single overflow line. JSON output always includes every model.
const MODEL_DISPLAY_LIMIT: usize = 10;

pub(super) fn run(args: SummaryArgs) -> Result<()> {
    let SummaryArgs {
        mut shared,
        value,
        claude_plan,
        codex_plan,
        range,
        agent,
        // HTML report wiring lands in a follow-up.
        html: _,
    } = args;
    if let Some(agent) = agent {
        return run_weekly(
            &agent,
            &shared,
            codex_plan.as_deref(),
            claude_plan.as_deref(),
        );
    }
    if let Some(range) = range {
        apply_range(&mut shared, range);
    }
    let result = loader::load_rows(AgentReportKind::Daily, &shared)?;
    let summary = Summary::from_rows(&result.rows);

    let subscription = if value {
        let agent_costs = summary.agent_costs();
        let has = |agent: &str| agent_costs.iter().any(|(name, _)| *name == agent);
        let codex_in = has("codex").then(|| codex_input(&result.rows)).flatten();
        let claude_in = has("claude")
            .then(|| claude_input(&result.rows, shared.offline))
            .flatten();
        let claude_tier = (has("claude") && claude_plan.is_none())
            .then(claude::detected_plan_tier)
            .flatten();
        Some(Subscription::build(
            &agent_costs,
            summary.period.clone(),
            codex_in,
            codex_plan.as_deref(),
            claude_in,
            claude_plan.as_deref(),
            claude_tier.as_deref(),
        ))
    } else {
        None
    };

    if wants_json(&shared) {
        let mut output = summary.to_json();
        if let (Some(object), Some(subscription)) = (output.as_object_mut(), subscription.as_ref())
        {
            object.insert("subscription".to_string(), subscription.to_json());
        }
        return print_json_or_jq(output, shared.jq.as_deref(), shared.no_cost);
    }

    print_summary(&summary, &shared, &result.detected_agents);
    if let Some(subscription) = subscription.as_ref() {
        subscription.print(&shared);
    }
    Ok(())
}

/// Resolve a quick time range into a `--since` bound, relative to today in the
/// configured timezone. Leaves `--until` open so the range runs through now.
fn apply_range(shared: &mut SharedArgs, range: SummaryRange) {
    let timezone = parse_tz(shared.timezone.as_deref());
    let today_str = format_date_tz(utc_now(), timezone.as_ref());
    let Some(today) = parse_iso_date(&today_str) else {
        return;
    };
    let start = match range {
        SummaryRange::Today => Some(today),
        SummaryRange::Wtd => {
            let days_since_monday = i64::from((today.weekday_from_sunday() + 6) % 7);
            today.checked_add_days(-days_since_monday)
        }
        SummaryRange::Mtd => IsoDate::from_ymd(today.year, today.month, 1),
        SummaryRange::Ytd => IsoDate::from_ymd(today.year, 1, 1),
        SummaryRange::Week => today.checked_add_days(-6),
        SummaryRange::Month => today.checked_add_days(-29),
    };
    if let Some(start) = start {
        shared.since = Some(format!(
            "{:04}{:02}{:02}",
            start.year, start.month, start.day
        ));
    }
}

/// Render the focused weekly-limit view for a single agent: limit-used vs
/// time-elapsed, the value extrapolation, and a day-by-day breakdown.
fn run_weekly(
    agent: &str,
    shared: &SharedArgs,
    codex_spec: Option<&str>,
    claude_spec: Option<&str>,
) -> Result<()> {
    let result = loader::load_rows(AgentReportKind::Daily, shared)?;
    let rows = &result.rows;

    let (plan_name, price, window, live_limits) = if agent == "codex" {
        match codex_input(rows) {
            Some(input) => {
                let (name, price) = subscription::resolve_codex(&input.plan_type, codex_spec);
                (Some(name), price, input.window, true)
            }
            None => (None, None, None, false),
        }
    } else {
        let tier = claude::detected_plan_tier();
        let (name, price) = subscription::resolve_claude(tier.as_deref(), claude_spec);
        match claude_input(rows, shared.offline) {
            Some(input) => (name, price, input.window, true),
            None => (name, price, None, false),
        }
    };

    let daily = window
        .as_ref()
        .map(|window| {
            let window_start = utc_now()
                .checked_sub_millis((window.elapsed_minutes * 60_000.0) as i64)
                .unwrap_or_else(utc_now);
            agent_daily_in_window(rows, window_start, agent)
        })
        .unwrap_or_default();

    let view = WeeklyView {
        agent,
        plan_name,
        price,
        window,
        daily,
        live_limits,
    };
    if wants_json(shared) {
        return print_json_or_jq(
            subscription::weekly_to_json(&view),
            shared.jq.as_deref(),
            shared.no_cost,
        );
    }
    subscription::print_weekly(&view, shared);
    Ok(())
}

/// Collect one agent's per-day cost across the window (full days, chronological).
fn agent_daily_in_window(
    rows: &[AllRow],
    window_start: TimestampMs,
    agent: &str,
) -> Vec<(String, f64)> {
    let start_date = format_utc_date(window_start);
    rows.iter()
        .filter(|row| row.period.as_str() >= start_date.as_str())
        .map(|row| {
            let cost = row
                .agent_breakdowns
                .as_ref()
                .and_then(|breakdowns| breakdowns.iter().find(|b| b.agent == agent))
                .map_or(0.0, |breakdown| breakdown.total_cost);
            (row.period.clone(), cost)
        })
        .collect()
}

/// Detect the Codex plan and measure spend over its live weekly limit window,
/// reusing the already-loaded daily rows (no extra log scan).
fn codex_input(rows: &[AllRow]) -> Option<CodexInput> {
    let snapshot = codex::latest_plan_snapshot()?;
    let window = snapshot.secondary.or(snapshot.primary).and_then(|basis| {
        let window_start =
            TimestampMs::from_unix_seconds(basis.resets_at? - (basis.window_minutes as i64) * 60)?;
        window_cost(
            basis.used_percent,
            basis.window_minutes,
            window_start,
            rows,
            "codex",
        )
    });
    Some(CodexInput {
        plan_type: snapshot.plan_type,
        window,
        short_window: snapshot
            .primary
            .map(|primary| (primary.window_minutes, primary.used_percent)),
    })
}

/// Fetch Claude's live limits from the OAuth usage endpoint and measure spend
/// over the weekly window from the already-loaded daily rows.
fn claude_input(rows: &[AllRow], offline: bool) -> Option<ClaudeInput> {
    const WEEKLY_MINUTES: u64 = 7 * 24 * 60;
    let limits = claude::usage_limits(offline)?;
    let window = limits.seven_day.and_then(|seven_day| {
        let window_start = seven_day
            .resets_at?
            .checked_sub_millis(WEEKLY_MINUTES as i64 * 60_000)?;
        window_cost(
            seven_day.utilization,
            WEEKLY_MINUTES,
            window_start,
            rows,
            "claude",
        )
    });
    Some(ClaudeInput {
        window,
        short_window: limits
            .five_hour
            .map(|five_hour| (5 * 60, five_hour.utilization)),
    })
}

/// Build a window-cost reading: API-equivalent spend over `[window_start, now]`
/// for one agent, given how much of the quota that window consumed.
fn window_cost(
    used_percent: f64,
    window_minutes: u64,
    window_start: TimestampMs,
    rows: &[AllRow],
    agent: &str,
) -> Option<WindowCost> {
    if used_percent <= 0.0 {
        return None;
    }
    let now = utc_now();
    if now <= window_start {
        return None;
    }
    Some(WindowCost {
        window_minutes,
        used_percent,
        elapsed_minutes: now.duration_since(window_start) as f64 / 60_000.0,
        cost: agent_cost_in_window(rows, window_start, agent),
    })
}

/// Sum one agent's per-day cost inside the window, prorating the first day by
/// the fraction of it that the window actually covers.
fn agent_cost_in_window(rows: &[AllRow], window_start: TimestampMs, agent: &str) -> f64 {
    let start_date = format_utc_date(window_start);
    let seconds_into_day = window_start
        .as_millis()
        .div_euclid(1_000)
        .rem_euclid(86_400) as f64;
    let start_day_fraction = (86_400.0 - seconds_into_day) / 86_400.0;
    rows.iter()
        .filter(|row| row.period.as_str() >= start_date.as_str())
        .map(|row| {
            let cost = row
                .agent_breakdowns
                .as_ref()
                .and_then(|breakdowns| breakdowns.iter().find(|b| b.agent == agent))
                .map_or(0.0, |breakdown| breakdown.total_cost);
            if row.period == start_date {
                cost * start_day_fraction
            } else {
                cost
            }
        })
        .sum()
}

struct AgentTotal {
    agent: &'static str,
    cost: f64,
    tokens: u64,
}

struct ModelTotal {
    model: String,
    cost: f64,
    tokens: u64,
}

struct Summary {
    total_cost: f64,
    total_tokens: u64,
    agents: Vec<AgentTotal>,
    models: Vec<ModelTotal>,
    period: Option<(String, String)>,
}

impl Summary {
    /// Collapse the per-day all-agent rows into a single aggregate: grand
    /// totals plus one entry per detected agent and per model, sorted by cost.
    fn from_rows(rows: &[AllRow]) -> Self {
        let mut total_cost = 0.0;
        let mut total_tokens = 0u64;
        let mut agents: Vec<AgentTotal> = Vec::new();
        let mut agent_index: FxHashMap<&'static str, usize> = FxHashMap::default();
        let mut models: Vec<ModelTotal> = Vec::new();
        let mut model_index: FxHashMap<String, usize> = FxHashMap::default();
        let mut first_period: Option<&str> = None;
        let mut last_period: Option<&str> = None;

        for row in rows {
            total_cost += row.total_cost;
            total_tokens += row.total_tokens;
            if first_period.is_none_or(|first| row.period.as_str() < first) {
                first_period = Some(&row.period);
            }
            if last_period.is_none_or(|last| row.period.as_str() > last) {
                last_period = Some(&row.period);
            }

            match row.agent_breakdowns.as_ref() {
                Some(breakdowns) => {
                    for breakdown in breakdowns {
                        add_agent(
                            &mut agents,
                            &mut agent_index,
                            breakdown.agent,
                            breakdown.total_cost,
                            breakdown.total_tokens,
                        );
                    }
                }
                None if row.agent != "all" => add_agent(
                    &mut agents,
                    &mut agent_index,
                    row.agent,
                    row.total_cost,
                    row.total_tokens,
                ),
                None => {}
            }

            for breakdown in &row.model_breakdowns {
                let tokens = breakdown.input_tokens
                    + breakdown.output_tokens
                    + breakdown.cache_creation_tokens
                    + breakdown.cache_read_tokens
                    + breakdown.extra_total_tokens;
                let index = *model_index
                    .entry(breakdown.model_name.clone())
                    .or_insert_with(|| {
                        models.push(ModelTotal {
                            model: breakdown.model_name.clone(),
                            cost: 0.0,
                            tokens: 0,
                        });
                        models.len() - 1
                    });
                models[index].cost += breakdown.cost;
                models[index].tokens += tokens;
            }
        }

        agents.sort_by(|a, b| {
            b.cost
                .total_cmp(&a.cost)
                .then_with(|| b.tokens.cmp(&a.tokens))
        });
        models.sort_by(|a, b| {
            b.cost
                .total_cmp(&a.cost)
                .then_with(|| b.tokens.cmp(&a.tokens))
        });

        Self {
            total_cost,
            total_tokens,
            agents,
            models,
            period: first_period
                .zip(last_period)
                .map(|(first, last)| (first.to_string(), last.to_string())),
        }
    }

    fn agent_costs(&self) -> Vec<(&'static str, f64)> {
        self.agents
            .iter()
            .map(|agent| (agent.agent, agent.cost))
            .collect()
    }

    fn is_empty(&self) -> bool {
        self.agents.is_empty() && self.models.is_empty()
    }

    fn to_json(&self) -> Value {
        json!({
            "totals": {
                "totalCost": json_float(self.total_cost),
                "totalTokens": self.total_tokens,
            },
            "agents": self
                .agents
                .iter()
                .map(|agent| json!({
                    "agent": agent.agent,
                    "totalCost": json_float(agent.cost),
                    "totalTokens": agent.tokens,
                }))
                .collect::<Vec<_>>(),
            "models": self
                .models
                .iter()
                .map(|model| json!({
                    "model": model.model,
                    "totalCost": json_float(model.cost),
                    "totalTokens": model.tokens,
                    "percentage": json_float(percentage(model.cost, self.total_cost)),
                }))
                .collect::<Vec<_>>(),
        })
    }
}

fn add_agent(
    agents: &mut Vec<AgentTotal>,
    agent_index: &mut FxHashMap<&'static str, usize>,
    agent: &'static str,
    cost: f64,
    tokens: u64,
) {
    let index = *agent_index.entry(agent).or_insert_with(|| {
        agents.push(AgentTotal {
            agent,
            cost: 0.0,
            tokens: 0,
        });
        agents.len() - 1
    });
    agents[index].cost += cost;
    agents[index].tokens += tokens;
}

fn print_summary(summary: &Summary, shared: &SharedArgs, detected_agents: &[&'static str]) {
    crate::print_box_title(&title(detected_agents), shared);
    if summary.is_empty() {
        eprintln!("No usage data found.");
        return;
    }

    let no_cost = shared.no_cost;
    let mut out = String::new();

    out.push_str(&heading(shared, "total"));
    out.push_str("    ");
    if !no_cost {
        out.push_str(&cost_cell(shared, summary.total_cost, 0, Color::Yellow));
        out.push_str("   ");
    }
    out.push_str(&token_cell(shared, summary.total_tokens, 0));
    out.push('\n');

    if !summary.agents.is_empty() {
        out.push('\n');
        out.push_str(&heading(shared, "agents"));
        let name_width = max_width(summary.agents.iter().map(|a| agent_label(a.agent).len()));
        let cost_width = max_width(summary.agents.iter().map(|a| format_currency(a.cost).len()));
        let token_width = max_width(
            summary
                .agents
                .iter()
                .map(|a| format_compact_tokens(a.tokens).len()),
        );
        for agent in &summary.agents {
            let color = agent_color(agent.agent);
            out.push_str("    ");
            out.push_str(&crate::color(
                shared,
                format!("{:<width$}", agent_label(agent.agent), width = name_width),
                color,
            ));
            out.push_str("   ");
            if !no_cost {
                out.push_str(&cost_cell(shared, agent.cost, cost_width, color));
                out.push_str("   ");
            }
            out.push_str(&token_cell(shared, agent.tokens, token_width));
            out.push('\n');
        }
    }

    if !summary.models.is_empty() {
        out.push('\n');
        out.push_str(&heading(shared, "models"));
        let value = |model: &ModelTotal| metric_value(model.cost, model.tokens, no_cost);
        let mut models: Vec<&ModelTotal> = summary.models.iter().collect();
        models.sort_by(|a, b| {
            value(b)
                .total_cmp(&value(a))
                .then_with(|| b.cost.total_cmp(&a.cost))
        });
        let total_value = metric_value(summary.total_cost, summary.total_tokens, no_cost);
        let max_value = models.first().map_or(0.0, |model| value(model));

        let shown = models.len().min(MODEL_DISPLAY_LIMIT);
        let visible = &models[..shown];
        let name_width = max_width(visible.iter().map(|model| model.model.len()));
        let primary_width = max_width(visible.iter().map(|model| {
            if no_cost {
                format_compact_tokens(model.tokens).len()
            } else {
                format_currency(model.cost).len()
            }
        }));
        let percentages: Vec<String> = visible
            .iter()
            .map(|model| format!("{:.1}%", percentage(value(model), total_value)))
            .collect();
        let percentage_width = max_width(percentages.iter().map(String::len));

        for (model, percentage) in visible.iter().zip(&percentages) {
            let color = family_color(&model.model);
            out.push_str("    ");
            out.push_str(&crate::color(
                shared,
                format!("{:<width$}", model.model, width = name_width),
                color,
            ));
            out.push_str("   ");
            if no_cost {
                out.push_str(&token_cell(shared, model.tokens, primary_width));
            } else {
                out.push_str(&cost_cell(shared, model.cost, primary_width, Color::Green));
            }
            out.push_str("  ");
            out.push_str(&crate::color(
                shared,
                format!("{percentage:>percentage_width$}"),
                Color::Grey,
            ));
            out.push_str("  ");
            out.push_str(&render_bar(value(model), max_value, color, shared));
            out.push('\n');
        }

        if let Some(rest) = models.get(shown..).filter(|rest| !rest.is_empty()) {
            let rest_cost = rest.iter().map(|model| model.cost).sum::<f64>();
            let rest_tokens = rest.iter().map(|model| model.tokens).sum::<u64>();
            let extra = if no_cost {
                format!("{} tokens", format_compact_tokens(rest_tokens))
            } else {
                format_currency(rest_cost)
            };
            out.push_str(&crate::color(
                shared,
                format!("    … +{} more models   {extra}", rest.len()),
                Color::Grey,
            ));
            out.push('\n');
        }
    }

    print!("{out}");
}

/// Pick a stable color for a model or agent name based on its provider family,
/// mirroring devrage's color-by-family layout within ccusage's palette.
fn family_color(name: &str) -> Color {
    let name = name.to_ascii_lowercase();
    if name.contains("claude") || name.contains("anthropic") {
        Color::Magenta
    } else if name.contains("gpt") || name.contains("codex") || name.contains("openai") {
        Color::Green
    } else if name.contains("gemini") {
        Color::Blue
    } else if name.contains("droid") {
        Color::Yellow
    } else {
        Color::Cyan
    }
}

/// Color for an agent row, keyed off the agent's canonical name.
fn agent_color(agent: &str) -> Color {
    match agent {
        "claude" => Color::Magenta,
        "codex" => Color::Green,
        "gemini" => Color::Blue,
        "droid" => Color::Yellow,
        _ => Color::Cyan,
    }
}

fn cost_cell(shared: &SharedArgs, cost: f64, width: usize, color: Color) -> String {
    crate::color(shared, format!("{:>width$}", format_currency(cost)), color)
}

fn token_cell(shared: &SharedArgs, tokens: u64, width: usize) -> String {
    let value = format!("{:>width$}", format_compact_tokens(tokens));
    format!(
        "{} {}",
        crate::color(shared, value, Color::Grey),
        crate::color(shared, "tokens", Color::Grey)
    )
}

fn render_bar(value: f64, max_value: f64, color: Color, shared: &SharedArgs) -> String {
    let filled = if max_value > 0.0 && value > 0.0 {
        ((value / max_value) * BAR_WIDTH as f64).round().max(1.0) as usize
    } else {
        0
    }
    .min(BAR_WIDTH);
    format!(
        "{}{}",
        crate::color(shared, "\u{2501}".repeat(filled), color),
        crate::color(shared, "\u{2500}".repeat(BAR_WIDTH - filled), Color::Grey),
    )
}

/// Render a section heading (e.g. `total`) followed by a newline. Left at the
/// terminal's default foreground so it stands out from the colored rows below.
fn heading(_shared: &SharedArgs, label: &str) -> String {
    format!("  {label}\n")
}

fn metric_value(cost: f64, tokens: u64, no_cost: bool) -> f64 {
    if no_cost { tokens as f64 } else { cost }
}

fn percentage(value: f64, total: f64) -> f64 {
    if total > 0.0 {
        value / total * 100.0
    } else {
        0.0
    }
}

fn max_width(widths: impl Iterator<Item = usize>) -> usize {
    widths.max().unwrap_or(0)
}

fn title(detected_agents: &[&'static str]) -> String {
    let labels = detected_agents
        .iter()
        .map(|agent| agent_label(agent))
        .collect::<BTreeSet<_>>();
    let detected = if labels.is_empty() {
        "None".to_string()
    } else {
        labels.into_iter().collect::<Vec<_>>().join(", ")
    };
    format!("Coding (Agent) CLI Usage Summary\nDetected: {detected}")
}

/// Format a token count compactly (e.g. `1.2B`, `847.2M`, `3.1M`, `999`).
fn format_compact_tokens(value: u64) -> String {
    const K: f64 = 1_000.0;
    const M: f64 = 1_000_000.0;
    const B: f64 = 1_000_000_000.0;
    const T: f64 = 1_000_000_000_000.0;
    let amount = value as f64;
    if amount >= T {
        format!("{:.1}T", amount / T)
    } else if amount >= B {
        format!("{:.1}B", amount / B)
    } else if amount >= M {
        format!("{:.1}M", amount / M)
    } else if amount >= K {
        format!("{:.1}K", amount / K)
    } else {
        value.to_string()
    }
}

#[cfg(test)]
mod tests {
    use crate::ModelBreakdown;

    use super::*;

    fn breakdown_row(agent: &'static str, cost: f64, tokens: u64) -> AllRow {
        AllRow {
            period: "2026-01-01".to_string(),
            agent,
            models_used: Vec::new(),
            input_tokens: tokens,
            output_tokens: 0,
            cache_creation_tokens: 0,
            cache_read_tokens: 0,
            total_tokens: tokens,
            total_cost: cost,
            metadata: None,
            metadata_agents: Some(vec![agent]),
            agent_breakdowns: None,
            model_breakdowns: Vec::new(),
        }
    }

    fn model_breakdown(name: &str, cost: f64, tokens: u64) -> ModelBreakdown {
        ModelBreakdown {
            model_name: name.to_string(),
            input_tokens: tokens,
            cost,
            ..ModelBreakdown::default()
        }
    }

    fn day_row(cost: f64, tokens: u64, agents: Vec<AllRow>, models: Vec<ModelBreakdown>) -> AllRow {
        AllRow {
            period: "2026-01-01".to_string(),
            agent: "all",
            models_used: Vec::new(),
            input_tokens: tokens,
            output_tokens: 0,
            cache_creation_tokens: 0,
            cache_read_tokens: 0,
            total_tokens: tokens,
            total_cost: cost,
            metadata: None,
            metadata_agents: Some(Vec::new()),
            agent_breakdowns: Some(agents),
            model_breakdowns: models,
        }
    }

    #[test]
    fn formats_compact_token_counts() {
        assert_eq!(format_compact_tokens(1_234_567_890), "1.2B");
        assert_eq!(format_compact_tokens(847_200_000), "847.2M");
        assert_eq!(format_compact_tokens(3_100_000), "3.1M");
        assert_eq!(format_compact_tokens(12_345), "12.3K");
        assert_eq!(format_compact_tokens(999), "999");
    }

    #[test]
    fn aggregates_totals_agents_and_models_across_days() {
        let rows = vec![
            day_row(
                10.0,
                100,
                vec![
                    breakdown_row("claude", 6.0, 60),
                    breakdown_row("codex", 4.0, 40),
                ],
                vec![
                    model_breakdown("claude-opus-4-8", 6.0, 60),
                    model_breakdown("gpt-5", 4.0, 40),
                ],
            ),
            day_row(
                5.0,
                50,
                vec![breakdown_row("claude", 5.0, 50)],
                vec![model_breakdown("claude-opus-4-8", 5.0, 50)],
            ),
        ];

        let summary = Summary::from_rows(&rows);

        assert!((summary.total_cost - 15.0).abs() < 1e-9);
        assert_eq!(summary.total_tokens, 150);

        assert_eq!(summary.agents.len(), 2);
        assert_eq!(summary.agents[0].agent, "claude");
        assert!((summary.agents[0].cost - 11.0).abs() < 1e-9);
        assert_eq!(summary.agents[0].tokens, 110);
        assert_eq!(summary.agents[1].agent, "codex");

        assert_eq!(summary.models.len(), 2);
        assert_eq!(summary.models[0].model, "claude-opus-4-8");
        assert!((summary.models[0].cost - 11.0).abs() < 1e-9);
        assert_eq!(summary.models[0].tokens, 110);
        assert_eq!(summary.models[1].model, "gpt-5");
    }

    #[test]
    fn percentage_handles_zero_total() {
        assert!((percentage(0.0, 0.0)).abs() < 1e-9);
        assert!((percentage(25.0, 100.0) - 25.0).abs() < 1e-9);
    }
}
