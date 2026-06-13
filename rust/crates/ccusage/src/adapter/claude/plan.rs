use std::{
    env, fs,
    path::{Path, PathBuf},
};

use serde_json::Value;

use crate::home;

/// The Claude subscription tier, read from the Claude Code account file.
///
/// Unlike the JSONL usage logs, `~/.claude.json` records the signed-in
/// account's `oauthAccount`, whose rate-limit tier reveals the plan
/// (e.g. `default_claude_max_20x`).
pub(crate) fn detected_plan_tier() -> Option<String> {
    candidate_files()
        .iter()
        .find_map(|path| plan_tier_from_file(path))
}

fn candidate_files() -> Vec<PathBuf> {
    let mut files = Vec::new();
    if let Ok(dirs) = env::var("CLAUDE_CONFIG_DIR") {
        for raw in dirs.split(',').map(str::trim).filter(|dir| !dir.is_empty()) {
            files.push(PathBuf::from(raw).join(".claude.json"));
        }
    }
    if let Some(home) = home::home_dir() {
        files.push(home.join(".claude.json"));
    }
    files
}

fn plan_tier_from_file(path: &Path) -> Option<String> {
    let contents = fs::read_to_string(path).ok()?;
    let value = serde_json::from_str::<Value>(&contents).ok()?;
    plan_tier_from_account(value.get("oauthAccount")?)
}

fn plan_tier_from_account(account: &Value) -> Option<String> {
    [
        "userRateLimitTier",
        "organizationRateLimitTier",
        "organizationType",
    ]
    .into_iter()
    .find_map(|key| {
        account
            .get(key)
            .and_then(Value::as_str)
            .filter(|tier| !tier.is_empty())
    })
    .map(str::to_string)
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    #[test]
    fn prefers_user_tier_then_org_tier_then_org_type() {
        let account = json!({
            "organizationRateLimitTier": "default_claude_max_20x",
            "organizationType": "claude_max",
            "userRateLimitTier": null,
        });
        assert_eq!(
            plan_tier_from_account(&account).as_deref(),
            Some("default_claude_max_20x")
        );

        let user_first = json!({
            "userRateLimitTier": "default_claude_pro",
            "organizationRateLimitTier": "default_claude_max_20x",
        });
        assert_eq!(
            plan_tier_from_account(&user_first).as_deref(),
            Some("default_claude_pro")
        );

        let org_type_only = json!({ "organizationType": "claude_max" });
        assert_eq!(
            plan_tier_from_account(&org_type_only).as_deref(),
            Some("claude_max")
        );
    }
}
