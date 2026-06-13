use std::{collections::BTreeMap, path::PathBuf};

pub struct Cli {
    pub command: Option<Command>,
    pub shared: SharedArgs,
}

pub enum Command {
    Summary(SummaryArgs),
}

#[derive(Clone, Debug, Default)]
pub struct SharedArgs {
    pub since: Option<String>,
    pub until: Option<String>,
    pub json: bool,
    pub mode: CostMode,
    pub debug: bool,
    pub debug_samples: usize,
    pub order: SortOrder,
    pub breakdown: bool,
    pub offline: bool,
    pub no_offline: bool,
    pub color: bool,
    pub no_color: bool,
    pub timezone: Option<String>,
    pub jq: Option<String>,
    pub config: Option<PathBuf>,
    pub compact: bool,
    pub single_thread: bool,
    pub no_cost: bool,
    pub pricing_overrides: BTreeMap<String, PricingOverride>,
}

impl SharedArgs {
    pub(crate) fn with_defaults() -> Self {
        Self {
            mode: CostMode::Auto,
            debug_samples: 5,
            order: SortOrder::Asc,
            ..Self::default()
        }
    }
}

pub fn normalize_date_bound(value: &str) -> String {
    value.replace('-', "")
}

/// Arguments shared by two sibling commands:
/// - `summary` — the all-agents cost overview (`agent` is `None`).
/// - `harness <agent>` — the focused per-agent detail (weekly limit vs time),
///   where `agent` is `Some("codex" | "claude")`.
#[derive(Clone)]
pub struct SummaryArgs {
    pub shared: SharedArgs,
    pub value: bool,
    pub claude_plan: Option<String>,
    pub codex_plan: Option<String>,
    pub range: Option<SummaryRange>,
    /// `Some(agent)` selects the `harness <agent>` detail view; `None` is the
    /// `summary` overview.
    pub agent: Option<String>,
    /// Generate an interactive HTML report (and open it) in addition to the
    /// terminal output. Overview-only.
    pub html: bool,
}

/// A convenience time range for `agent-burn summary`, resolved to a `--since`
/// bound at run time (it needs the current date and timezone).
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SummaryRange {
    Today,
    /// Week-to-date (since Monday of the current week).
    Wtd,
    /// Month-to-date (since the 1st of the current month).
    Mtd,
    /// Year-to-date (since January 1st).
    Ytd,
    /// The last 7 days.
    Week,
    /// The last 30 days.
    Month,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AgentReportKind {
    Daily,
    Weekly,
    Monthly,
    Session,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum CodexSpeed {
    #[default]
    Auto,
    Standard,
    Fast,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum CostMode {
    #[default]
    Auto,
    Calculate,
    Display,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum SortOrder {
    Desc,
    #[default]
    Asc,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum WeekDay {
    Sunday,
    Monday,
    Tuesday,
    Wednesday,
    Thursday,
    Friday,
    Saturday,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct PricingOverride {
    pub input_cost_per_token: Option<f64>,
    pub output_cost_per_token: Option<f64>,
    pub cache_creation_input_token_cost: Option<f64>,
    pub cache_read_input_token_cost: Option<f64>,
    pub input_cost_per_token_above_200k_tokens: Option<f64>,
    pub output_cost_per_token_above_200k_tokens: Option<f64>,
    pub cache_creation_input_token_cost_above_200k_tokens: Option<f64>,
    pub cache_read_input_token_cost_above_200k_tokens: Option<f64>,
    pub max_input_tokens: Option<u64>,
    pub fast_multiplier: Option<f64>,
}

pub trait CliConfig {
    fn apply_shared(&self, _shared: &mut SharedArgs) {}
}

pub struct NoConfig;

impl CliConfig for NoConfig {}
