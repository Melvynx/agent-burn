mod loader;
mod parser;
mod paths;
mod report;

pub(crate) use loader::load_entries;
pub(crate) use report::summarize_entries;

fn empty_usage_message() -> &'static str {
    "No GitHub Copilot CLI usage data found.\nEnable Copilot OpenTelemetry file export before starting or resuming Copilot sessions.\nSee https://github.com/Melvynx/agent-burn/guide/copilot/#data-source"
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_usage_message_links_to_copilot_docs() {
        let message = empty_usage_message();
        assert!(
            message.contains("https://github.com/Melvynx/agent-burn/guide/copilot/#data-source")
        );
    }
}
