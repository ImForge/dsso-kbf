mod commands;
mod engine;

use engine::system;
use tracing::{error, info};

fn show_error_box(message: &str) {
    use windows::core::PCWSTR;
    use windows::Win32::UI::WindowsAndMessaging::{MessageBoxW, MB_ICONERROR, MB_OK};

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

    let result = tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![commands::startup::startup_status])
        .run(tauri::generate_context!());
    if let Err(e) = result {
        fatal(&format!("tauri runtime error: {e}"));
    }
}
