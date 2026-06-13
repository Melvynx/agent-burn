use std::{collections::HashSet, fs, path::Path};

use super::paths::{codex_usage_sources, collect_codex_usage_files};
use crate::{TimestampMs, format_utc_date};

/// Count Codex built-in `image_generation` calls at or after `window_start`.
///
/// Image generations are logged as `image_generation_call` response items (id
/// `ig_…`) but carry no token usage, so they are invisible to the token-based
/// cost. Deduplicating by id (each image emits several streaming events) yields
/// the number of generated images, which callers price as a gpt-image estimate.
pub(crate) fn image_generation_count_since(window_start: TimestampMs) -> usize {
    let start_date = format_utc_date(window_start);
    let Ok(sources) = codex_usage_sources() else {
        return 0;
    };
    let mut seen: HashSet<String> = HashSet::new();
    for source in &sources {
        for file in collect_codex_usage_files(&source.dir) {
            if !file_in_window(&file, &start_date) {
                continue;
            }
            let Ok(contents) = fs::read_to_string(&file) else {
                continue;
            };
            for line in contents.lines() {
                if line.contains("image_generation_call")
                    && let Some(id) = extract_image_id(line)
                {
                    seen.insert(id);
                }
            }
        }
    }
    seen.len()
}

/// Session files are named `rollout-YYYY-MM-DDThh-...`; keep those whose date is
/// in the window. Files that don't parse are kept (fail open).
fn file_in_window(file: &Path, start_date: &str) -> bool {
    let Some(name) = file.file_name().and_then(|name| name.to_str()) else {
        return true;
    };
    match name.strip_prefix("rollout-") {
        Some(rest) if rest.len() >= 10 => &rest[..10] >= start_date,
        _ => true,
    }
}

/// Extract the `ig_…` id from an `image_generation_call` line without parsing
/// the (multi-MB base64) payload.
fn extract_image_id(line: &str) -> Option<String> {
    let start = line.find("\"ig_")? + 1;
    let rest = &line[start..];
    let end = rest.find('"')?;
    Some(rest[..end].to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extracts_image_id_ignoring_other_ids() {
        let line = r#"{"type":"response_item","payload":{"id":"resp_123","type":"image_generation_call","id":"ig_abc123","status":"completed","result":"<base64>"}}"#;
        assert_eq!(extract_image_id(line).as_deref(), Some("ig_abc123"));
    }

    #[test]
    fn keeps_files_in_window() {
        assert!(file_in_window(
            Path::new("/s/2026/06/13/rollout-2026-06-13T10-00-00-x.jsonl"),
            "2026-05-14"
        ));
        assert!(!file_in_window(
            Path::new("/s/2026/04/01/rollout-2026-04-01T10-00-00-x.jsonl"),
            "2026-05-14"
        ));
    }
}
