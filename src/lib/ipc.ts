// Typed wrappers around tauri invoke(). Every IPC call the frontend makes
// goes through this file.

import { invoke } from "@tauri-apps/api/core";
import type { StartupStatus, SystemProfile } from "./types";

export function getStartupStatus(): Promise<StartupStatus> {
  return invoke<StartupStatus>("startup_status");
}

export function getSystemProfile(): Promise<SystemProfile> {
  return invoke<SystemProfile>("get_system_profile");
}
