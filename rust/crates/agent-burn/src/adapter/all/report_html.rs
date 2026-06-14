use std::{env, fs, path::PathBuf, process::Command};

use serde_json::Value;

use crate::{Result, TimestampMs, home};

const TEMPLATE: &str = include_str!("report_template.html");

/// Write an interactive HTML report (and a sibling `.json` data file), then
/// open it in the browser. Returns the HTML path for the caller to print.
pub(super) fn write_and_open(payload: &Value, now: TimestampMs) -> Result<PathBuf> {
    let dir = report_dir();
    fs::create_dir_all(&dir)?;
    let stamp = file_stamp(now);
    let html_path = dir.join(format!("cost-report-{stamp}.html"));
    let json_path = dir.join(format!("cost-report-{stamp}.json"));

    fs::write(&json_path, serde_json::to_string_pretty(payload)?)?;
    let data = serde_json::to_string(payload)?;
    fs::write(&html_path, TEMPLATE.replace("__REPORT_DATA__", &data))?;

    open(&html_path);
    Ok(html_path)
}

/// `~/Library/Caches/agent-burn` on macOS, `$XDG_CACHE_HOME/agent-burn` (or
/// `~/.cache/agent-burn`) elsewhere, falling back to the temp dir.
fn report_dir() -> PathBuf {
    if let Some(home) = home::home_dir() {
        #[cfg(target_os = "macos")]
        return home.join("Library/Caches/agent-burn/reports");
        #[cfg(not(target_os = "macos"))]
        {
            let base = env::var_os("XDG_CACHE_HOME")
                .map(PathBuf::from)
                .unwrap_or_else(|| home.join(".cache"));
            return base.join("agent-burn/reports");
        }
    }
    env::temp_dir().join("agent-burn-reports")
}

fn file_stamp(now: TimestampMs) -> String {
    let parts = now.utc_parts();
    format!(
        "{:04}{:02}{:02}-{:02}{:02}{:02}",
        parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second
    )
}

fn open(path: &std::path::Path) {
    let _ = open_command(path).map(|mut command| command.spawn());
}

fn open_command(path: &std::path::Path) -> Option<Command> {
    #[cfg(target_os = "macos")]
    {
        let mut command = Command::new("open");
        command.arg(path);
        Some(command)
    }
    #[cfg(target_os = "linux")]
    {
        let mut command = Command::new("xdg-open");
        command.arg(path);
        Some(command)
    }
    #[cfg(target_os = "windows")]
    {
        let mut command = Command::new("cmd");
        command.args(["/C", "start", ""]).arg(path);
        Some(command)
    }
    #[cfg(not(any(target_os = "macos", target_os = "linux", target_os = "windows")))]
    {
        let _ = path;
        None
    }
}
