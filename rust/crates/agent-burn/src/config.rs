use std::{
    collections::BTreeMap,
    env, fs,
    path::{Path, PathBuf},
};

use serde_json::{Map, Value};

use crate::{
    cli::{CostMode, PricingOverride, SharedArgs, SortOrder, normalize_date_bound},
    config_schema::{ConfigCostMode, ConfigPricingOverride, ConfigSortOrder, SharedOptions},
};

struct ConfigCommand {
    raw: String,
}

pub(crate) struct ConfigContext {
    value: Option<Value>,
    command: ConfigCommand,
}

impl ConfigContext {
    pub(crate) fn from_args(args: &[String]) -> Self {
        let command = detect_config_command(args);
        let value = load_config_value(scan_config_path(args).as_deref());
        Self { value, command }
    }

    fn option_maps(&self) -> Vec<&Map<String, Value>> {
        let mut maps = Vec::new();
        let Some(root) = self.value.as_ref().and_then(Value::as_object) else {
            return maps;
        };
        if let Some(defaults) = object_at(root, "defaults") {
            maps.push(defaults);
        }
        if let Some(commands) = object_at(root, "commands") {
            if let Some(raw) = object_at(commands, &self.command.raw) {
                maps.push(raw);
            }
        }
        maps
    }
}

fn object_at<'a>(object: &'a Map<String, Value>, key: &str) -> Option<&'a Map<String, Value>> {
    object.get(key).and_then(Value::as_object)
}

fn load_config_value(path: Option<&Path>) -> Option<Value> {
    let paths = match path {
        Some(path) => vec![path.to_path_buf()],
        None => discover_config_paths(),
    };
    paths
        .into_iter()
        .filter_map(|path| fs::read_to_string(path).ok())
        .filter_map(|content| serde_json::from_str::<Value>(&content).ok())
        .find(|value| value.as_object().is_some())
}

fn discover_config_paths() -> Vec<PathBuf> {
    let mut paths = Vec::new();
    if let Ok(cwd) = env::current_dir() {
        paths.push(cwd.join(".agent-burn").join("agent-burn.json"));
    }
    if let Some(home) = crate::home::home_dir() {
        paths.push(
            home.join(".config")
                .join("agent-burn")
                .join("agent-burn.json"),
        );
    }
    paths.extend(
        claude_config_dirs()
            .into_iter()
            .map(|dir| dir.join("agent-burn.json")),
    );
    paths
}

fn claude_config_dirs() -> Vec<PathBuf> {
    if let Ok(paths) = env::var("CLAUDE_CONFIG_DIR") {
        return paths
            .split(',')
            .map(str::trim)
            .filter(|path| !path.is_empty())
            .map(PathBuf::from)
            .collect();
    }
    crate::home::home_dir()
        .map(|home| vec![home.join(".config").join("claude"), home.join(".claude")])
        .unwrap_or_default()
}

fn scan_config_path(args: &[String]) -> Option<PathBuf> {
    let mut index = 0;
    while index < args.len() {
        let arg = &args[index];
        if let Some((flag, value)) = arg.split_once('=') {
            if flag == "--config" && !value.is_empty() {
                return Some(PathBuf::from(value));
            }
        } else if arg == "--config" {
            return args.get(index + 1).map(PathBuf::from);
        }
        index += 1;
    }
    None
}

fn detect_config_command(args: &[String]) -> ConfigCommand {
    let tokens = command_tokens(args);
    let raw = match tokens.first().map(String::as_str) {
        Some("harness") => "harness",
        Some("summary") | None => "summary",
        Some(other) => other,
    };
    ConfigCommand {
        raw: raw.to_string(),
    }
}

fn command_tokens(args: &[String]) -> Vec<String> {
    let mut tokens = Vec::new();
    let mut index = 0;
    while index < args.len() {
        let arg = &args[index];
        if let Some((flag, _)) = arg.split_once('=')
            && flag.starts_with('-')
        {
            index += 1;
            continue;
        }
        if arg.starts_with('-') {
            index += if option_takes_value(arg) { 2 } else { 1 };
            continue;
        }
        tokens.push(arg.clone());
        index += 1;
    }
    tokens
}

fn option_takes_value(arg: &str) -> bool {
    matches!(
        arg.split_once('=').map_or(arg, |(name, _)| name),
        "-s" | "--since"
            | "-u"
            | "--until"
            | "-m"
            | "--mode"
            | "--debug-samples"
            | "-o"
            | "--order"
            | "-z"
            | "--timezone"
            | "-q"
            | "--jq"
            | "--config"
            | "--range"
            | "--claude-plan"
            | "--codex-plan"
    )
}

pub(crate) fn apply_config_to_shared(shared: &mut SharedArgs, config: &ConfigContext) {
    for options in config.option_maps() {
        apply_shared_options(shared, SharedOptions::from_map(options));
    }
}

impl crate::cli::CliConfig for ConfigContext {
    fn apply_shared(&self, shared: &mut SharedArgs) {
        apply_config_to_shared(shared, self);
    }
}

fn apply_shared_options(shared: &mut SharedArgs, options: SharedOptions) {
    if let Some(since) = options.since {
        shared.since = Some(normalize_date_bound(&since));
    }
    if let Some(until) = options.until {
        shared.until = Some(normalize_date_bound(&until));
    }
    if let Some(json) = options.json {
        shared.json = json;
    }
    if let Some(mode) = options.mode {
        shared.mode = mode.into();
    }
    if let Some(debug) = options.debug {
        shared.debug = debug;
    }
    if let Some(debug_samples) = options.debug_samples {
        shared.debug_samples = debug_samples;
    }
    if let Some(order) = options.order {
        shared.order = order.into();
    }
    if let Some(breakdown) = options.breakdown {
        shared.breakdown = breakdown;
    }
    if let Some(offline) = options.offline {
        shared.offline = offline;
    }
    if let Some(no_offline) = options.no_offline {
        shared.no_offline = no_offline;
    }
    if let Some(color) = options.color {
        shared.color = color;
    }
    if let Some(no_color) = options.no_color {
        shared.no_color = no_color;
    }
    if let Some(timezone) = options.timezone {
        shared.timezone = Some(timezone);
    }
    if let Some(jq) = options.jq {
        shared.jq = Some(jq);
    }
    if let Some(compact) = options.compact {
        shared.compact = compact;
    }
    if let Some(single_thread) = options.single_thread {
        shared.single_thread = single_thread;
    }
    if let Some(no_cost) = options.no_cost {
        shared.no_cost = no_cost;
    }
    if let Some(pricing_overrides) = options.pricing_overrides {
        merge_pricing_overrides(&mut shared.pricing_overrides, pricing_overrides);
    }
}

fn merge_pricing_overrides(
    current: &mut BTreeMap<String, PricingOverride>,
    incoming: BTreeMap<String, ConfigPricingOverride>,
) {
    for (model, incoming_override) in incoming {
        let entry = current.entry(model).or_default();
        merge_override_fields(entry, incoming_override);
    }
}

fn merge_override_fields(target: &mut PricingOverride, source: ConfigPricingOverride) {
    if source.input_cost_per_token.is_some() {
        target.input_cost_per_token = source.input_cost_per_token;
    }
    if source.output_cost_per_token.is_some() {
        target.output_cost_per_token = source.output_cost_per_token;
    }
    if source.cache_creation_input_token_cost.is_some() {
        target.cache_creation_input_token_cost = source.cache_creation_input_token_cost;
    }
    if source.cache_read_input_token_cost.is_some() {
        target.cache_read_input_token_cost = source.cache_read_input_token_cost;
    }
    if source.input_cost_per_token_above_200k_tokens.is_some() {
        target.input_cost_per_token_above_200k_tokens =
            source.input_cost_per_token_above_200k_tokens;
    }
    if source.output_cost_per_token_above_200k_tokens.is_some() {
        target.output_cost_per_token_above_200k_tokens =
            source.output_cost_per_token_above_200k_tokens;
    }
    if source
        .cache_creation_input_token_cost_above_200k_tokens
        .is_some()
    {
        target.cache_creation_input_token_cost_above_200k_tokens =
            source.cache_creation_input_token_cost_above_200k_tokens;
    }
    if source
        .cache_read_input_token_cost_above_200k_tokens
        .is_some()
    {
        target.cache_read_input_token_cost_above_200k_tokens =
            source.cache_read_input_token_cost_above_200k_tokens;
    }
    if source.max_input_tokens.is_some() {
        target.max_input_tokens = source.max_input_tokens;
    }
    if source.fast_multiplier.is_some() {
        target.fast_multiplier = source.fast_multiplier;
    }
}

impl From<ConfigPricingOverride> for PricingOverride {
    fn from(value: ConfigPricingOverride) -> Self {
        Self {
            input_cost_per_token: value.input_cost_per_token,
            output_cost_per_token: value.output_cost_per_token,
            cache_creation_input_token_cost: value.cache_creation_input_token_cost,
            cache_read_input_token_cost: value.cache_read_input_token_cost,
            input_cost_per_token_above_200k_tokens: value.input_cost_per_token_above_200k_tokens,
            output_cost_per_token_above_200k_tokens: value.output_cost_per_token_above_200k_tokens,
            cache_creation_input_token_cost_above_200k_tokens: value
                .cache_creation_input_token_cost_above_200k_tokens,
            cache_read_input_token_cost_above_200k_tokens: value
                .cache_read_input_token_cost_above_200k_tokens,
            max_input_tokens: value.max_input_tokens,
            fast_multiplier: value.fast_multiplier,
        }
    }
}

impl From<ConfigCostMode> for CostMode {
    fn from(value: ConfigCostMode) -> Self {
        match value {
            ConfigCostMode::Auto => Self::Auto,
            ConfigCostMode::Calculate => Self::Calculate,
            ConfigCostMode::Display => Self::Display,
        }
    }
}

impl From<ConfigSortOrder> for SortOrder {
    fn from(value: ConfigSortOrder) -> Self {
        match value {
            ConfigSortOrder::Desc => Self::Desc,
            ConfigSortOrder::Asc => Self::Asc,
        }
    }
}

#[cfg(test)]
mod tests {
    use serde_json::{Value, json};

    use super::*;
    use crate::cli::{CostMode, SortOrder};

    #[test]
    fn applies_schema_backed_shared_options() {
        let config = context(
            json!({
                "defaults": {
                    "since": "2026-01-01",
                    "until": "2026-01-31",
                    "json": true,
                    "mode": "calculate",
                    "debug": true,
                    "debugSamples": 9,
                    "order": "desc",
                    "breakdown": true,
                    "offline": true,
                    "noOffline": true,
                    "color": true,
                    "noColor": true,
                    "timezone": "Asia/Tokyo",
                    "jq": ".totals",
                    "compact": true,
                    "singleThread": true,
                    "noCost": true,
                }
            }),
            "summary",
        );
        let mut shared = SharedArgs::default();

        apply_config_to_shared(&mut shared, &config);

        assert_eq!(shared.since.as_deref(), Some("20260101"));
        assert_eq!(shared.until.as_deref(), Some("20260131"));
        assert!(shared.json);
        assert_eq!(shared.mode, CostMode::Calculate);
        assert!(shared.debug);
        assert_eq!(shared.debug_samples, 9);
        assert_eq!(shared.order, SortOrder::Desc);
        assert!(shared.breakdown);
        assert!(shared.offline);
        assert!(shared.no_offline);
        assert!(shared.color);
        assert!(shared.no_color);
        assert_eq!(shared.timezone.as_deref(), Some("Asia/Tokyo"));
        assert_eq!(shared.jq.as_deref(), Some(".totals"));
        assert!(shared.compact);
        assert!(shared.single_thread);
        assert!(shared.no_cost);
    }

    #[test]
    fn merge_pricing_overrides_field_level_preserves_parent_fields() {
        use crate::config_schema::ConfigPricingOverride;
        use agent_burn_cli::PricingOverride;

        let mut current = BTreeMap::new();
        current.insert(
            "[pi] gpt-5.4".to_string(),
            PricingOverride {
                input_cost_per_token: Some(2.5e-6),
                output_cost_per_token: Some(1.5e-5),
                ..Default::default()
            },
        );

        // Child config only sets max_input_tokens for the same model
        let mut incoming = BTreeMap::new();
        incoming.insert(
            "[pi] gpt-5.4".to_string(),
            ConfigPricingOverride {
                max_input_tokens: Some(1_000_000),
                ..Default::default()
            },
        );

        merge_pricing_overrides(&mut current, incoming);

        let result = &current["[pi] gpt-5.4"];
        // Parent fields preserved
        assert_eq!(result.input_cost_per_token, Some(2.5e-6));
        assert_eq!(result.output_cost_per_token, Some(1.5e-5));
        // Child field applied
        assert_eq!(result.max_input_tokens, Some(1_000_000));
    }

    #[test]
    fn merge_pricing_overrides_child_overrides_parent_field() {
        use crate::config_schema::ConfigPricingOverride;
        use agent_burn_cli::PricingOverride;

        let mut current = BTreeMap::new();
        current.insert(
            "model-a".to_string(),
            PricingOverride {
                input_cost_per_token: Some(3e-6),
                output_cost_per_token: Some(15e-6),
                cache_read_input_token_cost: Some(3e-7),
                ..Default::default()
            },
        );

        // Child overrides just input, leaves others alone
        let mut incoming = BTreeMap::new();
        incoming.insert(
            "model-a".to_string(),
            ConfigPricingOverride {
                input_cost_per_token: Some(2e-6),
                ..Default::default()
            },
        );

        merge_pricing_overrides(&mut current, incoming);

        let result = &current["model-a"];
        assert_eq!(result.input_cost_per_token, Some(2e-6)); // overridden
        assert_eq!(result.output_cost_per_token, Some(15e-6)); // preserved
        assert_eq!(result.cache_read_input_token_cost, Some(3e-7)); // preserved
    }

    fn context(value: Value, raw: &str) -> ConfigContext {
        ConfigContext {
            value: Some(value),
            command: ConfigCommand {
                raw: raw.to_string(),
            },
        }
    }
}
