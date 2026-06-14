mod chart;
mod loader;
mod report;
mod report_html;
mod subscription;
mod summary;
mod types;

use crate::{Result, cli::SummaryArgs};

pub(crate) fn run_summary(args: SummaryArgs) -> Result<()> {
    summary::run(args)
}

#[cfg(test)]
use loader::{aggregate_rows, codex_group_row, load_agent_rows_parallel};
#[cfg(test)]
use report::{all_report_title, all_table_columns, all_table_row, report_json};
#[cfg(test)]
use types::{AgentLoadSpec, AgentRows, AllRow};

#[cfg(test)]
mod tests;
