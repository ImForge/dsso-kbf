use crate::engine::profile::{self, SystemProfile};

#[tauri::command]
pub async fn get_system_profile() -> Result<SystemProfile, String> {
    // Detection shells out to PowerShell and takes a few seconds — keep it off
    // the async runtime's core threads.
    tauri::async_runtime::spawn_blocking(profile::detect)
        .await
        .map_err(|e| e.to_string())?
        .map_err(|e| {
            tracing::error!("detection failed: {e}");
            e.to_string()
        })
}
