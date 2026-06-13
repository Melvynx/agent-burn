mod loader;
mod parser;
mod paths;
mod report;

pub(crate) use loader::load_entries;
pub(crate) use report::summarize_entries;

#[cfg(test)]
struct GeminiDataDirEnvGuard {
    _guard: agent_burn_test_support::EnvVarGuard,
}

#[cfg(test)]
impl GeminiDataDirEnvGuard {
    fn set(path: &std::path::Path) -> Self {
        Self {
            _guard: agent_burn_test_support::EnvVarGuard::set(paths::GEMINI_DATA_DIR_ENV, path),
        }
    }
}
