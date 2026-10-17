//! PresentMon wrapper + metrics: spawns the bundled console PresentMon for a
//! timed capture, parses the frametime CSV, computes avg / 1% low / 0.1% low
//! FPS and frametime stddev, and stores runs under
//! %LOCALAPPDATA%\dsso-kbf\benchmarks\ so before/after can be compared.

use std::path::{Path, PathBuf};
use std::process::Command;

use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::engine::powershell::{self, PowershellError};

const CREATE_NO_WINDOW: u32 = 0x0800_0000;

#[derive(Debug, Error)]
pub enum BenchmarkError {
    #[error(
        "PresentMon.exe not found (looked for resources/presentmon/PresentMon.exe next to the exe and up the tree)"
    )]
    PresentMonMissing,
    #[error("failed to start PresentMon: {0}")]
    Spawn(#[from] std::io::Error),
    #[error("PresentMon exited with code {code}: {stderr}")]
    CaptureFailed { code: i32, stderr: String },
    #[error(
        "no frames captured for '{process}' - is it running, presenting frames, and spelled exactly like the exe name?"
    )]
    NoFrames { process: String },
    #[error("cannot find a frametime column (FrameTime / MsBetweenPresents) in the PresentMon CSV")]
    InvalidCsv,
    #[error("cannot access {path}: {source}")]
    Io {
        path: String,
        #[source]
        source: std::io::Error,
    },
    #[error("run {0} is invalid: {1}")]
    InvalidRun(String, serde_json::Error),
    #[error(transparent)]
    Powershell(#[from] PowershellError),
}

fn io_err(path: &Path) -> impl FnOnce(std::io::Error) -> BenchmarkError + '_ {
    move |source| BenchmarkError::Io {
        path: path.display().to_string(),
        source,
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameMetrics {
    pub frames: u32,
    pub fps_avg: f64,
    pub fps_1_low: f64,
    pub fps_01_low: f64,
    pub frametime_avg_ms: f64,
    pub frametime_stddev_ms: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemMetrics {
    pub cpu_usage_percent: f64,
    pub ram_used_mb: u64,
    pub ram_total_mb: u64,
    pub boot_time_ms: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BenchmarkRun {
    pub id: String,
    pub created: String,
    #[serde(default)]
    pub label: Option<String>,
    #[serde(default)]
    pub process: Option<String>,
    #[serde(default)]
    pub duration_s: Option<u32>,
    #[serde(default)]
    pub game: Option<GameMetrics>,
    #[serde(default)]
    pub system: Option<SystemMetrics>,
}

pub fn benchmarks_root() -> PathBuf {
    let base = std::env::var_os("LOCALAPPDATA")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."));
    base.join("dsso-kbf").join("benchmarks")
}

/// Locate the bundled PresentMon: <dir>/resources/presentmon/PresentMon.exe
/// next to the exe (installed) or up the tree (dev: src-tauri/resources).
pub fn resolve_presentmon() -> Result<PathBuf, BenchmarkError> {
    let mut candidates: Vec<PathBuf> = Vec::new();
    if let Ok(exe) = std::env::current_exe() {
        let mut dir = exe.parent().map(Path::to_path_buf);
        for _ in 0..5 {
            match dir {
                Some(d) => {
                    candidates.push(
                        d.join("resources")
                            .join("presentmon")
                            .join("PresentMon.exe"),
                    );
                    dir = d.parent().map(Path::to_path_buf);
                }
                None => break,
            }
        }
    }
    candidates
        .into_iter()
        .find(|c| c.is_file())
        .ok_or(BenchmarkError::PresentMonMissing)
}

/// Parse PresentMon CSV (2.x "FrameTime" or 1.x "MsBetweenPresents") into
/// per-frame milliseconds.
pub fn parse_frametimes_csv(text: &str) -> Result<Vec<f64>, BenchmarkError> {
    let mut lines = text.lines();
    let header = lines.next().ok_or(BenchmarkError::InvalidCsv)?;
    let column = header
        .split(',')
        .position(|c| {
            let c = c.trim().to_ascii_lowercase();
            c == "frametime" || c == "msbetweenpresents"
        })
        .ok_or(BenchmarkError::InvalidCsv)?;
    let mut frametimes = Vec::new();
    for line in lines {
        if let Some(cell) = line.split(',').nth(column)
            && let Ok(ms) = cell.trim().parse::<f64>()
            && ms.is_finite()
            && ms > 0.0
        {
            frametimes.push(ms);
        }
    }
    Ok(frametimes)
}

/// Method: avg FPS = 1000 / mean frametime; "1% low" = 1000 / mean of the
/// worst 1% of frametimes (0.1% analogous, minimum one frame each).
pub fn compute_game_metrics(frametimes: &[f64]) -> Option<GameMetrics> {
    if frametimes.len() < 2 {
        return None;
    }
    let n = frametimes.len();
    let mean = frametimes.iter().sum::<f64>() / n as f64;
    let variance = frametimes.iter().map(|x| (x - mean).powi(2)).sum::<f64>() / n as f64;

    let mut sorted = frametimes.to_vec();
    sorted.sort_by(|a, b| b.partial_cmp(a).unwrap_or(std::cmp::Ordering::Equal));
    let worst_mean = |fraction: f64| -> f64 {
        let count = ((n as f64 * fraction).floor() as usize).max(1);
        sorted[..count].iter().sum::<f64>() / count as f64
    };

    Some(GameMetrics {
        frames: n as u32,
        fps_avg: round2(1000.0 / mean),
        fps_1_low: round2(1000.0 / worst_mean(0.01)),
        fps_01_low: round2(1000.0 / worst_mean(0.001)),
        frametime_avg_ms: round2(mean),
        frametime_stddev_ms: round2(variance.sqrt()),
    })
}

fn round2(x: f64) -> f64 {
    (x * 100.0).round() / 100.0
}

/// Millisecond timestamp + in-process counter: two runs in the same second
/// (e.g. a system snapshot followed by a capture) must never share an id —
/// found live when a game run overwrote a system run's JSON.
fn new_run_id() -> String {
    use std::sync::atomic::{AtomicU32, Ordering};
    static RUN_COUNTER: AtomicU32 = AtomicU32::new(0);
    let n = RUN_COUNTER.fetch_add(1, Ordering::Relaxed) % 100;
    format!("{}{n:02}", chrono::Local::now().format("%Y%m%dT%H%M%S%3f"))
}

fn save_run(run: &BenchmarkRun) -> Result<(), BenchmarkError> {
    let root = benchmarks_root();
    std::fs::create_dir_all(&root).map_err(io_err(&root))?;
    let path = root.join(format!("{}.json", run.id));
    let json = serde_json::to_string_pretty(run)
        .map_err(|e| BenchmarkError::InvalidRun(run.id.clone(), e))?;
    std::fs::write(&path, json).map_err(io_err(&path))
}

/// Timed PresentMon capture of one process. The raw CSV is kept next to the
/// run JSON so numbers can always be re-checked.
pub fn run_game_capture(
    process: &str,
    duration_s: u32,
    label: Option<String>,
) -> Result<BenchmarkRun, BenchmarkError> {
    use std::os::windows::process::CommandExt;

    let presentmon = resolve_presentmon()?;
    let id = new_run_id();
    let root = benchmarks_root();
    std::fs::create_dir_all(&root).map_err(io_err(&root))?;
    let csv_path = root.join(format!("{id}.csv"));

    tracing::info!(process, duration_s, "starting PresentMon capture");
    let output = Command::new(&presentmon)
        .args([
            "--process_name",
            process,
            "--output_file",
            &csv_path.display().to_string(),
            "--timed",
            &duration_s.to_string(),
            "--terminate_after_timed",
            "--stop_existing_session",
            "--no_console_stats",
        ])
        .creation_flags(CREATE_NO_WINDOW)
        .output()?;
    if !output.status.success() {
        return Err(BenchmarkError::CaptureFailed {
            code: output.status.code().unwrap_or(-1),
            stderr: String::from_utf8_lossy(&output.stderr).trim().to_string(),
        });
    }

    let csv = std::fs::read_to_string(&csv_path).map_err(|_| BenchmarkError::NoFrames {
        process: process.to_string(),
    })?;
    let frametimes = parse_frametimes_csv(&csv)?;
    let game = compute_game_metrics(&frametimes).ok_or(BenchmarkError::NoFrames {
        process: process.to_string(),
    })?;
    tracing::info!(
        frames = game.frames,
        fps_avg = game.fps_avg,
        "capture finished"
    );

    let run = BenchmarkRun {
        id,
        created: chrono::Local::now().to_rfc3339(),
        label,
        process: Some(process.to_string()),
        duration_s: Some(duration_s),
        game: Some(game),
        system: None,
    };
    save_run(&run)?;
    Ok(run)
}

/// Cheap idle system metrics via engine/Measure-System.ps1.
pub fn run_system_metrics(
    engine_dir: &Path,
    label: Option<String>,
) -> Result<BenchmarkRun, BenchmarkError> {
    let script = engine_dir.join("Measure-System.ps1");
    let system: SystemMetrics = powershell::run_script_json(&script, &[])?;
    let run = BenchmarkRun {
        id: new_run_id(),
        created: chrono::Local::now().to_rfc3339(),
        label,
        process: None,
        duration_s: None,
        game: None,
        system: Some(system),
    };
    save_run(&run)?;
    Ok(run)
}

/// Every stored run, newest first.
pub fn list_runs() -> Result<Vec<BenchmarkRun>, BenchmarkError> {
    let root = benchmarks_root();
    let mut runs = Vec::new();
    let entries = match std::fs::read_dir(&root) {
        Ok(e) => e,
        Err(ref e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(runs),
        Err(source) => {
            return Err(BenchmarkError::Io {
                path: root.display().to_string(),
                source,
            });
        }
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().is_none_or(|e| e != "json") {
            continue;
        }
        match std::fs::read_to_string(&path)
            .map_err(io_err(&path))
            .and_then(|raw| {
                serde_json::from_str::<BenchmarkRun>(&raw)
                    .map_err(|e| BenchmarkError::InvalidRun(path.display().to_string(), e))
            }) {
            Ok(run) => runs.push(run),
            Err(e) => tracing::warn!("skipping unreadable benchmark run: {e}"),
        }
    }
    runs.sort_by(|a, b| b.id.cmp(&a.id));
    Ok(runs)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_v2_frametime_column() {
        let csv = "Application,ProcessID,SwapChainAddress,PresentRuntime,FrameTime,CPUBusy\n\
                   game.exe,123,0x1,DXGI,10.0,5.0\n\
                   game.exe,123,0x1,DXGI,12.5,5.0\n";
        let ft = parse_frametimes_csv(csv).expect("parse");
        assert_eq!(ft, vec![10.0, 12.5]);
    }

    #[test]
    fn parses_v1_msbetweenpresents_column() {
        let csv = "Application,ProcessID,MsBetweenPresents,MsInPresentAPI\n\
                   game.exe,123,16.6,1.0\n\
                   game.exe,123,17.0,1.0\n";
        let ft = parse_frametimes_csv(csv).expect("parse");
        assert_eq!(ft, vec![16.6, 17.0]);
    }

    #[test]
    fn csv_without_frametime_column_is_rejected() {
        let r = parse_frametimes_csv("a,b,c\n1,2,3\n");
        assert!(matches!(r, Err(BenchmarkError::InvalidCsv)));
    }

    #[test]
    fn malformed_rows_are_skipped() {
        let csv = "FrameTime\n10.0\nnot-a-number\n-5.0\n20.0\n";
        let ft = parse_frametimes_csv(csv).expect("parse");
        assert_eq!(ft, vec![10.0, 20.0]);
    }

    #[test]
    fn metrics_match_hand_computed_values() {
        // 99 frames at 10 ms + 1 frame at 50 ms.
        let mut ft = vec![10.0; 99];
        ft.push(50.0);
        let m = compute_game_metrics(&ft).expect("metrics");
        assert_eq!(m.frames, 100);
        assert_eq!(m.frametime_avg_ms, 10.4);
        assert_eq!(m.fps_avg, 96.15); // 1000 / 10.4
        assert_eq!(m.fps_1_low, 20.0); // worst 1% = the 50 ms frame
        assert_eq!(m.fps_01_low, 20.0); // worst 0.1% (min 1 frame) = same frame
        // stddev = sqrt(99*(0.4^2) + (39.6^2)) / 100) = sqrt(15.84) = 3.98
        assert_eq!(m.frametime_stddev_ms, 3.98);
    }

    #[test]
    fn too_few_frames_yield_no_metrics() {
        assert!(compute_game_metrics(&[16.6]).is_none());
        assert!(compute_game_metrics(&[]).is_none());
    }

    #[test]
    fn run_ids_are_unique_even_within_one_millisecond() {
        let ids: Vec<String> = (0..50).map(|_| new_run_id()).collect();
        let mut dedup = ids.clone();
        dedup.sort();
        dedup.dedup();
        assert_eq!(dedup.len(), ids.len(), "duplicate run ids: {ids:?}");
    }
}
