// Mirrors the Rust structs in src-tauri/src/engine/ and src-tauri/src/commands/.
// StartupStatus is camelCase (serde rename_all); everything else keeps the
// snake_case JSON schema from CLAUDE.md.

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

// ---- tweaks ----------------------------------------------------------------

export type Impact = "low" | "medium" | "high";
export type Risk = "safe" | "caution" | "advanced";
export type DetectState = "applied" | "not-applied" | "partial" | "unknown";

export interface TweakRequires {
  os_min_build: number | null;
  gpu_vendor: GpuVendor | GpuVendor[] | null;
  cpu_vendor: CpuVendor | CpuVendor[] | null;
  form_factor: FormFactor | FormFactor[] | null;
}

export interface TweakManifest {
  id: string;
  name: string;
  category: string;
  description: string;
  impact: Impact;
  risk: Risk;
  requires: TweakRequires;
  touches: string[];
  warning: string | null;
  list_driven: boolean;
  toggle: boolean;
}

export type ToggleTarget = "on" | "off";

export interface ToggleInfo {
  current: ToggleTarget | string;
  recommended: ToggleTarget | string;
  reason: string;
}

export interface TweakListEntry {
  manifest: TweakManifest;
  applicable: boolean;
}

export interface TweakItem {
  id: string;
  name: string;
  detail: string | null;
  active: boolean;
}

export interface TweakSelection {
  id: string;
  items?: string[];
  target?: ToggleTarget;
}

export type TweakRunStatus = "applied" | "failed" | "reverted" | "skipped";

export interface ApplyResultEntry {
  id: string;
  status: TweakRunStatus;
  requires_reboot: boolean;
  error: string | null;
}

export interface RestorePointResult {
  created: boolean;
  reason: string;
}

export interface ApplySummary {
  session_id: string;
  restore_point: RestorePointResult;
  results: ApplyResultEntry[];
}

// ---- backups ---------------------------------------------------------------

export interface TweakRunRecord {
  id: string;
  status: TweakRunStatus;
  requires_reboot: boolean;
  error: string | null;
  backup_files: string[];
  items: string[];
  target: string | null;
}

export interface SessionRecord {
  id: string;
  created: string;
  restore_point: RestorePointResult;
  tweaks: TweakRunRecord[];
}

export interface RevertEntry {
  id: string;
  ok: boolean;
  error: string | null;
}

// ---- benchmarks --------------------------------------------------------------

export interface GameMetrics {
  frames: number;
  fps_avg: number;
  fps_1_low: number;
  fps_01_low: number;
  frametime_avg_ms: number;
  frametime_stddev_ms: number;
}

export interface SystemMetrics {
  cpu_usage_percent: number;
  ram_used_mb: number;
  ram_total_mb: number;
  boot_time_ms: number | null;
}

export interface BenchmarkRun {
  id: string;
  created: string;
  label: string | null;
  process: string | null;
  duration_s: number | null;
  game: GameMetrics | null;
  system: SystemMetrics | null;
}
