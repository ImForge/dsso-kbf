use std::path::{Path, PathBuf};
use std::process::Command;

use serde::de::DeserializeOwned;
use thiserror::Error;

/// Prevents a console window flashing when spawned from the GUI exe.
const CREATE_NO_WINDOW: u32 = 0x0800_0000;

#[derive(Debug, Error)]
pub enum PowershellError {
    #[error("engine directory not found (looked next to the exe, up the tree, and in the cwd)")]
    EngineDirNotFound,
    #[error("failed to start powershell.exe: {0}")]
    Spawn(#[from] std::io::Error),
    #[error("{script} exited with code {code}: {stderr}")]
    ScriptFailed {
        script: String,
        code: i32,
        stderr: String,
    },
    #[error("{script} printed invalid JSON: {source}")]
    InvalidJson {
        script: String,
        #[source]
        source: serde_json::Error,
    },
}

/// Locate the engine/ directory holding the PowerShell scripts: next to the
/// exe (installed layout), walking up from the exe (dev: target/debug is three
/// levels below the repo), then the cwd.
pub fn resolve_engine_dir() -> Result<PathBuf, PowershellError> {
    let mut candidates: Vec<PathBuf> = Vec::new();
    if let Ok(exe) = std::env::current_exe() {
        let mut dir = exe.parent().map(Path::to_path_buf);
        for _ in 0..5 {
            match dir {
                Some(d) => {
                    candidates.push(d.join("engine"));
                    dir = d.parent().map(Path::to_path_buf);
                }
                None => break,
            }
        }
    }
    if let Ok(cwd) = std::env::current_dir() {
        candidates.push(cwd.join("engine"));
    }
    candidates
        .into_iter()
        .find(|c| c.join("Detect-System.ps1").is_file())
        .ok_or(PowershellError::EngineDirNotFound)
}

/// Run a script with Windows PowerShell 5.1 semantics and parse its stdout as JSON.
pub fn run_script_json<T: DeserializeOwned>(script: &Path) -> Result<T, PowershellError> {
    use std::os::windows::process::CommandExt;

    let name = script
        .file_name()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_default();
    tracing::info!(script = %name, "running engine script");

    let output = Command::new("powershell.exe")
        .args([
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
        ])
        .arg(script)
        .creation_flags(CREATE_NO_WINDOW)
        .output()?;

    if !output.status.success() {
        return Err(PowershellError::ScriptFailed {
            script: name,
            code: output.status.code().unwrap_or(-1),
            stderr: String::from_utf8_lossy(&output.stderr).trim().to_string(),
        });
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    serde_json::from_str(stdout.trim()).map_err(|e| PowershellError::InvalidJson {
        script: name,
        source: e,
    })
}
