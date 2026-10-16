use crate::engine::{logging, system};

#[tauri::command]
pub fn startup_status() -> system::StartupStatus {
    let os = system::os_info();
    system::StartupStatus {
        elevated: system::is_elevated(),
        os_build: os.build,
        os_revision: os.revision,
        os_version: os.version,
        os_edition: os.edition,
        os_supported: os.build >= system::MIN_SUPPORTED_BUILD,
        log_dir: logging::log_dir().display().to_string(),
    }
}
