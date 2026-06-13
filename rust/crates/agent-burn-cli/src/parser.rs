use std::{env, ffi::OsString, path::PathBuf, process};

use crate::arg_parser::ArgParser;
use crate::help::{print_help_and_exit, print_version_and_exit};
use crate::{
    Cli, CliConfig, Command, CostMode, NoConfig, SharedArgs, SortOrder, SummaryArgs, SummaryRange,
    normalize_date_bound,
};

const CLI_NAME: &str = "agent-burn";

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ControlArg {
    Help,
    Version,
}

impl Cli {
    pub fn parse() -> Self {
        Self::parse_from(env::args_os()).unwrap_or_else(|message| {
            eprintln!("{message}");
            eprintln!("Run '{CLI_NAME} --help' for usage.");
            process::exit(2);
        })
    }

    pub fn parse_from<I>(args: I) -> Result<Self, String>
    where
        I: IntoIterator<Item = OsString>,
    {
        Self::parse_from_with_config(args, &NoConfig, 5.0, env!("CARGO_PKG_VERSION"))
    }

    pub fn parse_from_with_config<I>(
        args: I,
        config: &dyn CliConfig,
        _default_session_duration_hours: f64,
        version: &'static str,
    ) -> Result<Self, String>
    where
        I: IntoIterator<Item = OsString>,
    {
        let mut parser = ArgParser::new(args.into_iter().skip(1).collect())?;
        match control_arg(&parser.args) {
            Some(ControlArg::Version) => print_version_and_exit(version),
            Some(ControlArg::Help) => print_help_and_exit(&parser.args),
            None => {}
        }

        let mut shared = SharedArgs::with_defaults();
        config.apply_shared(&mut shared);
        while let Some(arg) = parser.peek() {
            if is_command(arg) {
                break;
            }
            if !arg.starts_with('-') {
                return Err(format!("Unknown command '{arg}'"));
            }
            parse_shared_arg(&mut parser, &mut shared)?;
        }

        let command = match parser.next() {
            None => None,
            Some(command) => Some(parse_command(&command, &mut parser, shared.clone())?),
        };
        if let Some(extra) = parser.next() {
            return Err(format!("Unexpected argument '{extra}'"));
        }
        Ok(Self { command, shared })
    }
}

fn control_arg(args: &[String]) -> Option<ControlArg> {
    if args
        .iter()
        .any(|arg| matches!(arg.as_str(), "-v" | "-V" | "--version"))
    {
        return Some(ControlArg::Version);
    }
    if args
        .iter()
        .any(|arg| matches!(arg.as_str(), "-h" | "--help"))
    {
        return Some(ControlArg::Help);
    }
    None
}

fn parse_command(
    command: &str,
    parser: &mut ArgParser,
    shared: SharedArgs,
) -> Result<Command, String> {
    match command {
        "summary" => parse_summary_command(parser, shared),
        "harness" => parse_harness_command(parser, shared),
        _ => Err(format!("Unknown command '{command}'")),
    }
}

/// Parse `summary` - the all-agents cost overview:
///   summary [<range>] [--value --html --range --claude-plan --codex-plan]
fn parse_summary_command(
    parser: &mut ArgParser,
    mut shared: SharedArgs,
) -> Result<Command, String> {
    let mut value = false;
    let mut html = false;
    let mut claude_plan = None;
    let mut codex_plan = None;
    let mut range = None;
    while let Some(arg) = parser.peek() {
        if arg == "--all" {
            parser.next();
            continue;
        }
        if !arg.starts_with('-') {
            range = Some(parse_summary_range(arg)?);
            parser.next();
            continue;
        }
        if parse_shared_arg_for_command(parser, &mut shared)? {
            continue;
        }
        match parser.next_flag()?.as_str() {
            "--value" => value = true,
            "--html" => html = true,
            "--range" => range = Some(parse_summary_range(&parser.value_for("--range")?)?),
            "--claude-plan" => claude_plan = Some(parser.value_for("--claude-plan")?),
            "--codex-plan" => codex_plan = Some(parser.value_for("--codex-plan")?),
            flag => return Err(format!("Unknown summary option '{flag}'")),
        }
    }
    Ok(Command::Summary(SummaryArgs {
        shared,
        value,
        claude_plan,
        codex_plan,
        range,
        agent: None,
        html,
    }))
}

/// Parse `harness <agent>` - the focused per-agent weekly-limit detail:
///   harness <codex|claude> [--value --claude-plan --codex-plan]
fn parse_harness_command(
    parser: &mut ArgParser,
    mut shared: SharedArgs,
) -> Result<Command, String> {
    let agent = match parser.next() {
        Some(token) if matches!(token.as_str(), "codex" | "claude") => token,
        Some(token) => {
            return Err(format!(
                "Unsupported agent '{token}' for harness. Use '{CLI_NAME} harness <codex|claude>'."
            ));
        }
        None => {
            return Err(format!(
                "Specify an agent: {CLI_NAME} harness <codex|claude>"
            ));
        }
    };
    let mut value = false;
    let mut claude_plan = None;
    let mut codex_plan = None;
    while parser.peek().is_some() {
        if parse_shared_arg_for_command(parser, &mut shared)? {
            continue;
        }
        match parser.next_flag()?.as_str() {
            "--value" => value = true,
            "--claude-plan" => claude_plan = Some(parser.value_for("--claude-plan")?),
            "--codex-plan" => codex_plan = Some(parser.value_for("--codex-plan")?),
            flag => return Err(format!("Unknown harness option '{flag}'")),
        }
    }
    Ok(Command::Summary(SummaryArgs {
        shared,
        value,
        claude_plan,
        codex_plan,
        range: None,
        agent: Some(agent),
        html: false,
    }))
}

fn parse_summary_range(value: &str) -> Result<SummaryRange, String> {
    match value {
        "today" | "day" => Ok(SummaryRange::Today),
        "wtd" => Ok(SummaryRange::Wtd),
        "mtd" => Ok(SummaryRange::Mtd),
        "ytd" => Ok(SummaryRange::Ytd),
        "week" => Ok(SummaryRange::Week),
        "month" => Ok(SummaryRange::Month),
        _ => Err(format!(
            "Invalid summary range '{value}'. Use today | wtd | mtd | ytd | week | month."
        )),
    }
}

fn parse_shared_arg_for_command(
    parser: &mut ArgParser,
    shared: &mut SharedArgs,
) -> Result<bool, String> {
    let Some(arg) = parser.peek() else {
        return Ok(false);
    };
    if is_shared_flag(arg) {
        parse_shared_arg(parser, shared)?;
        return Ok(true);
    }
    Ok(false)
}

fn parse_shared_arg(parser: &mut ArgParser, shared: &mut SharedArgs) -> Result<(), String> {
    match parser.next_flag()?.as_str() {
        "-s" | "--since" => {
            shared.since = Some(normalize_date_bound(&parser.value_for("--since")?));
        }
        "-u" | "--until" => {
            shared.until = Some(normalize_date_bound(&parser.value_for("--until")?));
        }
        "-j" | "--json" => shared.json = true,
        "-m" | "--mode" => shared.mode = parse_cost_mode(&parser.value_for("--mode")?)?,
        "-d" | "--debug" => shared.debug = true,
        "--debug-samples" => {
            shared.debug_samples = parser
                .value_for("--debug-samples")?
                .parse()
                .map_err(|_| "Invalid value for --debug-samples".to_string())?;
        }
        "-o" | "--order" => shared.order = parse_sort_order(&parser.value_for("--order")?)?,
        "-b" | "--breakdown" => shared.breakdown = true,
        "-O" | "--offline" => shared.offline = true,
        "--no-offline" => shared.no_offline = true,
        "--color" => shared.color = true,
        "--no-color" => shared.no_color = true,
        "-z" | "--timezone" => shared.timezone = Some(parser.value_for("--timezone")?),
        "-q" | "--jq" => shared.jq = Some(parser.value_for("--jq")?),
        "--config" => shared.config = Some(PathBuf::from(parser.value_for("--config")?)),
        "--compact" => shared.compact = true,
        "--single-thread" => shared.single_thread = true,
        "--no-cost" => shared.no_cost = true,
        flag => return Err(format!("Unknown option '{flag}'")),
    }
    Ok(())
}

fn is_command(arg: &str) -> bool {
    matches!(arg, "summary" | "harness")
}

pub(crate) fn command_tokens(args: &[String]) -> Vec<String> {
    let mut tokens = Vec::new();
    let mut index = 0;
    while let Some(arg) = args.get(index) {
        if arg.starts_with('-') {
            if option_takes_value(arg) && !arg.contains('=') {
                index += 2;
            } else {
                index += 1;
            }
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
            | "--claude-plan"
            | "--codex-plan"
            | "--range"
    )
}

fn is_shared_flag(arg: &str) -> bool {
    matches!(
        arg.split_once('=').map_or(arg, |(name, _)| name),
        "-s" | "--since"
            | "-u"
            | "--until"
            | "-j"
            | "--json"
            | "-m"
            | "--mode"
            | "-d"
            | "--debug"
            | "--debug-samples"
            | "-o"
            | "--order"
            | "-b"
            | "--breakdown"
            | "-O"
            | "--offline"
            | "--no-offline"
            | "--color"
            | "--no-color"
            | "-z"
            | "--timezone"
            | "-q"
            | "--jq"
            | "--config"
            | "--compact"
            | "--single-thread"
            | "--no-cost"
    )
}

fn parse_cost_mode(value: &str) -> Result<CostMode, String> {
    match value {
        "auto" => Ok(CostMode::Auto),
        "calculate" => Ok(CostMode::Calculate),
        "display" => Ok(CostMode::Display),
        _ => Err(format!("Invalid cost mode '{value}'")),
    }
}

fn parse_sort_order(value: &str) -> Result<SortOrder, String> {
    match value {
        "asc" => Ok(SortOrder::Asc),
        "desc" => Ok(SortOrder::Desc),
        _ => Err(format!("Invalid sort order '{value}'")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(values: &[&str]) -> Vec<String> {
        values.iter().map(|value| value.to_string()).collect()
    }

    #[test]
    fn detects_help_before_semantic_validation() {
        assert_eq!(
            control_arg(&args(&["--help", "--daily"])),
            Some(ControlArg::Help)
        );
    }

    #[test]
    fn version_takes_precedence_over_help() {
        assert_eq!(
            control_arg(&args(&["--help", "--version"])),
            Some(ControlArg::Version)
        );
    }
}
