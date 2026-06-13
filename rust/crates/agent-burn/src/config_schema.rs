#![allow(dead_code)]

use std::collections::BTreeMap;

use serde::Deserialize;
use serde::de::DeserializeOwned;
use serde_json::{Map, Value, json};

use schemars::{JsonSchema, r#gen::SchemaSettings};

#[derive(Debug, Default, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub(crate) struct AgentBurnConfig {
    /// JSON Schema URL for validation and autocomplete.
    #[serde(rename = "$schema")]
    pub(crate) schema_url: Option<String>,
    /// Default values for Agent Burn reports.
    pub(crate) defaults: Option<SharedOptions>,
    /// Command-specific configuration.
    pub(crate) commands: Option<RootCommandsConfig>,
}

#[derive(Debug, Default, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub(crate) struct RootCommandsConfig {
    pub(crate) summary: Option<SummaryOptions>,
    pub(crate) harness: Option<HarnessOptions>,
}

#[derive(Debug, Default, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub(crate) struct SharedOptions {
    /// Filter from date (YYYY-MM-DD or YYYYMMDD).
    pub(crate) since: Option<String>,
    /// Filter until date (inclusive).
    pub(crate) until: Option<String>,
    /// Output in JSON format.
    pub(crate) json: Option<bool>,
    /// Cost calculation mode.
    pub(crate) mode: Option<ConfigCostMode>,
    /// Show pricing mismatch information for debugging.
    pub(crate) debug: Option<bool>,
    /// Number of sample discrepancies to show in debug output.
    pub(crate) debug_samples: Option<usize>,
    /// Sort order.
    pub(crate) order: Option<ConfigSortOrder>,
    /// Show per-model cost breakdown.
    pub(crate) breakdown: Option<bool>,
    /// Use cached pricing data where supported.
    pub(crate) offline: Option<bool>,
    /// Disable cached pricing data where supported.
    pub(crate) no_offline: Option<bool>,
    /// Enable colored output.
    pub(crate) color: Option<bool>,
    /// Disable colored output.
    pub(crate) no_color: Option<bool>,
    /// Timezone for date grouping (IANA).
    pub(crate) timezone: Option<String>,
    /// jq filter to apply to JSON output.
    pub(crate) jq: Option<String>,
    /// Accepted for compatibility; all detected supported agents are included by default.
    pub(crate) all: Option<bool>,
    /// Force compact table layout for narrow terminals.
    pub(crate) compact: Option<bool>,
    /// Disable parallel file processing.
    pub(crate) single_thread: Option<bool>,
    /// Hide cost information in table and JSON output.
    pub(crate) no_cost: Option<bool>,
    /// Runtime pricing overrides keyed by raw model name.
    pub(crate) pricing_overrides: Option<BTreeMap<String, ConfigPricingOverride>>,
}

#[derive(Debug, Default, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub(crate) struct SummaryOptions {
    #[serde(flatten)]
    pub(crate) shared: SharedOptions,
    /// Quick time range for summary.
    pub(crate) range: Option<String>,
    /// Show subscription value.
    pub(crate) value: Option<bool>,
    /// Generate an interactive HTML report.
    pub(crate) html: Option<bool>,
    /// Claude plan override.
    pub(crate) claude_plan: Option<String>,
    /// Codex plan override.
    pub(crate) codex_plan: Option<String>,
}

#[derive(Debug, Default, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub(crate) struct HarnessOptions {
    #[serde(flatten)]
    pub(crate) shared: SharedOptions,
    /// Show subscription value.
    pub(crate) value: Option<bool>,
    /// Claude plan override.
    pub(crate) claude_plan: Option<String>,
    /// Codex plan override.
    pub(crate) codex_plan: Option<String>,
}

#[derive(Clone, Copy, Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "lowercase")]
pub(crate) enum ConfigCostMode {
    Auto,
    Calculate,
    Display,
}

#[derive(Clone, Copy, Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "lowercase")]
pub(crate) enum ConfigSortOrder {
    Desc,
    Asc,
}

#[derive(Debug, Default, Deserialize, JsonSchema, Clone)]
#[serde(rename_all = "camelCase")]
pub(crate) struct ConfigPricingOverride {
    pub(crate) input_cost_per_token: Option<f64>,
    pub(crate) output_cost_per_token: Option<f64>,
    pub(crate) cache_creation_input_token_cost: Option<f64>,
    pub(crate) cache_read_input_token_cost: Option<f64>,
    pub(crate) input_cost_per_token_above_200k_tokens: Option<f64>,
    pub(crate) output_cost_per_token_above_200k_tokens: Option<f64>,
    pub(crate) cache_creation_input_token_cost_above_200k_tokens: Option<f64>,
    pub(crate) cache_read_input_token_cost_above_200k_tokens: Option<f64>,
    pub(crate) max_input_tokens: Option<u64>,
    pub(crate) fast_multiplier: Option<f64>,
}

impl SharedOptions {
    pub(crate) fn from_map(map: &Map<String, Value>) -> Self {
        Self {
            since: string_option(map, "since"),
            until: string_option(map, "until"),
            json: bool_option(map, "json"),
            mode: enum_option(map, "mode"),
            debug: bool_option(map, "debug"),
            debug_samples: usize_option(map, "debugSamples"),
            order: enum_option(map, "order"),
            breakdown: bool_option(map, "breakdown"),
            offline: bool_option(map, "offline"),
            no_offline: bool_option(map, "noOffline"),
            color: bool_option(map, "color"),
            no_color: bool_option(map, "noColor"),
            timezone: string_option(map, "timezone"),
            jq: string_option(map, "jq"),
            all: bool_option(map, "all"),
            compact: bool_option(map, "compact"),
            single_thread: bool_option(map, "singleThread"),
            no_cost: bool_option(map, "noCost"),
            pricing_overrides: pricing_override_map_option(map, "pricingOverrides"),
        }
    }
}

pub(crate) fn generate_config_schema_json() -> String {
    let generator = SchemaSettings::draft07()
        .with(|settings| {
            settings.meta_schema = Some("https://json-schema.org/draft-07/schema#".to_string());
            settings.option_add_null_type = false;
        })
        .into_generator();
    let mut generated =
        serde_json::to_value(generator.into_root_schema_for::<AgentBurnConfig>()).unwrap();
    enrich_schema(&mut generated);
    add_schema_defaults(&mut generated);
    let schema = agent_burn_schema_from(&generated);
    let mut json = tab_indent_json(&serde_json::to_string_pretty(&schema).unwrap());
    json.push('\n');
    json
}

fn agent_burn_schema_from(generated: &Value) -> Value {
    let definitions = generated
        .get("definitions")
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();
    let mut shared_options = definitions
        .get("SharedOptions")
        .cloned()
        .unwrap_or_else(|| json!({"type": "object", "properties": {}}));
    inline_schema_value(&mut shared_options, &definitions);

    let mut summary_options = shared_options.clone();
    extend_object_properties(
        &mut summary_options,
        json!({
            "range": {
                "type": "string",
                "enum": ["today", "wtd", "mtd", "ytd", "week", "month"],
                "description": "Quick time range for summary."
            },
            "value": {
                "type": "boolean",
                "default": false,
                "description": "Show subscription value."
            },
            "html": {
                "type": "boolean",
                "default": false,
                "description": "Generate an interactive HTML report."
            },
            "claudePlan": {
                "type": "string",
                "description": "Claude plan override: pro, max-5x, max-20x, or a monthly price."
            },
            "codexPlan": {
                "type": "string",
                "description": "Codex plan override: plus, pro, or a monthly price."
            }
        }),
    );

    let mut harness_options = shared_options.clone();
    extend_object_properties(
        &mut harness_options,
        json!({
            "value": {
                "type": "boolean",
                "default": false,
                "description": "Show subscription value."
            },
            "claudePlan": {
                "type": "string",
                "description": "Claude plan override: pro, max-5x, max-20x, or a monthly price."
            },
            "codexPlan": {
                "type": "string",
                "description": "Codex plan override: plus, pro, or a monthly price."
            }
        }),
    );

    json!({
        "$schema": "https://json-schema.org/draft-07/schema#",
        "$ref": "#/definitions/agent-burn-config",
        "title": "Agent Burn Configuration",
        "description": "Configuration file for Agent Burn",
        "examples": [
            {
                "$schema": "https://raw.githubusercontent.com/Melvynx/agent-burn/main/apps/agent-burn/config-schema.json",
                "defaults": {
                    "timezone": "Europe/Zurich",
                    "offline": true
                },
                "commands": {
                    "summary": {
                        "value": true,
                        "range": "month"
                    },
                    "harness": {
                        "value": true
                    }
                }
            }
        ],
        "definitions": {
            "agent-burn-config": {
                "type": "object",
                "additionalProperties": false,
                "description": "Configuration file for Agent Burn",
                "markdownDescription": "Configuration file for Agent Burn",
                "properties": {
                    "$schema": {
                        "type": "string",
                        "description": "JSON Schema URL for validation and autocomplete.",
                        "markdownDescription": "JSON Schema URL for validation and autocomplete."
                    },
                    "defaults": shared_options,
                    "commands": {
                        "type": "object",
                        "additionalProperties": false,
                        "properties": {
                            "summary": summary_options,
                            "harness": harness_options
                        }
                    }
                }
            }
        }
    })
}

fn extend_object_properties(target: &mut Value, extra_properties: Value) {
    let Some(properties) = target.get_mut("properties").and_then(Value::as_object_mut) else {
        return;
    };
    if let Value::Object(extra) = extra_properties {
        properties.extend(extra);
    }
}

fn tab_indent_json(json: &str) -> String {
    json.lines()
        .map(|line| {
            let spaces = line
                .as_bytes()
                .iter()
                .take_while(|byte| **byte == b' ')
                .count();
            let mut formatted = "\t".repeat(spaces / 2);
            formatted.push_str(&line[spaces..]);
            formatted
        })
        .collect::<Vec<_>>()
        .join("\n")
}

fn string_option(map: &Map<String, Value>, key: &str) -> Option<String> {
    map.get(key)?.as_str().map(ToString::to_string)
}

fn bool_option(map: &Map<String, Value>, key: &str) -> Option<bool> {
    map.get(key)?.as_bool()
}

fn usize_option(map: &Map<String, Value>, key: &str) -> Option<usize> {
    map.get(key)?
        .as_u64()
        .and_then(|value| usize::try_from(value).ok())
}

fn enum_option<T>(map: &Map<String, Value>, key: &str) -> Option<T>
where
    T: DeserializeOwned,
{
    serde_json::from_value(map.get(key)?.clone()).ok()
}

fn pricing_override_map_option(
    map: &Map<String, Value>,
    key: &str,
) -> Option<BTreeMap<String, ConfigPricingOverride>> {
    serde_json::from_value(map.get(key)?.clone()).ok()
}

fn enrich_schema(value: &mut Value) {
    match value {
        Value::Object(map) => {
            if let Some(description) = map.get("description").cloned() {
                map.entry("markdownDescription".to_string())
                    .or_insert(description);
            }
            if map.contains_key("properties") {
                map.entry("additionalProperties".to_string())
                    .or_insert(Value::Bool(false));
            }
            for child in map.values_mut() {
                enrich_schema(child);
            }
        }
        Value::Array(values) => {
            for child in values {
                enrich_schema(child);
            }
        }
        _ => {}
    }
}

fn add_schema_defaults(schema: &mut Value) {
    set_definition_defaults(
        schema,
        "SharedOptions",
        &[
            ("json", json!(false)),
            ("mode", json!("auto")),
            ("debug", json!(false)),
            ("debugSamples", json!(5)),
            ("order", json!("asc")),
            ("breakdown", json!(false)),
            ("offline", json!(false)),
            ("noOffline", json!(false)),
            ("color", json!(false)),
            ("noColor", json!(false)),
            ("all", json!(false)),
            ("compact", json!(false)),
            ("singleThread", json!(false)),
            ("noCost", json!(false)),
        ],
    );
}

fn set_definition_defaults(schema: &mut Value, definition: &str, defaults: &[(&str, Value)]) {
    let Some(properties) = schema
        .get_mut("definitions")
        .and_then(|definitions| definitions.get_mut(definition))
        .and_then(|definition| definition.get_mut("properties"))
        .and_then(Value::as_object_mut)
    else {
        return;
    };
    for (property, default) in defaults {
        if let Some(property_schema) = properties.get_mut(*property).and_then(Value::as_object_mut)
        {
            property_schema
                .entry("default".to_string())
                .or_insert_with(|| default.clone());
        }
    }
}

fn inline_schema_references(schema: &mut Value) {
    let definitions = schema
        .get("definitions")
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();
    inline_schema_value(schema, &definitions);
}

fn inline_schema_value(value: &mut Value, definitions: &Map<String, Value>) {
    match value {
        Value::Object(map) => {
            inline_ref(map, definitions);
            inline_all_of(map, definitions);
            for child in map.values_mut() {
                inline_schema_value(child, definitions);
            }
        }
        Value::Array(values) => {
            for child in values {
                inline_schema_value(child, definitions);
            }
        }
        _ => {}
    }
}

fn inline_ref(map: &mut Map<String, Value>, definitions: &Map<String, Value>) {
    let Some(reference) = map.remove("$ref") else {
        return;
    };
    let Some(reference) = reference.as_str() else {
        return;
    };
    let Some(definition_name) = reference.strip_prefix("#/definitions/") else {
        return;
    };
    let Some(Value::Object(definition)) = definitions.get(definition_name).cloned() else {
        return;
    };

    let existing = std::mem::take(map);
    for (key, value) in definition {
        map.insert(key, value);
    }
    for (key, value) in existing {
        map.insert(key, value);
    }
}

fn inline_all_of(map: &mut Map<String, Value>, definitions: &Map<String, Value>) {
    let Some(Value::Array(items)) = map.remove("allOf") else {
        return;
    };
    for mut item in items {
        inline_schema_value(&mut item, definitions);
        let Value::Object(item) = item else {
            continue;
        };
        merge_schema_object(map, item);
    }
}

fn merge_schema_object(target: &mut Map<String, Value>, source: Map<String, Value>) {
    for (key, value) in source {
        if key == "properties" {
            let target_properties = target
                .entry(key)
                .or_insert_with(|| Value::Object(Map::new()));
            if let (Some(target), Value::Object(source)) =
                (target_properties.as_object_mut(), value)
            {
                target.extend(source);
            }
            continue;
        }
        target.entry(key).or_insert(value);
    }
}

fn wrap_root_schema(schema: &mut Value) {
    let Value::Object(root) = schema else {
        return;
    };
    root.remove("definitions");
    let mut definitions = Map::new();
    let mut root_definition = Map::new();
    for key in [
        "additionalProperties",
        "description",
        "markdownDescription",
        "properties",
        "type",
    ] {
        if let Some(value) = root.remove(key) {
            root_definition.insert(key.to_string(), value);
        }
    }
    definitions.insert(
        "agent-burn-config".to_string(),
        Value::Object(root_definition),
    );
    root.insert(
        "$ref".to_string(),
        Value::String("#/definitions/agent-burn-config".to_string()),
    );
    root.insert("definitions".to_string(), Value::Object(definitions));
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeSet;

    use serde_json::{Value, json};

    use super::generate_config_schema_json;

    #[test]
    fn schema_option_sets_expose_expected_keys() {
        let schema = generated_schema();
        let shared = [
            "all",
            "breakdown",
            "color",
            "compact",
            "debug",
            "debugSamples",
            "jq",
            "json",
            "mode",
            "noColor",
            "noCost",
            "noOffline",
            "offline",
            "order",
            "pricingOverrides",
            "since",
            "singleThread",
            "timezone",
            "until",
        ];

        assert_schema_properties(&schema, &["defaults"], &shared);
        assert_schema_properties(
            &schema,
            &["commands", "summary"],
            &with_keys(
                &shared,
                &["claudePlan", "codexPlan", "html", "range", "value"],
            ),
        );
        assert_schema_properties(
            &schema,
            &["commands", "harness"],
            &with_keys(&shared, &["claudePlan", "codexPlan", "value"]),
        );
    }

    #[test]
    fn agent_configs_are_not_public_schema_keys() {
        let schema = generated_schema();

        for key in [
            "amp", "claude", "codebuff", "codex", "copilot", "droid", "gemini", "goose", "hermes",
            "kilo", "kimi", "openclaw", "opencode", "pi", "qwen",
        ] {
            assert!(
                schema_property(&schema, &[key]).is_none(),
                "{key} leaked into schema"
            );
        }
    }

    #[test]
    fn generated_schema_does_not_accept_null_config_values() {
        let schema = generate_config_schema_json();
        let value = serde_json::from_str::<Value>(&schema).unwrap();

        assert!(!schema.contains("\"null\""));
        assert!(!contains_key(&value, "anyOf"));
    }

    #[test]
    fn generated_schema_keeps_agent_burn_root_definition_shape() {
        let schema = generated_schema();

        assert_eq!(
            schema["$ref"].as_str(),
            Some("#/definitions/agent-burn-config")
        );
        assert_eq!(
            schema["definitions"]
                .as_object()
                .unwrap()
                .keys()
                .map(String::as_str)
                .collect::<Vec<_>>(),
            vec!["agent-burn-config"]
        );
        assert_properties(
            &schema,
            "agent-burn-config",
            &["$schema", "commands", "defaults"],
        );
        assert!(
            schema["definitions"]["agent-burn-config"]["properties"]["defaults"]["properties"]
                .is_object()
        );
    }

    #[test]
    fn schema_allows_cli_config_file_shape() {
        let schema = generated_schema();
        let config = serde_json::json!({
            "$schema": "https://github.com/Melvynx/agent-burn/config-schema.json",
            "defaults": {
                "json": true,
                "compact": true,
                "timezone": "Asia/Tokyo"
            },
            "commands": {
                "summary": {
                    "value": true,
                    "range": "month"
                },
                "harness": {
                    "value": true,
                    "offline": true
                }
            }
        });

        assert_value_keys_allowed_by_schema(&config, &schema, &schema);
    }

    #[test]
    fn schema_allows_repository_example_config() {
        let schema = generated_schema();
        let config =
            serde_json::from_str::<Value>(include_str!("../../../../agent-burn.example.json"))
                .unwrap();

        assert_value_keys_allowed_by_schema(&config, &schema, &schema);
    }

    #[test]
    fn generated_schema_exposes_cli_defaults() {
        let schema = generated_schema();

        assert_eq!(
            property_default(&schema, &["defaults", "json"]),
            Some(&json!(false))
        );
        assert_eq!(
            property_default(&schema, &["defaults", "mode"]),
            Some(&json!("auto"))
        );
        assert_eq!(
            property_default(&schema, &["defaults", "debugSamples"]),
            Some(&json!(5))
        );
        assert_eq!(
            property_default(&schema, &["defaults", "order"]),
            Some(&json!("asc"))
        );
        assert_eq!(
            property_default(&schema, &["commands", "summary", "value"]),
            Some(&json!(false))
        );
        assert_eq!(
            property_default(&schema, &["commands", "harness", "value"]),
            Some(&json!(false))
        );
    }

    #[test]
    fn snapshots_schema_agent_specific_option_edges() {
        if running_in_schema_generator_test_binary() {
            return;
        }
        let schema = generated_schema();

        insta::assert_json_snapshot!(json!({
            "rootRef": schema["$ref"],
            "rootProperties": definition_properties(&schema, "agent-burn-config"),
            "rootAdditionalProperties": schema["definitions"]["agent-burn-config"]["additionalProperties"],
            "defaults": schema_node(&schema, &["defaults"]),
            "summary": schema_node(&schema, &["commands", "summary"]),
            "harness": schema_node(&schema, &["commands", "harness"]),
        }));
    }

    fn running_in_schema_generator_test_binary() -> bool {
        std::env::current_exe()
            .ok()
            .and_then(|path| {
                path.file_name()
                    .map(|name| name.to_string_lossy().into_owned())
            })
            .is_some_and(|name| {
                name.starts_with("generate_config_schema")
                    || name.starts_with("generate-config-schema")
            })
    }

    fn generated_schema() -> Value {
        serde_json::from_str(&generate_config_schema_json()).unwrap()
    }

    fn assert_properties(schema: &Value, definition: &str, expected: &[&str]) {
        assert_eq!(
            definition_properties(schema, definition),
            expected.iter().copied().collect::<BTreeSet<_>>(),
            "{definition} properties did not match"
        );
    }

    fn definition_properties<'a>(schema: &'a Value, definition: &str) -> BTreeSet<&'a str> {
        schema["definitions"][definition]["properties"]
            .as_object()
            .unwrap()
            .keys()
            .map(String::as_str)
            .collect()
    }

    fn assert_schema_properties(schema: &Value, path: &[&str], expected: &[&str]) {
        assert_eq!(
            schema_properties(schema, path),
            expected.iter().copied().collect::<BTreeSet<_>>(),
            "{path:?} properties did not match"
        );
    }

    fn schema_properties<'a>(schema: &'a Value, path: &[&str]) -> BTreeSet<&'a str> {
        schema_node(schema, path)["properties"]
            .as_object()
            .unwrap()
            .keys()
            .map(String::as_str)
            .collect()
    }

    fn property_default<'a>(schema: &'a Value, path: &[&str]) -> Option<&'a Value> {
        schema_property(schema, path).and_then(|property| property.get("default"))
    }

    fn schema_property<'a>(schema: &'a Value, path: &[&str]) -> Option<&'a Value> {
        let (property, parent_path) = path.split_last().unwrap();
        schema_node(schema, parent_path)["properties"].get(*property)
    }

    fn schema_node<'a>(schema: &'a Value, path: &[&str]) -> &'a Value {
        let mut node = &schema["definitions"]["agent-burn-config"];
        for segment in path {
            node = &node["properties"][*segment];
        }
        node
    }

    fn with_keys<'a>(base: &[&'a str], extra: &[&'a str]) -> Vec<&'a str> {
        base.iter().chain(extra).copied().collect()
    }

    fn contains_key(value: &Value, key: &str) -> bool {
        match value {
            Value::Object(map) => {
                map.contains_key(key) || map.values().any(|value| contains_key(value, key))
            }
            Value::Array(values) => values.iter().any(|value| contains_key(value, key)),
            _ => false,
        }
    }

    fn assert_value_keys_allowed_by_schema(value: &Value, schema: &Value, root: &Value) {
        let Some(value_object) = value.as_object() else {
            return;
        };
        let schema = resolve_schema(schema, root);
        let schema = merge_all_of(schema, root);
        let properties = schema.get("properties").and_then(Value::as_object);
        for (key, child_value) in value_object {
            let child_schema = if let Some(properties) = properties {
                if let Some(child_schema) = properties.get(key) {
                    child_schema
                } else if schema
                    .get("additionalProperties")
                    .is_some_and(|v| !v.is_null() && *v != Value::Bool(false))
                {
                    schema.get("additionalProperties").unwrap()
                } else {
                    panic!("schema does not allow config key {key}");
                }
            } else if schema
                .get("additionalProperties")
                .is_some_and(|v| !v.is_null() && *v != Value::Bool(false))
            {
                schema.get("additionalProperties").unwrap()
            } else {
                panic!("schema node has no properties: {schema:?}");
            };
            assert_value_keys_allowed_by_schema(child_value, child_schema, root);
        }
    }

    fn resolve_schema<'a>(schema: &'a Value, root: &'a Value) -> &'a Value {
        let Some(reference) = schema.get("$ref").and_then(Value::as_str) else {
            return schema;
        };
        let definition = reference.strip_prefix("#/definitions/").unwrap();
        &root["definitions"][definition]
    }

    fn merge_all_of(schema: &Value, root: &Value) -> Value {
        let Some(items) = schema.get("allOf").and_then(Value::as_array) else {
            return schema.clone();
        };
        let mut merged = schema.clone();
        let properties = merged
            .as_object_mut()
            .unwrap()
            .entry("properties")
            .or_insert_with(|| Value::Object(Default::default()));
        let properties = properties.as_object_mut().unwrap();
        for item in items {
            let resolved = resolve_schema(item, root);
            for (key, value) in resolved["properties"].as_object().unwrap() {
                properties.insert(key.clone(), value.clone());
            }
        }
        merged
    }
}
