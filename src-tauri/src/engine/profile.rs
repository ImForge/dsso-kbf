//! SystemProfile: the Rust mirror of the JSON emitted by engine/Detect-System.ps1.
//! The schema lives in CLAUDE.md — keep both sides in sync.

use serde::{Deserialize, Serialize};

use crate::engine::powershell::{self, PowershellError};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemProfile {
    pub os: Os,
    pub cpu: Cpu,
    pub gpu: Vec<Gpu>,
    pub ram_mb: u64,
    pub storage: Vec<StorageDrive>,
    pub form_factor: FormFactor,
    pub state: SystemState,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Os {
    pub build: u32,
    pub version: String,
    pub edition: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Cpu {
    pub vendor: CpuVendor,
    pub name: String,
    pub cores: u32,
    pub threads: u32,
    pub hybrid: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum CpuVendor {
    Intel,
    Amd,
    #[serde(other)]
    Unknown,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Gpu {
    pub vendor: GpuVendor,
    pub name: String,
    pub driver: String,
    pub vram_mb: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum GpuVendor {
    Nvidia,
    Amd,
    Intel,
    #[serde(other)]
    Unknown,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StorageDrive {
    pub drive: String,
    #[serde(rename = "type")]
    pub kind: StorageKind,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum StorageKind {
    Nvme,
    Ssd,
    Hdd,
    #[serde(other)]
    Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum FormFactor {
    Laptop,
    Desktop,
    #[serde(other)]
    Unknown,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemState {
    pub vbs_enabled: bool,
    pub hvci_enabled: bool,
    pub hags_enabled: bool,
    pub game_mode: bool,
    pub game_dvr: bool,
    pub power_plan: String,
    pub fso_global: bool,
    pub mouse_accel: bool,
}

/// Run Detect-System.ps1 and parse the result.
pub fn detect() -> Result<SystemProfile, PowershellError> {
    let dir = powershell::resolve_engine_dir()?;
    let started = std::time::Instant::now();
    let profile: SystemProfile = powershell::run_script_json(&dir.join("Detect-System.ps1"))?;
    tracing::info!(
        elapsed_ms = started.elapsed().as_millis() as u64,
        build = profile.os.build,
        gpus = profile.gpu.len(),
        "system profile detected"
    );
    Ok(profile)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture(name: &str) -> SystemProfile {
        let path = format!("{}/../tests/fixtures/{name}", env!("CARGO_MANIFEST_DIR"));
        let raw = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{path}: {e}"));
        serde_json::from_str(&raw).unwrap_or_else(|e| panic!("{path}: {e}"))
    }

    #[test]
    fn nvidia_laptop_fixture_deserializes() {
        let p = fixture("nvidia-laptop.json");
        assert_eq!(p.gpu[0].vendor, GpuVendor::Nvidia);
        assert_eq!(p.form_factor, FormFactor::Laptop);
        assert!(p.os.build >= 22000);
    }

    #[test]
    fn amd_desktop_fixture_deserializes() {
        let p = fixture("amd-desktop.json");
        assert_eq!(p.cpu.vendor, CpuVendor::Amd);
        assert_eq!(p.gpu[0].vendor, GpuVendor::Amd);
        assert_eq!(p.form_factor, FormFactor::Desktop);
    }

    #[test]
    fn intel_igpu_fixture_deserializes() {
        let p = fixture("intel-igpu.json");
        assert_eq!(p.cpu.vendor, CpuVendor::Intel);
        assert_eq!(p.gpu[0].vendor, GpuVendor::Intel);
        assert_eq!(p.storage[0].kind, StorageKind::Ssd);
    }

    #[test]
    fn unknown_vendor_falls_back() {
        let raw = r#"{"vendor":"matrox","name":"x","driver":"1","vram_mb":64}"#;
        let gpu: Gpu = serde_json::from_str(raw).expect("gpu");
        assert_eq!(gpu.vendor, GpuVendor::Unknown);
    }
}
