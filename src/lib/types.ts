// Mirrors the Rust structs in src-tauri/src/engine/ (serde camelCase).

export interface StartupStatus {
  elevated: boolean;
  osBuild: number;
  osRevision: number;
  osVersion: string;
  osEdition: string;
  osSupported: boolean;
  logDir: string;
}
