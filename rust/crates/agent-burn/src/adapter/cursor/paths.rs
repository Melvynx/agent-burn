use std::{
    env,
    path::{Path, PathBuf},
};

use crate::home;

pub(super) const CURSOR_DATA_DIR_ENV: &str = "CURSOR_DATA_DIR";
pub(super) const CURSOR_ACCESS_TOKEN_ENV: &str = "CURSOR_ACCESS_TOKEN";

pub(super) struct CursorCredentials {
    pub(super) token: Option<String>,
    pub(super) membership: Option<String>,
}

pub(super) fn credentials() -> CursorCredentials {
    credentials_from(
        state_db_path().as_deref(),
        env::var(CURSOR_ACCESS_TOKEN_ENV)
            .ok()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty()),
    )
}

pub(super) fn credentials_from(
    db_path: Option<&Path>,
    env_token: Option<String>,
) -> CursorCredentials {
    let token =
        env_token.or_else(|| db_path.and_then(|path| read_item(path, "cursorAuth/accessToken")));
    let membership = db_path.and_then(|path| read_item(path, "cursorAuth/stripeMembershipType"));
    CursorCredentials { token, membership }
}

pub(crate) fn detected_plan() -> Option<String> {
    credentials().membership
}

pub(super) fn state_db_path() -> Option<PathBuf> {
    if let Ok(raw) = env::var(CURSOR_DATA_DIR_ENV) {
        let path = PathBuf::from(raw.trim());
        if path.is_file() {
            return Some(path);
        }
        for candidate in [
            path.join("User/globalStorage/state.vscdb"),
            path.join("globalStorage/state.vscdb"),
            path.join("state.vscdb"),
        ] {
            if candidate.is_file() {
                return Some(candidate);
            }
        }
        return None;
    }
    default_state_db_path().filter(|path| path.is_file())
}

fn default_state_db_path() -> Option<PathBuf> {
    let home = home::home_dir()?;
    #[cfg(target_os = "macos")]
    {
        return Some(
            home.join("Library/Application Support/Cursor/User/globalStorage/state.vscdb"),
        );
    }
    #[cfg(target_os = "windows")]
    {
        let app_data = env::var_os("APPDATA").map(PathBuf::from)?;
        return Some(app_data.join("Cursor/User/globalStorage/state.vscdb"));
    }
    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    {
        let base = env::var_os("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| home.join(".config"));
        Some(base.join("Cursor/User/globalStorage/state.vscdb"))
    }
}

fn read_item(db_path: &Path, key: &str) -> Option<String> {
    let connection =
        sqlite::Connection::open_with_flags(db_path, sqlite::OpenFlags::new().with_read_only())
            .ok()?;
    let mut statement = connection
        .prepare("SELECT value FROM ItemTable WHERE key = ?1")
        .ok()?;
    statement.bind((1, key)).ok()?;
    if !matches!(statement.next(), Ok(sqlite::State::Row)) {
        return None;
    }
    let raw = statement.read::<Vec<u8>, _>(0).ok()?;
    item_text(&raw)
}

fn item_text(raw: &[u8]) -> Option<String> {
    let text = String::from_utf8_lossy(raw).trim().to_string();
    if text.is_empty() {
        return None;
    }
    if text.starts_with('"') {
        return serde_json::from_str::<String>(&text)
            .ok()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty());
    }
    Some(text)
}

#[cfg(test)]
mod tests {
    use super::*;
    use agent_burn_test_support::{EnvVarGuard, Fixture};

    fn write_state_db(path: &Path, token: &str, membership: &str) {
        let db = sqlite::open(path).unwrap();
        db.execute("CREATE TABLE ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB)")
            .unwrap();
        for (key, value) in [
            ("cursorAuth/accessToken", token),
            ("cursorAuth/stripeMembershipType", membership),
        ] {
            let mut statement = db
                .prepare("INSERT INTO ItemTable (key, value) VALUES (?1, ?2)")
                .unwrap();
            statement.bind((1, key)).unwrap();
            statement.bind((2, value)).unwrap();
            statement.next().unwrap();
        }
    }

    #[test]
    fn reads_token_and_membership_from_state_db() {
        let fixture = Fixture::new();
        let db_path = fixture.path("state.vscdb");
        write_state_db(&db_path, "jwt-token", "ultra");

        let credentials = credentials_from(Some(&db_path), None);

        assert_eq!(credentials.token.as_deref(), Some("jwt-token"));
        assert_eq!(credentials.membership.as_deref(), Some("ultra"));
    }

    #[test]
    fn env_token_overrides_state_db() {
        let fixture = Fixture::new();
        let db_path = fixture.path("User/globalStorage/state.vscdb");
        let _ = fixture.create_dir_all("User/globalStorage");
        write_state_db(&db_path, "db-token", "pro");

        let credentials = credentials_from(Some(&db_path), Some("env-token".to_string()));

        assert_eq!(credentials.token.as_deref(), Some("env-token"));
        assert_eq!(credentials.membership.as_deref(), Some("pro"));
    }

    #[test]
    fn finds_state_db_under_cursor_data_dir() {
        let fixture = Fixture::new();
        let _ = fixture.create_dir_all("User/globalStorage");
        write_state_db(
            &fixture.path("User/globalStorage/state.vscdb"),
            "jwt-token",
            "ultra",
        );
        let _dir = EnvVarGuard::set(CURSOR_DATA_DIR_ENV, fixture.root());

        assert_eq!(
            state_db_path().as_deref(),
            Some(fixture.path("User/globalStorage/state.vscdb").as_path())
        );
    }
}
