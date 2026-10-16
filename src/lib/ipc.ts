// Typed wrappers around tauri invoke(). Every IPC call the frontend makes
// goes through this file.

import { invoke } from "@tauri-apps/api/core";
import type { StartupStatus } from "./types";

export function getStartupStatus(): Promise<StartupStatus> {
  return invoke<StartupStatus>("startup_status");
}
