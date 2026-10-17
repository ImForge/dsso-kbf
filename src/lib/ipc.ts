// Typed wrappers around tauri invoke(). Every IPC call the frontend makes
// goes through this file.

import { invoke } from "@tauri-apps/api/core";
import type {
  ApplySummary,
  BenchmarkRun,
  DetectState,
  RevertEntry,
  SessionRecord,
  StartupStatus,
  SystemProfile,
  ToggleInfo,
  TweakItem,
  TweakListEntry,
  TweakSelection,
} from "./types";

export function getStartupStatus(): Promise<StartupStatus> {
  return invoke<StartupStatus>("startup_status");
}

export function getSystemProfile(refresh = false): Promise<SystemProfile> {
  return invoke<SystemProfile>("get_system_profile", { refresh });
}

export function listTweaks(): Promise<TweakListEntry[]> {
  return invoke<TweakListEntry[]>("list_tweaks");
}

export function detectTweak(id: string, items?: string[]): Promise<DetectState> {
  return invoke<DetectState>("detect_tweak", { id, items: items ?? null });
}

export function getTweakItems(id: string): Promise<TweakItem[]> {
  return invoke<TweakItem[]>("get_tweak_items", { id });
}

export function getTweakToggle(id: string): Promise<ToggleInfo> {
  return invoke<ToggleInfo>("get_tweak_toggle", { id });
}

export function applyTweaks(selections: TweakSelection[]): Promise<ApplySummary> {
  return invoke<ApplySummary>("apply_tweaks", { selections });
}

export function listBackupSessions(): Promise<SessionRecord[]> {
  return invoke<SessionRecord[]>("list_backup_sessions");
}

export function revertBackupSession(sessionId: string): Promise<RevertEntry[]> {
  return invoke<RevertEntry[]>("revert_backup_session", { sessionId });
}

export function revertBackupTweak(sessionId: string, tweakId: string): Promise<void> {
  return invoke<void>("revert_backup_tweak", { sessionId, tweakId });
}

export function runGameBenchmark(
  process: string,
  durationS: number,
  label?: string,
): Promise<BenchmarkRun> {
  return invoke<BenchmarkRun>("run_game_benchmark", {
    process,
    durationS,
    label: label ?? null,
  });
}

export function runSystemBenchmark(label?: string): Promise<BenchmarkRun> {
  return invoke<BenchmarkRun>("run_system_benchmark", { label: label ?? null });
}

export function listBenchmarkRuns(): Promise<BenchmarkRun[]> {
  return invoke<BenchmarkRun[]>("list_benchmark_runs");
}
