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
pub fn run_script_json<T: DeserializeOwned>(
    script: &Path,
    args: &[&str],
) -> Result<T, PowershellError> {
    use std::os::windows::process::CommandExt;

    let name = script
        .file_name()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_default();
    tracing::info!(script = %name, ?args, "running engine script");

    let output = Command::new("powershell.exe")
        .args([
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
        ])
        .arg(script)
        .args(args)
        .creation_flags(CREATE_NO_WINDOW)
        .output()?;

    if !output.status.success() {
        return Err(PowershellError::ScriptFailed {
            script: name,
            code: output.status.code().unwrap_or(-1),
            stderr: String::from_utf8_lossy(&output.stderr).trim().to_string(),
        });
    }

    parse_json_output(&String::from_utf8_lossy(&output.stdout), name)
}

fn parse_json_output<T: DeserializeOwned>(
    stdout: &str,
    name: String,
) -> Result<T, PowershellError> {
    let trimmed = stdout.trim();
    match serde_json::from_str(trimmed) {
        Ok(v) => Ok(v),
        Err(first_err) => {
            // Host noise (e.g. a cmdlet WARNING) can precede the JSON on
            // stdout; Write-Result emits one compact line, always last.
            trimmed
                .lines()
                .rev()
                .find(|l| !l.trim().is_empty())
                .and_then(|l| serde_json::from_str(l.trim()).ok())
                .ok_or(PowershellError::InvalidJson {
                    script: name,
                    source: first_err,
                })
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clean_json_parses() {
        let v: serde_json::Value = parse_json_output(r#"{"ok":true}"#, "x".into()).expect("parse");
        assert_eq!(v["ok"], true);
    }

    #[test]
    fn host_noise_before_json_is_skipped() {
        // Checkpoint-Computer's 24h WARNING lands on stdout before Write-Result.
        let noisy = "WARNING: A new system restore point cannot be created...\r\n{\"created\":false,\"reason\":\"24h-skip\"}\r\n";
        let v: serde_json::Value = parse_json_output(noisy, "x".into()).expect("parse");
        assert_eq!(v["reason"], "24h-skip");
    }

    #[test]
    fn garbage_is_an_error() {
        let r: Result<serde_json::Value, _> = parse_json_output("not json at all", "x".into());
        assert!(r.is_err());
    }
}
