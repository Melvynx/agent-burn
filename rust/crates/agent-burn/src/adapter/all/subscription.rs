use serde_json::{Value, json};

use crate::{Color, cli::SharedArgs, format_currency, json_float};

/// Average days per month, for normalising a window's value to a monthly figure.
const DAYS_PER_MONTH: f64 = 30.4375;

/// API-equivalent spend measured over a single rate-limit window.
pub(super) struct WindowCost {
    pub(super) window_minutes: u64,
    pub(super) used_percent: f64,
    pub(super) elapsed_minutes: f64,
    pub(super) cost: f64,
}

/// Live Codex limit input: the plan from the logs plus the weekly window.
pub(super) struct CodexInput {
    pub(super) plan_type: String,
    pub(super) window: Option<WindowCost>,
    pub(super) short_window: Option<(u64, f64)>,
}

/// Live Claude limit input from the OAuth usage endpoint.
pub(super) struct ClaudeInput {
    pub(super) window: Option<WindowCost>,
    pub(super) short_window: Option<(u64, f64)>,
}

/// A resolved monthly plan price.
struct PlanInfo {
    /// Known plan label (e.g. `Max 20×`); `None` for a raw price override.
    name: Option<String>,
    price: f64,
}

/// One agent's resolved subscription value, ready to render.
struct AgentValue {
    agent: &'static str,
    plan_name: Option<String>,
    price: Option<f64>,
    period_usage: f64,
    window: Option<WindowCost>,
    short_window: Option<(u64, f64)>,
    live_limits: bool,
}

pub(super) struct Subscription {
    period: Option<(String, String)>,
    agents: Vec<AgentValue>,
}

/// The dollar value of a full quota window, extrapolated from how much
/// API-equivalent usage produced the consumed percentage.
struct QuotaValue {
    full_quota: f64,
    monthly: f64,
    projected_use_percent: f64,
}

impl Subscription {
    /// Pair per-agent spend with auto-detected plans and live limits.
    ///
    /// `agents` is `(agent, period_usage_cost)`. Codex's plan comes from its
    /// logs; Claude's from the account file (`claude_detected_tier`). Either
    /// `*_spec` overrides the detected plan with a name or raw monthly price.
    #[allow(clippy::too_many_arguments)]
    pub(super) fn build(
        agents: &[(&'static str, f64)],
        period: Option<(String, String)>,
        codex_input: Option<CodexInput>,
        codex_spec: Option<&str>,
        claude_input: Option<ClaudeInput>,
        claude_spec: Option<&str>,
        claude_detected_tier: Option<&str>,
    ) -> Self {
        let cost_of = |agent: &str| {
            agents
                .iter()
                .find(|(name, _)| *name == agent)
                .map(|(_, cost)| *cost)
        };
        let mut values = Vec::new();

        if let (Some(period_usage), Some(input)) = (cost_of("codex"), codex_input) {
            let (plan_name, price) = resolve_codex(&input.plan_type, codex_spec);
            values.push(AgentValue {
                agent: "codex",
                plan_name: Some(plan_name),
                price,
                period_usage,
                window: input.window,
                short_window: input.short_window,
                live_limits: true,
            });
        }

        if let Some(period_usage) = cost_of("claude") {
            let (plan_name, price) = resolve_claude(claude_detected_tier, claude_spec);
            let (window, short_window, live_limits) = match claude_input {
                Some(input) => (input.window, input.short_window, true),
                None => (None, None, false),
            };
            values.push(AgentValue {
                agent: "claude",
                plan_name,
                price,
                period_usage,
                window,
                short_window,
                live_limits,
            });
        }

        Self {
            period,
            agents: values,
        }
    }

    pub(super) fn to_json(&self) -> Value {
        json!({
            "period": self.period.as_ref().map(|(from, to)| json!({ "from": from, "to": to })),
            "agents": self.agents.iter().map(agent_json).collect::<Vec<_>>(),
        })
    }

    pub(super) fn print(&self, shared: &SharedArgs) {
        let mut out = String::from("\n  subscription value");
        if let Some((from, to)) = self.period.as_ref() {
            out.push_str(&crate::color(
                shared,
                format!("  ·  {from} → {to}"),
                Color::Grey,
            ));
        }
        out.push('\n');

        if self.agents.is_empty() {
            out.push_str(&crate::color(
                shared,
                "    no agent usage to value",
                Color::Grey,
            ));
            out.push('\n');
        }
        for agent in &self.agents {
            print_agent(&mut out, agent, self.period.as_ref(), shared);
        }
        print!("{out}");
    }
}

fn print_agent(
    out: &mut String,
    agent: &AgentValue,
    period: Option<&(String, String)>,
    shared: &SharedArgs,
) {
    out.push_str("    ");
    out.push_str(&crate::color(
        shared,
        format!("{}  ·  {}", agent.agent, plan_label(agent)),
        agent_color(agent.agent),
    ));
    out.push('\n');

    match agent.window.as_ref().and_then(quota_value) {
        Some(quota) => print_extrapolation(out, agent, &quota, shared),
        None => print_period_only(out, agent, period, shared),
    }

    if let Some((minutes, percent)) = agent.short_window {
        out.push_str(&detail(
            shared,
            format!("{} window: {percent:.0}% used", window_label(minutes)),
        ));
    }
}

fn print_extrapolation(
    out: &mut String,
    agent: &AgentValue,
    quota: &QuotaValue,
    shared: &SharedArgs,
) {
    let window = agent.window.as_ref().expect("window present");
    let elapsed_days = window.elapsed_minutes / 1440.0;
    let resets_in_days = (window.window_minutes as f64 - window.elapsed_minutes).max(0.0) / 1440.0;
    let label = window_label(window.window_minutes);

    out.push_str(&detail(
        shared,
        format!(
            "{label} limit {:.0}% used over {elapsed_days:.1}d · resets in {resets_in_days:.1}d · {} API-equiv spent",
            window.used_percent,
            money(window.cost),
        ),
    ));
    out.push_str(&detail(
        shared,
        format!(
            "→ full {label} quota ≈ {}  ·  ≈ {}/mo of API usage",
            money(quota.full_quota),
            money(quota.monthly),
        ),
    ));
    if let Some(price) = agent.price {
        out.push_str("      ");
        out.push_str(&crate::color(
            shared,
            format!(
                "→ quota worth up to {:.0}× your ${price:.0}/mo plan",
                quota.monthly / price
            ),
            Color::Yellow,
        ));
        out.push('\n');
    } else {
        out.push_str(&detail(
            shared,
            format!(
                "pass --{}-plan <PRICE> to turn this into a value multiple",
                agent.agent
            ),
        ));
    }
    out.push_str(&detail(
        shared,
        format!(
            "on pace to use ~{:.0}% of the {label} quota by reset",
            quota.projected_use_percent
        ),
    ));
    if window.used_percent < 3.0 {
        out.push_str(&detail(
            shared,
            format!(
                "rough estimate — only {:.0}% of the quota sampled so far",
                window.used_percent
            ),
        ));
    }
}

fn print_period_only(
    out: &mut String,
    agent: &AgentValue,
    period: Option<&(String, String)>,
    shared: &SharedArgs,
) {
    let span = period
        .map(|(from, to)| format!(" ({from} → {to})"))
        .unwrap_or_default();
    match agent.price {
        Some(price) => out.push_str(&detail(
            shared,
            format!(
                "spent {} this period{span} → {:.1}× the ${price:.0}/mo plan",
                money(agent.period_usage),
                agent.period_usage / price,
            ),
        )),
        None => {
            out.push_str(&detail(
                shared,
                format!("spent {} this period{span}", money(agent.period_usage)),
            ));
            out.push_str(&detail(
                shared,
                format!("pass --{}-plan <PRICE> for a value ratio", agent.agent),
            ));
        }
    }
    let note = if agent.live_limits {
        "not enough usage in the current limit window to extrapolate yet"
    } else {
        "no live limits available to extrapolate a weekly quota"
    };
    out.push_str(&detail(shared, note.to_string()));
}

fn plan_label(agent: &AgentValue) -> String {
    plan_label_parts(agent.plan_name.as_deref(), agent.price)
}

fn agent_color(agent: &str) -> Color {
    match agent {
        "claude" => Color::Magenta,
        "codex" => Color::Green,
        _ => Color::Cyan,
    }
}

fn detail(shared: &SharedArgs, text: String) -> String {
    format!("      {}\n", crate::color(shared, text, Color::Grey))
}

fn agent_json(agent: &AgentValue) -> Value {
    let quota = agent.window.as_ref().and_then(quota_value);
    json!({
        "agent": agent.agent,
        "plan": agent.plan_name,
        "pricePerMonth": agent.price.map(json_float),
        "periodUsage": json_float(agent.period_usage),
        "liveLimits": agent.live_limits,
        "window": agent.window.as_ref().map(|window| json!({
            "label": window_label(window.window_minutes),
            "usedPercent": json_float(window.used_percent),
            "elapsedMinutes": json_float(window.elapsed_minutes),
            "apiEquivalentSpent": json_float(window.cost),
        })),
        "estimate": quota.as_ref().map(|quota| json!({
            "fullQuotaValue": json_float(quota.full_quota),
            "monthlyValue": json_float(quota.monthly),
            "projectedUsePercent": json_float(quota.projected_use_percent),
            "valueMultiple": agent.price.map(|price| json_float(quota.monthly / price)),
        })),
        "shortWindow": agent.short_window.map(|(minutes, percent)| json!({
            "label": window_label(minutes),
            "usedPercent": json_float(percent),
        })),
    })
}

/// A focused weekly-limit view for a single agent: how much of the quota is
/// spent vs how much of the week has elapsed, plus a day-by-day breakdown.
pub(super) struct WeeklyView<'a> {
    pub(super) agent: &'a str,
    pub(super) plan_name: Option<String>,
    pub(super) price: Option<f64>,
    pub(super) window: Option<WindowCost>,
    pub(super) daily: Vec<(String, f64)>,
    pub(super) live_limits: bool,
}

pub(super) fn print_weekly(view: &WeeklyView, shared: &SharedArgs) {
    crate::print_box_title(
        &format!("{} — Weekly Limit", title_case(view.agent)),
        shared,
    );
    let color = agent_color(view.agent);
    let mut out = String::new();

    out.push_str("  ");
    out.push_str(&crate::color(
        shared,
        plan_label_parts(view.plan_name.as_deref(), view.price),
        color,
    ));
    out.push_str("\n\n");

    match view.window.as_ref() {
        Some(window) => {
            let elapsed_percent =
                (window.elapsed_minutes / window.window_minutes as f64 * 100.0).min(100.0);
            out.push_str(&bar_line(shared, "limit used", window.used_percent, color));
            out.push_str(&bar_line(
                shared,
                "time elapsed",
                elapsed_percent,
                Color::Blue,
            ));

            let delta = window.used_percent - elapsed_percent;
            let (pace, pace_color) = if delta < -1.0 {
                (
                    format!(
                        "{:.0}pt under pace — quota burning slower than the clock",
                        -delta
                    ),
                    Color::Green,
                )
            } else if delta > 1.0 {
                (
                    format!("{delta:.0}pt over pace — quota burning faster than the clock"),
                    Color::Red,
                )
            } else {
                ("right on pace".to_string(), Color::Grey)
            };
            out.push_str("                  ");
            out.push_str(&crate::color(shared, format!("→ {pace}"), pace_color));
            out.push_str("\n\n");

            let resets_in =
                (window.window_minutes as f64 - window.elapsed_minutes).max(0.0) / 1440.0;
            out.push_str(&detail(
                shared,
                format!(
                    "resets in {resets_in:.1}d · {} API-equiv spent so far",
                    money(window.cost)
                ),
            ));
            if let Some(quota) = quota_value(window) {
                let value = match view.price {
                    Some(price) => format!(
                        "full quota ≈ {}/wk ≈ {}/mo  =  {:.0}× your ${price:.0}/mo plan",
                        money(quota.full_quota),
                        money(quota.monthly),
                        quota.monthly / price,
                    ),
                    None => format!(
                        "full quota ≈ {}/wk ≈ {}/mo of API usage",
                        money(quota.full_quota),
                        money(quota.monthly)
                    ),
                };
                out.push_str(&detail(
                    shared,
                    format!(
                        "projected ~{:.0}% used by reset · {value}",
                        quota.projected_use_percent
                    ),
                ));
            }
        }
        None => {
            let note = if view.live_limits {
                "no weekly limit window available yet"
            } else {
                "no live limits available (offline, or no signed-in token)"
            };
            out.push_str(&detail(shared, note.to_string()));
        }
    }

    if !view.daily.is_empty() {
        out.push_str("\n  day by day\n");
        let max = view
            .daily
            .iter()
            .map(|(_, cost)| *cost)
            .fold(0.0_f64, f64::max);
        let cost_width = view
            .daily
            .iter()
            .map(|(_, cost)| format_currency(*cost).len())
            .max()
            .unwrap_or(0);
        for (date, cost) in &view.daily {
            out.push_str("    ");
            out.push_str(&crate::color(shared, date.clone(), Color::Grey));
            out.push_str("   ");
            out.push_str(&crate::color(
                shared,
                format!("{:>cost_width$}", format_currency(*cost)),
                Color::Green,
            ));
            out.push_str("   ");
            out.push_str(&mini_bar(shared, *cost, max, color));
            out.push('\n');
        }
    }

    print!("{out}");
}

pub(super) fn weekly_to_json(view: &WeeklyView) -> Value {
    let quota = view.window.as_ref().and_then(quota_value);
    json!({
        "agent": view.agent,
        "plan": view.plan_name,
        "pricePerMonth": view.price.map(json_float),
        "liveLimits": view.live_limits,
        "window": view.window.as_ref().map(|window| json!({
            "windowMinutes": window.window_minutes,
            "usedPercent": json_float(window.used_percent),
            "elapsedPercent": json_float((window.elapsed_minutes / window.window_minutes as f64 * 100.0).min(100.0)),
            "apiEquivalentSpent": json_float(window.cost),
        })),
        "estimate": quota.as_ref().map(|quota| json!({
            "fullQuotaValue": json_float(quota.full_quota),
            "monthlyValue": json_float(quota.monthly),
            "projectedUsePercent": json_float(quota.projected_use_percent),
            "valueMultiple": view.price.map(|price| json_float(quota.monthly / price)),
        })),
        "daily": view.daily.iter().map(|(date, cost)| json!({ "date": date, "cost": json_float(*cost) })).collect::<Vec<_>>(),
    })
}

fn bar_line(shared: &SharedArgs, label: &str, percent: f64, color: Color) -> String {
    const WIDTH: usize = 24;
    let filled = ((percent / 100.0) * WIDTH as f64)
        .round()
        .clamp(0.0, WIDTH as f64) as usize;
    format!(
        "  {label:<13} {percent:>3.0}%  {}{}\n",
        crate::color(shared, "\u{2588}".repeat(filled), color),
        crate::color(shared, "\u{2591}".repeat(WIDTH - filled), Color::Grey),
    )
}

fn mini_bar(shared: &SharedArgs, value: f64, max: f64, color: Color) -> String {
    const WIDTH: usize = 16;
    let filled = if max > 0.0 && value > 0.0 {
        ((value / max) * WIDTH as f64).round().max(1.0) as usize
    } else {
        0
    }
    .min(WIDTH);
    format!(
        "{}{}",
        crate::color(shared, "\u{2588}".repeat(filled), color),
        crate::color(shared, "\u{2591}".repeat(WIDTH - filled), Color::Grey),
    )
}

fn plan_label_parts(name: Option<&str>, price: Option<f64>) -> String {
    match (name, price) {
        (Some(name), Some(price)) => format!("{name} (${price:.0}/mo)"),
        (Some(name), None) => format!("{name} (price unknown)"),
        (None, Some(price)) => format!("(${price:.0}/mo)"),
        (None, None) => "plan not detected".to_string(),
    }
}

/// Extrapolate the full-window and monthly quota value from a window's
/// consumed percentage and the matching API-equivalent spend.
fn quota_value(window: &WindowCost) -> Option<QuotaValue> {
    if window.used_percent <= 0.0 || window.elapsed_minutes <= 0.0 {
        return None;
    }
    let window_days = window.window_minutes as f64 / 1440.0;
    if window_days <= 0.0 {
        return None;
    }
    let full_quota = window.cost / (window.used_percent / 100.0);
    let monthly = full_quota * (DAYS_PER_MONTH / window_days);
    let projected_use_percent =
        (window.used_percent * window.window_minutes as f64 / window.elapsed_minutes).min(999.0);
    Some(QuotaValue {
        full_quota,
        monthly,
        projected_use_percent,
    })
}

/// Compact currency for headline figures: `$812`, `$8.1k`, `$1.2M`.
fn money(value: f64) -> String {
    if value >= 1_000_000.0 {
        format!("${:.1}M", value / 1_000_000.0)
    } else if value >= 1_000.0 {
        format!("${:.1}k", value / 1_000.0)
    } else {
        format_currency(value)
    }
}

/// Resolve a Codex plan label and price from the detected `plan_type`, with an
/// optional `spec` override (a known name or a raw monthly price).
pub(super) fn resolve_codex(plan_type: &str, spec: Option<&str>) -> (String, Option<f64>) {
    let resolved = spec
        .and_then(resolve_codex_plan)
        .or_else(|| codex_plan_from_type(plan_type));
    let name = resolved
        .as_ref()
        .and_then(|info| info.name.clone())
        .unwrap_or_else(|| title_case(plan_type));
    (name, resolved.map(|info| info.price))
}

/// Resolve a Claude plan label and price from the detected account `tier`, with
/// an optional `spec` override.
pub(super) fn resolve_claude(
    tier: Option<&str>,
    spec: Option<&str>,
) -> (Option<String>, Option<f64>) {
    let resolved = spec
        .and_then(resolve_claude_plan)
        .or_else(|| tier.and_then(resolve_claude_tier));
    (
        resolved.as_ref().and_then(|info| info.name.clone()),
        resolved.map(|info| info.price),
    )
}

fn resolve_claude_plan(spec: &str) -> Option<PlanInfo> {
    price_override(spec).or_else(|| match normalize(spec).as_str() {
        "pro" => known("Pro", 20.0),
        "max" | "max5x" | "max5" => known("Max 5×", 100.0),
        "max20x" | "max20" => known("Max 20×", 200.0),
        _ => None,
    })
}

/// Map a Claude account rate-limit tier (e.g. `default_claude_max_20x`) to a
/// known plan and price.
fn resolve_claude_tier(tier: &str) -> Option<PlanInfo> {
    let tier = tier.to_ascii_lowercase();
    if tier.contains("20x") {
        known("Max 20×", 200.0)
    } else if tier.contains("5x") {
        known("Max 5×", 100.0)
    } else if tier.contains("max") {
        known("Max", 100.0)
    } else if tier.contains("pro") {
        known("Pro", 20.0)
    } else {
        None
    }
}

fn resolve_codex_plan(spec: &str) -> Option<PlanInfo> {
    price_override(spec).or_else(|| codex_plan_from_type(spec))
}

fn codex_plan_from_type(plan_type: &str) -> Option<PlanInfo> {
    match normalize(plan_type).as_str() {
        "plus" => known("Plus", 20.0),
        "pro" => known("Pro", 200.0),
        _ => None,
    }
}

fn price_override(spec: &str) -> Option<PlanInfo> {
    let price = spec.trim().trim_start_matches('$').parse::<f64>().ok()?;
    (price > 0.0).then_some(PlanInfo { name: None, price })
}

fn known(name: &str, price: f64) -> Option<PlanInfo> {
    Some(PlanInfo {
        name: Some(name.to_string()),
        price,
    })
}

fn normalize(spec: &str) -> String {
    spec.chars()
        .filter(char::is_ascii_alphanumeric)
        .collect::<String>()
        .to_ascii_lowercase()
}

fn title_case(value: &str) -> String {
    let mut chars = value.chars();
    match chars.next() {
        Some(first) => first.to_ascii_uppercase().to_string() + chars.as_str(),
        None => value.to_string(),
    }
}

fn window_label(minutes: u64) -> String {
    match minutes {
        10080 => "weekly".to_string(),
        1440 => "daily".to_string(),
        m if m % 1440 == 0 => format!("{}d", m / 1440),
        m if m % 60 == 0 => format!("{}h", m / 60),
        m => format!("{m}m"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn window_cost(
        used_percent: f64,
        window_minutes: u64,
        elapsed_minutes: f64,
        cost: f64,
    ) -> WindowCost {
        WindowCost {
            window_minutes,
            used_percent,
            elapsed_minutes,
            cost,
        }
    }

    #[test]
    fn extrapolates_full_quota_and_monthly_value() {
        // 10% of the weekly quota produced $800 over 2 days.
        let quota = quota_value(&window_cost(10.0, 10080, 2.0 * 1440.0, 800.0)).unwrap();

        assert!((quota.full_quota - 8000.0).abs() < 1e-6);
        assert!((quota.monthly - 8000.0 * (DAYS_PER_MONTH / 7.0)).abs() < 1e-6);
        assert!((quota.projected_use_percent - 35.0).abs() < 1e-6);
    }

    #[test]
    fn skips_extrapolation_without_usage() {
        assert!(quota_value(&window_cost(0.0, 10080, 1000.0, 0.0)).is_none());
    }

    #[test]
    fn auto_detects_codex_plan_and_claude_tier() {
        let codex_input = CodexInput {
            plan_type: "pro".to_string(),
            window: Some(window_cost(10.0, 10080, 2.0 * 1440.0, 800.0)),
            short_window: Some((300, 4.0)),
        };
        let claude_input = ClaudeInput {
            window: Some(window_cost(12.0, 10080, 6.0 * 1440.0, 600.0)),
            short_window: Some((300, 23.0)),
        };
        let agents = [("codex", 8200.0), ("claude", 2900.0)];

        let subscription = Subscription::build(
            &agents,
            None,
            Some(codex_input),
            None,
            Some(claude_input),
            None,
            Some("default_claude_max_20x"),
        );

        assert_eq!(subscription.agents.len(), 2);
        let codex = &subscription.agents[0];
        assert_eq!(codex.agent, "codex");
        assert_eq!(codex.plan_name.as_deref(), Some("Pro"));
        assert_eq!(codex.price, Some(200.0));

        let claude = &subscription.agents[1];
        assert_eq!(claude.agent, "claude");
        assert_eq!(claude.plan_name.as_deref(), Some("Max 20×"));
        assert_eq!(claude.price, Some(200.0));
        assert!(claude.live_limits);
        assert!(claude.window.is_some());
    }

    #[test]
    fn maps_claude_tiers_to_plans() {
        assert_eq!(
            resolve_claude_tier("default_claude_max_20x").unwrap().price,
            200.0
        );
        assert_eq!(
            resolve_claude_tier("default_claude_max_5x").unwrap().price,
            100.0
        );
        assert_eq!(
            resolve_claude_tier("default_claude_pro").unwrap().price,
            20.0
        );
        assert!(resolve_claude_tier("default_claude_team").is_none());
    }

    #[test]
    fn money_uses_compact_units_for_large_values() {
        assert_eq!(money(812.0), "$812.00");
        assert_eq!(money(8120.0), "$8.1k");
        assert_eq!(money(1_200_000.0), "$1.2M");
    }
}
