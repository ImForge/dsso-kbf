use tauri::State;

use crate::AppState;
use crate::engine::benchmark::{self, BenchmarkRun};

#[tauri::command]
pub async fn run_game_benchmark(
    state: State<'_, AppState>,
    process: String,
    duration_s: u32,
    label: Option<String>,
) -> Result<BenchmarkRun, String> {
    let process = process.trim().to_string();
    if process.is_empty() {
        return Err("process name is empty".into());
    }
    let duration = duration_s.clamp(5, 600);
    let lock = state.bench_lock.clone();
    tauri::async_runtime::spawn_blocking(move || {
        let _guard = lock
            .try_lock()
            .map_err(|_| "a capture is already running".to_string())?;
        benchmark::run_game_capture(&process, duration, label).map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn run_system_benchmark(
    state: State<'_, AppState>,
    label: Option<String>,
) -> Result<BenchmarkRun, String> {
    let reg = state.registry.clone();
    let lock = state.bench_lock.clone();
    tauri::async_runtime::spawn_blocking(move || {
        let _guard = lock
            .try_lock()
            .map_err(|_| "a capture is already running".to_string())?;
        benchmark::run_system_metrics(reg.engine_dir(), label).map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn list_benchmark_runs() -> Result<Vec<BenchmarkRun>, String> {
    tauri::async_runtime::spawn_blocking(|| benchmark::list_runs().map_err(|e| e.to_string()))
        .await
        .map_err(|e| e.to_string())?
}
