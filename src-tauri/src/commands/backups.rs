use serde::Serialize;
use tauri::State;

use crate::AppState;
use crate::engine::backup::{self, SessionRecord};

/// Session ids are timestamps (digits + 'T'); anything else is refused so a
/// crafted id can never traverse out of the backups dir.
fn session_dir(id: &str) -> Result<std::path::PathBuf, String> {
    if id.is_empty() || !id.chars().all(|c| c.is_ascii_digit() || c == 'T') {
        return Err(format!("invalid session id: {id}"));
    }
    Ok(backup::backups_root().join(id))
}

#[tauri::command]
pub async fn list_backup_sessions() -> Result<Vec<SessionRecord>, String> {
    tauri::async_runtime::spawn_blocking(|| {
        backup::list_sessions()
            .map(|v| v.into_iter().map(|(_, r)| r).collect())
            .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| e.to_string())?
}

#[derive(Debug, Serialize)]
pub struct RevertEntry {
    pub id: String,
    pub ok: bool,
    pub error: Option<String>,
}

#[tauri::command]
pub async fn revert_backup_session(
    state: State<'_, AppState>,
    session_id: String,
) -> Result<Vec<RevertEntry>, String> {
    let reg = state.registry.clone();
    let dir = session_dir(&session_id)?;
    tauri::async_runtime::spawn_blocking(move || {
        backup::revert_session(&reg, &dir)
            .map(|results| {
                results
                    .into_iter()
                    .map(|(id, r)| RevertEntry {
                        id,
                        ok: r.is_ok(),
                        error: r.err(),
                    })
                    .collect()
            })
            .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn revert_backup_tweak(
    state: State<'_, AppState>,
    session_id: String,
    tweak_id: String,
) -> Result<(), String> {
    let reg = state.registry.clone();
    let dir = session_dir(&session_id)?;
    tauri::async_runtime::spawn_blocking(move || {
        backup::revert_tweak_in_session(&reg, &dir, &tweak_id).map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| e.to_string())?
}
