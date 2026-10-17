//! Backup sessions: one restore-point attempt per session, a per-tweak backup
//! dir under %LOCALAPPDATA%\dsso-kbf\backups\<timestamp>\<tweak-id>\, and a
//! session.json listing every tweak and its result.

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::engine::powershell::{self, PowershellError};
use crate::engine::registry::{
    self, DetectState, InvokeError, Tweak, TweakFunction, TweakRegistry,
};

#[derive(Debug, Error)]
pub enum BackupError {
    #[error("cannot access {path}: {source}")]
    Io {
        path: String,
        #[source]
        source: std::io::Error,
    },
    #[error("session {0} not found")]
    SessionNotFound(String),
    #[error("session.json in {path} is invalid: {source}")]
    InvalidSession {
        path: String,
        #[source]
        source: serde_json::Error,
    },
    #[error(transparent)]
    Powershell(#[from] PowershellError),
    #[error(transparent)]
    Invoke(#[from] InvokeError),
}

fn io_err(path: &Path) -> impl FnOnce(std::io::Error) -> BackupError + '_ {
    move |source| BackupError::Io {
        path: path.display().to_string(),
        source,
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RestorePointResult {
    pub created: bool,
    pub reason: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TweakRunStatus {
    Applied,
    Failed,
    Reverted,
    Skipped,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TweakRunRecord {
    pub id: String,
    pub status: TweakRunStatus,
    pub requires_reboot: bool,
    #[serde(default)]
    pub error: Option<String>,
    #[serde(default)]
    pub backup_files: Vec<String>,
    /// Selected item ids for list-driven tweaks (informational; Revert is
    /// driven purely by the backup dir contents).
    #[serde(default)]
    pub items: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionRecord {
    pub id: String,
    pub created: String,
    pub restore_point: RestorePointResult,
    pub tweaks: Vec<TweakRunRecord>,
}

pub fn backups_root() -> PathBuf {
    let base = std::env::var_os("LOCALAPPDATA")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."));
    base.join("dsso-kbf").join("backups")
}

fn save_record(dir: &Path, record: &SessionRecord) -> Result<(), BackupError> {
    let path = dir.join("session.json");
    let json =
        serde_json::to_string_pretty(record).map_err(|source| BackupError::InvalidSession {
            path: path.display().to_string(),
            source,
        })?;
    std::fs::write(&path, json).map_err(io_err(&path))
}

pub fn load_session(dir: &Path) -> Result<SessionRecord, BackupError> {
    let path = dir.join("session.json");
    let raw = std::fs::read_to_string(&path).map_err(io_err(&path))?;
    serde_json::from_str(&raw).map_err(|source| BackupError::InvalidSession {
        path: path.display().to_string(),
        source,
    })
}

/// Every session on disk, newest first.
pub fn list_sessions() -> Result<Vec<(PathBuf, SessionRecord)>, BackupError> {
    let root = backups_root();
    let mut sessions = Vec::new();
    let entries = match std::fs::read_dir(&root) {
        Ok(e) => e,
        Err(ref e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(sessions),
        Err(source) => {
            return Err(BackupError::Io {
                path: root.display().to_string(),
                source,
            });
        }
    };
    for entry in entries.flatten() {
        let dir = entry.path();
        if dir.is_dir() && dir.join("session.json").is_file() {
            match load_session(&dir) {
                Ok(record) => sessions.push((dir, record)),
                Err(e) => tracing::warn!("skipping unreadable session {}: {e}", dir.display()),
            }
        }
    }
    sessions.sort_by(|a, b| b.1.id.cmp(&a.1.id));
    Ok(sessions)
}

pub struct Session {
    pub dir: PathBuf,
    pub record: SessionRecord,
}

impl Session {
    /// Create the session dir and attempt ONE restore point (continuing on
    /// failure with the cause recorded, per CLAUDE.md).
    pub fn begin(engine_dir: &Path) -> Result<Session, BackupError> {
        let id = chrono::Local::now().format("%Y%m%dT%H%M%S").to_string();
        let dir = backups_root().join(&id);
        std::fs::create_dir_all(&dir).map_err(io_err(&dir))?;

        let restore_point = create_restore_point(engine_dir, &id);
        if restore_point.created {
            tracing::info!("restore point created");
        } else {
            tracing::warn!(reason = %restore_point.reason, "restore point NOT created — continuing");
        }

        let record = SessionRecord {
            id,
            created: chrono::Local::now().to_rfc3339(),
            restore_point,
            tweaks: Vec::new(),
        };
        save_record(&dir, &record)?;
        Ok(Session { dir, record })
    }

    pub fn tweak_backup_dir(&self, tweak_id: &str) -> PathBuf {
        self.dir.join(tweak_id)
    }

    fn record_tweak(&mut self, rec: TweakRunRecord) -> Result<(), BackupError> {
        self.record.tweaks.push(rec);
        save_record(&self.dir, &self.record)
    }
}

fn create_restore_point(engine_dir: &Path, session_id: &str) -> RestorePointResult {
    let description = format!("dsso-kbf session {session_id}");
    let script = engine_dir.join("New-RestorePoint.ps1");
    match powershell::run_script_json(&script, &["-Description", &description]) {
        Ok(r) => r,
        Err(e) => RestorePointResult {
            created: false,
            reason: e.to_string(),
        },
    }
}

#[derive(Debug)]
pub struct ApplyOutcome {
    pub record: TweakRunRecord,
    pub state_before: DetectState,
    pub state_after: Option<DetectState>,
}

/// Backup then apply one tweak, recording the result in the session. An Apply
/// failure is recorded and returned, not propagated; a Backup failure aborts
/// the tweak (nothing is applied without a backup).
pub fn apply_tweak(
    registry: &TweakRegistry,
    session: &mut Session,
    tweak: &Tweak,
    items: Option<&str>,
) -> Result<ApplyOutcome, BackupError> {
    let engine = registry.engine_dir();
    let before = registry::detect(engine, tweak, items)?;
    let item_list: Vec<String> = items
        .map(|s| s.split(',').map(|x| x.trim().to_string()).collect())
        .unwrap_or_default();

    if before == DetectState::Applied {
        let rec = TweakRunRecord {
            id: tweak.id().to_string(),
            status: TweakRunStatus::Skipped,
            requires_reboot: false,
            error: None,
            backup_files: Vec::new(),
            items: item_list,
        };
        session.record_tweak(rec.clone())?;
        return Ok(ApplyOutcome {
            record: rec,
            state_before: before,
            state_after: None,
        });
    }

    let backup_dir = session.tweak_backup_dir(tweak.id());
    std::fs::create_dir_all(&backup_dir).map_err(io_err(&backup_dir))?;
    let backup_files = registry::invoke(
        engine,
        tweak,
        TweakFunction::Backup,
        Some(&backup_dir),
        items,
    )
    .map(|v| registry::value_as_strings(&v))?;

    match registry::invoke(engine, tweak, TweakFunction::Apply, None, items) {
        Ok(value) => {
            let after = registry::detect(engine, tweak, items).unwrap_or(DetectState::Unknown);
            let rec = TweakRunRecord {
                id: tweak.id().to_string(),
                status: TweakRunStatus::Applied,
                requires_reboot: registry::value_requires_reboot(&value),
                error: None,
                backup_files,
                items: item_list,
            };
            session.record_tweak(rec.clone())?;
            Ok(ApplyOutcome {
                record: rec,
                state_before: before,
                state_after: Some(after),
            })
        }
        Err(e) => {
            let rec = TweakRunRecord {
                id: tweak.id().to_string(),
                status: TweakRunStatus::Failed,
                requires_reboot: false,
                error: Some(e.to_string()),
                backup_files,
                items: item_list,
            };
            session.record_tweak(rec.clone())?;
            Ok(ApplyOutcome {
                record: rec,
                state_before: before,
                state_after: None,
            })
        }
    }
}

/// Per-tweak revert outcome: (tweak id, Ok or the failure message).
pub type RevertResult = (String, Result<(), String>);

/// Revert every applied tweak in a session, newest first. Returns one result
/// per tweak attempted.
pub fn revert_session(
    registry: &TweakRegistry,
    dir: &Path,
) -> Result<Vec<RevertResult>, BackupError> {
    let mut record = load_session(dir)?;
    let engine = registry.engine_dir();
    let mut results = Vec::new();

    for rec in record.tweaks.iter_mut().rev() {
        if rec.status != TweakRunStatus::Applied {
            continue;
        }
        let Some(tweak) = registry.get(&rec.id) else {
            results.push((
                rec.id.clone(),
                Err("tweak no longer exists in the registry".into()),
            ));
            continue;
        };
        let backup_dir = dir.join(&rec.id);
        match registry::invoke(
            engine,
            tweak,
            TweakFunction::Revert,
            Some(&backup_dir),
            None,
        ) {
            Ok(_) => {
                rec.status = TweakRunStatus::Reverted;
                results.push((rec.id.clone(), Ok(())));
            }
            Err(e) => results.push((rec.id.clone(), Err(e.to_string()))),
        }
    }

    save_record(dir, &record)?;
    Ok(results)
}

/// Revert ONE applied tweak of a session (the Backups page allows per-tweak
/// revert). Fails when the tweak was not applied in that session.
pub fn revert_tweak_in_session(
    registry: &TweakRegistry,
    dir: &Path,
    tweak_id: &str,
) -> Result<(), BackupError> {
    let mut record = load_session(dir)?;
    let engine = registry.engine_dir();
    let rec = record
        .tweaks
        .iter_mut()
        .find(|r| r.id == tweak_id && r.status == TweakRunStatus::Applied)
        .ok_or_else(|| BackupError::SessionNotFound(format!("{tweak_id} (applied) in session")))?;
    let tweak = registry
        .get(tweak_id)
        .ok_or_else(|| BackupError::SessionNotFound(format!("tweak {tweak_id} in registry")))?;
    let backup_dir = dir.join(tweak_id);
    registry::invoke(
        engine,
        tweak,
        TweakFunction::Revert,
        Some(&backup_dir),
        None,
    )?;
    rec.status = TweakRunStatus::Reverted;
    save_record(dir, &record)
}
