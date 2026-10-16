// Mirrors the Rust structs in src-tauri/src/engine/.
// StartupStatus is camelCase (serde rename_all); SystemProfile keeps the
// snake_case JSON schema from CLAUDE.md as emitted by Detect-System.ps1.

export interface StartupStatus {
  elevated: boolean;
  osBuild: number;
  osRevision: number;
  osVersion: string;
  osEdition: string;
  osSupported: boolean;
  logDir: string;
}

export type CpuVendor = "intel" | "amd" | "unknown";
export type GpuVendor = "nvidia" | "amd" | "intel" | "unknown";
export type StorageKind = "nvme" | "ssd" | "hdd" | "unknown";
export type FormFactor = "laptop" | "desktop" | "unknown";

export interface SystemProfile {
  os: { build: number; version: string; edition: string };
  cpu: {
    vendor: CpuVendor;
    name: string;
    cores: number;
    threads: number;
    hybrid: boolean;
  };
  gpu: {
    vendor: GpuVendor;
    name: string;
    driver: string;
    vram_mb: number;
  }[];
  ram_mb: number;
  storage: { drive: string; type: StorageKind }[];
  form_factor: FormFactor;
  state: {
    vbs_enabled: boolean;
    hvci_enabled: boolean;
    hags_enabled: boolean;
    game_mode: boolean;
    game_dvr: boolean;
    power_plan: string;
    fso_global: boolean;
    mouse_accel: boolean;
  };
}
