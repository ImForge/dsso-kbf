use serde::Serialize;
use windows::Win32::Foundation::{CloseHandle, HANDLE};
use windows::Win32::Security::{GetTokenInformation, TOKEN_ELEVATION, TOKEN_QUERY, TokenElevation};
use windows::Win32::System::Threading::{GetCurrentProcess, OpenProcessToken};

/// Any Windows 11 build.
pub const MIN_SUPPORTED_BUILD: u32 = 22000;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StartupStatus {
    pub version: String,
    pub elevated: bool,
    pub os_build: u32,
    pub os_revision: u32,
    pub os_version: String,
    pub os_edition: String,
    pub os_supported: bool,
    pub log_dir: String,
}

/// True when the current process token is elevated (running as administrator).
pub fn is_elevated() -> bool {
    unsafe {
        let mut token = HANDLE::default();
        if OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &mut token).is_err() {
            return false;
        }
        let mut elevation = TOKEN_ELEVATION::default();
        let mut returned = 0u32;
        let result = GetTokenInformation(
            token,
            TokenElevation,
            Some(&mut elevation as *mut TOKEN_ELEVATION as *mut _),
            std::mem::size_of::<TOKEN_ELEVATION>() as u32,
            &mut returned,
        );
        let _ = CloseHandle(token);
        result.is_ok() && elevation.TokenIsElevated != 0
    }
}

#[derive(Debug, Clone)]
pub struct OsInfo {
    pub build: u32,
    pub revision: u32,
    pub version: String,
    pub edition: String,
}

/// Build/version/edition from HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion.
/// The registry is the reliable source here: GetVersionExW lies depending on
/// the compatibility manifest.
pub fn os_info() -> OsInfo {
    let key = windows_registry::LOCAL_MACHINE.open(r"SOFTWARE\Microsoft\Windows NT\CurrentVersion");
    match key {
        Ok(key) => OsInfo {
            build: key
                .get_string("CurrentBuildNumber")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(0),
            revision: key.get_u32("UBR").unwrap_or(0),
            version: key.get_string("DisplayVersion").unwrap_or_default(),
            edition: key.get_string("EditionID").unwrap_or_default(),
        },
        Err(_) => OsInfo {
            build: 0,
            revision: 0,
            version: String::new(),
            edition: String::new(),
        },
    }
}
