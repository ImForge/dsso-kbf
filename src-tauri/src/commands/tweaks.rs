use serde::{Deserialize, Serialize};
use tauri::State;

use crate::AppState;
use crate::engine::backup::{self, RestorePointResult, TweakRunStatus};
use crate::engine::registry::{
    self, DetectState, InvokeOpts, ToggleInfo, TweakItem, TweakManifest,
};

#[derive(Debug, Serialize)]
pub struct TweakListEntry {
    pub manifest: TweakManifest,
    pub applicable: bool,
}

#[tauri::command]
pub async fn list_tweaks(state: State<'_, AppState>) -> Result<Vec<TweakListEntry>, String> {
    let profile = super::profile::profile_cached(&state).await?;
    Ok(state
        .registry
        .all()
        .iter()
        .map(|t| TweakListEntry {
            manifest: t.manifest.clone(),
            applicable: t.is_applicable(&profile),
        })
        .collect())
}

#[tauri::command]
pub async fn detect_tweak(
    state: State<'_, AppState>,
    id: String,
    items: Option<Vec<String>>,
    target: Option<String>,
) -> Result<DetectState, String> {
    let reg = state.registry.clone();
    tauri::async_runtime::spawn_blocking(move || {
        let tweak = reg.get(&id).ok_or_else(|| format!("unknown tweak: {id}"))?;
        let items_str = items.map(|v| v.join(","));
        let opts = InvokeOpts {
            items: items_str.as_deref(),
            target: target.as_deref(),
            ..Default::default()
        };
        registry::detect(reg.engine_dir(), tweak, &opts).map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn get_tweak_toggle(
    state: State<'_, AppState>,
    id: String,
) -> Result<ToggleInfo, String> {
    let reg = state.registry.clone();
    tauri::async_runtime::spawn_blocking(move || {
        let tweak = reg.get(&id).ok_or_else(|| format!("unknown tweak: {id}"))?;
        if !tweak.manifest.toggle {
            return Err(format!("{id} is not a toggle tweak"));
        }
        registry::get_toggle(reg.engine_dir(), tweak).map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn get_tweak_items(
    state: State<'_, AppState>,
    id: String,
) -> Result<Vec<TweakItem>, String> {
    let reg = state.registry.clone();
    tauri::async_runtime::spawn_blocking(move || {
        let tweak = reg.get(&id).ok_or_else(|| format!("unknown tweak: {id}"))?;
        if !tweak.manifest.list_driven {
            return Err(format!("{id} is not list-driven"));
        }
        registry::get_items(reg.engine_dir(), tweak).map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| e.to_string())?
}

#[derive(Debug, Deserialize)]
pub struct TweakSelection {
    pub id: String,
    #[serde(default)]
    pub items: Option<Vec<String>>,
    /// "on" | "off" for toggle tweaks.
    #[serde(default)]
    pub target: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct ApplyResultEntry {
    pub id: String,
    pub status: TweakRunStatus,
    pub requires_reboot: bool,
    pub error: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct ApplySummary {
    pub session_id: String,
    pub restore_point: RestorePointResult,
    pub results: Vec<ApplyResultEntry>,
}

#[tauri::command]
pub async fn apply_tweaks(
    state: State<'_, AppState>,
    selections: Vec<TweakSelection>,
) -> Result<ApplySummary, String> {
    if selections.is_empty() {
        return Err("nothing selected".into());
    }
    let profile = super::profile::profile_cached(&state).await?;
    let reg = state.registry.clone();
    let lock = state.apply_lock.clone();

    tauri::async_runtime::spawn_blocking(move || {
        let _guard = lock
            .try_lock()
            .map_err(|_| "an apply session is already running".to_string())?;

        let mut session = backup::Session::begin(reg.engine_dir()).map_err(|e| e.to_string())?;
        let mut results = Vec::new();

        for sel in &selections {
            let Some(tweak) = reg.get(&sel.id) else {
                results.push(ApplyResultEntry {
                    id: sel.id.clone(),
                    status: TweakRunStatus::Failed,
                    requires_reboot: false,
                    error: Some("unknown tweak".into()),
                });
                continue;
            };
            if !tweak.is_applicable(&profile) {
                results.push(ApplyResultEntry {
                    id: sel.id.clone(),
                    status: TweakRunStatus::Failed,
                    requires_reboot: false,
                    error: Some("not applicable to this machine".into()),
                });
                continue;
            }
            let items_str = match (&tweak.manifest.list_driven, &sel.items) {
                (true, Some(items)) if !items.is_empty() => Some(items.join(",")),
                (true, _) => {
                    results.push(ApplyResultEntry {
                        id: sel.id.clone(),
                        status: TweakRunStatus::Failed,
                        requires_reboot: false,
                        error: Some("no items selected".into()),
                    });
                    continue;
                }
                (false, _) => None,
            };
            let target = match (&tweak.manifest.toggle, &sel.target) {
                (true, Some(t)) if t == "on" || t == "off" => Some(t.as_str()),
                (true, _) => {
                    results.push(ApplyResultEntry {
                        id: sel.id.clone(),
                        status: TweakRunStatus::Failed,
                        requires_reboot: false,
                        error: Some("no on/off target chosen".into()),
                    });
                    continue;
                }
                (false, _) => None,
            };

            match backup::apply_tweak(&reg, &mut session, tweak, items_str.as_deref(), target) {
                Ok(outcome) => results.push(ApplyResultEntry {
                    id: sel.id.clone(),
                    status: outcome.record.status,
                    requires_reboot: outcome.record.requires_reboot,
                    error: outcome.record.error,
                }),
                Err(e) => results.push(ApplyResultEntry {
                    id: sel.id.clone(),
                    status: TweakRunStatus::Failed,
                    requires_reboot: false,
                    error: Some(format!("backup failed, tweak not applied: {e}")),
                }),
            }
        }

        Ok(ApplySummary {
            session_id: session.record.id.clone(),
            restore_point: session.record.restore_point.clone(),
            results,
        })
    })
    .await
    .map_err(|e| e.to_string())?
}
