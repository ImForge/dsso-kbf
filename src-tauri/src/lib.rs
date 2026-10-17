pub mod commands;
pub mod engine;

use std::sync::{Arc, Mutex};

use engine::profile::SystemProfile;
use engine::registry::TweakRegistry;
use engine::system;
use tracing::{error, info};

pub struct AppState {
    pub registry: Arc<TweakRegistry>,
    pub registry_errors: Vec<String>,
    pub profile: Mutex<Option<SystemProfile>>,
    pub apply_lock: Arc<Mutex<()>>,
    pub bench_lock: Arc<Mutex<()>>,
}

fn show_error_box(message: &str) {
    use windows::Win32::UI::WindowsAndMessaging::{MB_ICONERROR, MB_OK, MessageBoxW};
    use windows::core::PCWSTR;

    let text: Vec<u16> = message.encode_utf16().chain(std::iter::once(0)).collect();
    let caption: Vec<u16> = "Da Sigma Squads Optimizer KBF"
        .encode_utf16()
        .chain(std::iter::once(0))
        .collect();
    unsafe {
        MessageBoxW(
            None,
            PCWSTR(text.as_ptr()),
            PCWSTR(caption.as_ptr()),
            MB_OK | MB_ICONERROR,
        );
    }
}

fn fatal(message: &str) -> ! {
    error!("{message}");
    show_error_box(message);
    std::process::exit(1);
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let log_dir = engine::logging::init();
    info!(
        version = env!("CARGO_PKG_VERSION"),
        log_dir = %log_dir.display(),
        "Da Sigma Squads Optimizer KBF starting"
    );

    let os = system::os_info();
    info!(
        build = os.build,
        revision = os.revision,
        version = %os.version,
        edition = %os.edition,
        "detected OS"
    );
    if os.build < system::MIN_SUPPORTED_BUILD {
        fatal(&format!(
            "Da Sigma Squads Optimizer KBF requires Windows 11 (build {} or newer). \
             This system reports build {}.",
            system::MIN_SUPPORTED_BUILD,
            os.build
        ));
    }

    if !system::is_elevated() {
        fatal(
            "Da Sigma Squads Optimizer KBF must run as administrator. \
             Right-click dsso-kbf.exe and choose \"Run as administrator\".",
        );
    }
    info!("running elevated");

    let engine_dir = match engine::powershell::resolve_engine_dir() {
        Ok(d) => d,
        Err(e) => fatal(&format!(
            "The tweak engine folder is missing ({e}). Reinstall Da Sigma Squads Optimizer KBF."
        )),
    };
    let (registry, errors) = TweakRegistry::load(&engine_dir);
    let state = AppState {
        registry: Arc::new(registry),
        registry_errors: errors.iter().map(|e| e.to_string()).collect(),
        profile: Mutex::new(None),
        apply_lock: Arc::new(Mutex::new(())),
        bench_lock: Arc::new(Mutex::new(())),
    };

    let result = tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .manage(state)
        .invoke_handler(tauri::generate_handler![
            commands::startup::startup_status,
            commands::profile::get_system_profile,
            commands::tweaks::list_tweaks,
            commands::tweaks::detect_tweak,
            commands::tweaks::get_tweak_items,
            commands::tweaks::get_tweak_toggle,
            commands::tweaks::apply_tweaks,
            commands::backups::list_backup_sessions,
            commands::backups::revert_backup_session,
            commands::backups::revert_backup_tweak,
            commands::benchmark::run_game_benchmark,
            commands::benchmark::run_system_benchmark,
            commands::benchmark::list_benchmark_runs
        ])
        .run(tauri::generate_context!());
    if let Err(e) = result {
        fatal(&format!("tauri runtime error: {e}"));
    }
}
