mod account;
mod loader;
mod parser;
mod paths;
mod report;

pub(crate) use account::load_account;
pub(crate) use loader::load_entries;
pub(crate) use paths::detected_plan as detected_membership;
pub(crate) use report::summarize_entries;

#[cfg(test)]
mod tests {
    #[test]
    #[ignore]
    fn loads_live_cursor_usage_when_signed_in() {
        let shared = crate::cli::SharedArgs::default();
        let pricing = crate::PricingMap::load_embedded();
        let entries = super::load_entries(&shared, &pricing).unwrap();
        assert!(
            !entries.is_empty(),
            "signed-in Cursor session should produce usage rows"
        );
    }
}
