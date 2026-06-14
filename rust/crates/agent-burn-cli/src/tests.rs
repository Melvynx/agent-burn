use std::ffi::OsString;

use serde_json::{Value, json};

use crate::help::{help_text, help_text_for_args};
use crate::*;

fn parse(args: &[&str]) -> Cli {
    Cli::parse_from(args.iter().map(OsString::from)).unwrap()
}

fn parse_with_config(args: &[&str], config: &dyn CliConfig) -> Cli {
    Cli::parse_from_with_config(
        args.iter().map(OsString::from),
        config,
        5.0,
        env!("CARGO_PKG_VERSION"),
    )
    .unwrap()
}

fn parse_error(args: &[&str]) -> String {
    match Cli::parse_from(args.iter().map(OsString::from)) {
        Ok(_) => panic!("expected parse error"),
        Err(error) => error,
    }
}

#[derive(Default)]
struct TestConfig {
    shared_json: Option<bool>,
    shared_order: Option<SortOrder>,
    shared_since: Option<&'static str>,
    shared_timezone: Option<&'static str>,
    shared_compact: Option<bool>,
}

impl CliConfig for TestConfig {
    fn apply_shared(&self, shared: &mut SharedArgs) {
        if let Some(json) = self.shared_json {
            shared.json = json;
        }
        if let Some(order) = self.shared_order {
            shared.order = order;
        }
        if let Some(since) = self.shared_since {
            shared.since = Some(since.to_string());
        }
        if let Some(timezone) = self.shared_timezone {
            shared.timezone = Some(timezone.to_string());
        }
        if let Some(compact) = self.shared_compact {
            shared.compact = compact;
        }
    }
}

fn shared_snapshot(shared: &SharedArgs) -> Value {
    json!({
        "since": shared.since.as_deref(),
        "until": shared.until.as_deref(),
        "json": shared.json,
        "mode": format!("{:?}", shared.mode),
        "debug": shared.debug,
        "debugSamples": shared.debug_samples,
        "order": format!("{:?}", shared.order),
        "breakdown": shared.breakdown,
        "offline": shared.offline,
        "noOffline": shared.no_offline,
        "color": shared.color,
        "noColor": shared.no_color,
        "timezone": shared.timezone.as_deref(),
        "jq": shared.jq.as_deref(),
        "config": shared.config.as_ref().map(|path| path.to_string_lossy().to_string()),
        "compact": shared.compact,
        "singleThread": shared.single_thread,
        "noCost": shared.no_cost,
    })
}

fn cli_snapshot(cli: Cli) -> Value {
    json!({
        "shared": shared_snapshot(&cli.shared),
        "command": command_snapshot(cli.command),
    })
}

fn command_snapshot(command: Option<Command>) -> Value {
    match command {
        None => Value::Null,
        Some(Command::Summary(args)) => json!({
            "type": "summary",
            "shared": shared_snapshot(&args.shared),
            "value": args.value,
            "claudePlan": args.claude_plan,
            "codexPlan": args.codex_plan,
            "range": args.range.map(|range| format!("{range:?}")),
            "agent": args.agent,
            "html": args.html,
            "chart": args.chart,
        }),
    }
}

#[test]
fn parses_no_command_as_default_summary_surface() {
    let cli = parse(&["agent-burn", "--json", "--since", "2026-01-02"]);
    assert!(cli.command.is_none());
    assert!(cli.shared.json);
    assert_eq!(cli.shared.since.as_deref(), Some("20260102"));
}

#[test]
fn parses_summary_overview_options() {
    let cli = parse(&[
        "agent-burn",
        "summary",
        "mtd",
        "--value",
        "--html",
        "--claude-plan",
        "max-20x",
        "--codex-plan",
        "pro",
    ]);
    let Some(Command::Summary(args)) = cli.command else {
        panic!("expected summary command");
    };
    assert_eq!(args.range, Some(SummaryRange::Mtd));
    assert!(args.value);
    assert!(args.html);
    assert!(args.agent.is_none());
    assert_eq!(args.claude_plan.as_deref(), Some("max-20x"));
    assert_eq!(args.codex_plan.as_deref(), Some("pro"));
}

#[test]
fn parses_harness_agent_detail_view() {
    let cli = parse(&[
        "agent-burn",
        "harness",
        "codex",
        "--value",
        "--codex-plan",
        "pro",
    ]);
    let Some(Command::Summary(args)) = cli.command else {
        panic!("expected harness command");
    };
    assert_eq!(args.agent.as_deref(), Some("codex"));
    assert!(args.value);
    assert!(!args.html);
    assert_eq!(args.codex_plan.as_deref(), Some("pro"));
}

#[test]
fn accepts_burn_as_program_name_for_help_selection() {
    assert!(help_text_for_args(&["burn".to_string(), "harness".to_string()]).contains("USAGE:"));
}

#[test]
fn rejects_removed_legacy_commands() {
    assert_eq!(
        parse_error(&["agent-burn", "daily"]),
        "Unknown command 'daily'"
    );
    assert_eq!(
        parse_error(&["agent-burn", "codex", "daily"]),
        "Unknown command 'codex'"
    );
    assert_eq!(
        parse_error(&["agent-burn", "harness"]),
        "Specify an agent: agent-burn harness <codex|claude>"
    );
}

#[test]
fn applies_config_defaults_before_command_options() {
    let config = TestConfig {
        shared_json: Some(true),
        shared_order: Some(SortOrder::Desc),
        shared_since: Some("20260101"),
        shared_timezone: Some("UTC"),
        shared_compact: Some(true),
    };
    let cli = parse_with_config(&["agent-burn", "summary", "--since", "2026-02-03"], &config);
    let Some(Command::Summary(args)) = cli.command else {
        panic!("expected summary command");
    };
    assert!(args.shared.json);
    assert_eq!(args.shared.order, SortOrder::Desc);
    assert_eq!(args.shared.since.as_deref(), Some("20260203"));
    assert_eq!(args.shared.timezone.as_deref(), Some("UTC"));
    assert!(args.shared.compact);
}

#[test]
fn snapshots_root_help() {
    insta::assert_snapshot!("root_help", help_text());
}

#[test]
fn snapshots_command_help() {
    insta::assert_snapshot!(
        "summary_help",
        help_text_for_args(&["agent-burn".to_string(), "summary".to_string()])
    );
    insta::assert_snapshot!(
        "harness_help",
        help_text_for_args(&["agent-burn".to_string(), "harness".to_string()])
    );
}

#[test]
fn snapshots_cli_parse_shapes() {
    insta::assert_json_snapshot!(json!({
        "defaultSummary": cli_snapshot(parse(&["agent-burn", "--json"])),
        "summary": cli_snapshot(parse(&[
            "agent-burn",
            "summary",
            "week",
            "--value",
            "--timezone",
            "Europe/Zurich",
        ])),
        "harness": cli_snapshot(parse(&[
            "agent-burn",
            "harness",
            "claude",
            "--value",
            "--claude-plan",
            "max-20x",
            "--offline",
        ])),
    }));
}
