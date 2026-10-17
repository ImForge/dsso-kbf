use tauri::State;

use crate::AppState;
use crate::engine::profile::{self, SystemProfile};

/// Detection shells out to PowerShell and takes a few seconds, so the result
/// is cached in AppState for every consumer (Dashboard, tweak filtering).
pub async fn profile_cached(state: &State<'_, AppState>) -> Result<SystemProfile, String> {
    {
        let cached = state.profile.lock().map_err(|e| e.to_string())?;
        if let Some(p) = cached.as_ref() {
            return Ok(p.clone());
        }
    }
    let fresh = tauri::async_runtime::spawn_blocking(profile::detect)
        .await
        .map_err(|e| e.to_string())?
        .map_err(|e| {
            tracing::error!("detection failed: {e}");
            e.to_string()
        })?;
    let mut cached = state.profile.lock().map_err(|e| e.to_string())?;
    *cached = Some(fresh.clone());
    Ok(fresh)
}

#[tauri::command]
pub async fn get_system_profile(
    state: State<'_, AppState>,
    refresh: Option<bool>,
) -> Result<SystemProfile, String> {
    if refresh.unwrap_or(false) {
        let mut cached = state.profile.lock().map_err(|e| e.to_string())?;
        *cached = None;
    }
    profile_cached(&state).await
}
