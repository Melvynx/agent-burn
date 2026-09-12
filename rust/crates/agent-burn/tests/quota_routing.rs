use std::process::Command;

#[test]
fn quota_only_harnesses_do_not_return_cursor_skip_payloads() {
    for agent in ["codex", "claude"] {
        let output = Command::new(env!("CARGO_BIN_EXE_agent-burn"))
            .args(["harness", agent, "--json", "--offline"])
            .env("AGENT_BURN_QUOTA_ONLY", "1")
            .output()
            .unwrap();
        assert!(
            !output.status.success(),
            "{agent} must reject unavailable live quotas"
        );
        assert!(
            output.stdout.is_empty(),
            "{agent} must not emit another provider's quota"
        );
    }
}

#[test]
fn quota_only_summary_keeps_optional_cursor_skip_payload() {
    let output = Command::new(env!("CARGO_BIN_EXE_agent-burn"))
        .args(["summary", "--value", "--json", "--offline"])
        .env("AGENT_BURN_QUOTA_ONLY", "1")
        .output()
        .unwrap();
    assert!(output.status.success());
    let value: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(value["agent"], "cursor");
    assert!(value.get("window").is_none());
}
