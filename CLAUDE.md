# Da Sigma Squads Optimizer KBF — Windows 11 Gaming Optimizer

> Display name: **Da Sigma Squads Optimizer KBF**. Short slug used for the exe, repo folder, app data folder, and Cargo/npm package name: **`dsso-kbf`**. Everything below is the spec Claude Code must follow.

## What this is

A Tauri desktop app for Windows 11 that profiles the user's hardware, recommends a set of gaming-performance tweaks specific to that machine, applies them safely with full backup + revert, and proves the result with before/after benchmarks.

The product is the **tweak engine** (PowerShell modules with a strict interface). The Tauri app is a wrapper around it. A CLI must also work without the GUI.

## Non-negotiable principles

1. **Reversible.** Every tweak has a tested `Revert`. Nothing is applied without a backup of the exact prior state.
2. **Honest.** No snake oil. No RAM cleaners, "core unparking", registry cleaners, or claims we can't measure. Impact ratings must be conservative.
3. **Specific.** Tweaks are gated on detected hardware/OS. Never show an NVIDIA tweak to an AMD user. Never show a laptop power tweak to a desktop.
4. **Safe by default.** Default profile = "safe" tier only. "caution" and "advanced" tiers require explicit opt-in with a clear warning (e.g. VBS off = security tradeoff).
5. **Transparent.** Dry-run mode shows exactly what registry keys / services / commands will change before anything runs. Everything logs to a file.
6. **Windows 11 only.** Check build number: supported = build >= 22000 (any Windows 11). Refuse to run on Win10 or anything below 22000.

## Stack

- **Tauri 2.x** — Rust backend, WebView frontend
- **Frontend:** React 18 + TypeScript + Vite + Tailwind CSS
- **Rust:** `tauri`, `serde`, `serde_json`, `tokio`, `tracing`, `thiserror`, `windows` crate where native calls are cleaner than shelling out
- **Tweak engine:** PowerShell 5.1 compatible scripts (ships with every Win11 — do NOT require PowerShell 7)
- **Benchmark:** Intel PresentMon (bundled binary under `resources/presentmon/`) for FPS / frametime capture
- **Tests:** `cargo test` (Rust), Pester 5 (PowerShell — the inbox Pester 3.4 is too old; see Dev commands for the one-time install), Vitest (frontend)
- **Admin:** the app must run elevated. Embed a Windows manifest with `requestedExecutionLevel level="requireAdministrator"` via `build.rs` using `tauri_build::WindowsAttributes::app_manifest(...)` (passed through `tauri_build::try_build`). Do NOT add `tauri-winres` or `embed-manifest` — `tauri-build` already embeds a manifest, and a second `RT_MANIFEST` resource causes link errors. Fail loudly at startup if not elevated.
- Developer uses **Windows CMD**, not PowerShell or WSL. Write all dev/build commands for CMD.
- Dev note: because of `requireAdministrator`, `npm run tauri dev` must be run from an **elevated** terminal (an unelevated parent cannot spawn the exe — os error 740).
- Dev note 2: a debug `cargo build` exe loads `devUrl` (http://localhost:1420), not the embedded dist — start Vite first (`npm run dev`) or use `npm run tauri dev`; only release builds serve the embedded frontend.

## Repo layout

```
dsso-kbf/
  CLAUDE.md
  README.md
  package.json
  src/                        # React frontend
    main.tsx
    App.tsx
    components/
    pages/                    # Dashboard, Profile, Tweaks, Benchmark, Backups, Logs
    lib/
      ipc.ts                  # typed wrappers around tauri invoke()
      types.ts                # mirrors Rust structs (SystemProfile, Tweak, TweakResult...)
  src-tauri/
    Cargo.toml
    build.rs                  # embeds admin manifest via WindowsAttributes::app_manifest
    tauri.conf.json
    src/
      main.rs
      bin/
        dsso-cli.rs           # dsso-cli.exe — separate console bin target, same engine, no GUI
      commands/               # tauri::command handlers, thin — delegate to engine/
        profile.rs
        tweaks.rs
        benchmark.rs
        backups.rs
      engine/
        mod.rs
        powershell.rs         # runs scripts, captures JSON stdout, maps errors
        registry.rs           # tweak manifest loader + validator
        profile.rs            # system detection orchestration
        backup.rs             # restore points + reg exports + manifest of what changed
        benchmark.rs          # PresentMon wrapper, parses CSV, computes avg/1%/0.1% lows
        logging.rs            # tracing -> %LOCALAPPDATA%\dsso-kbf\logs\
    resources/
      presentmon/
  engine/                     # PowerShell — the actual product
    Common.psm1               # shared helpers: Write-Result, Test-Admin, Get-RegValue, Backup-RegKey, etc.
    Detect-System.ps1         # outputs SystemProfile JSON to stdout
    tweaks/
      <tweak-id>/
        manifest.json
        tweak.ps1
    profiles/
      safe.json               # ordered list of tweak ids for each default profile
      balanced.json
      aggressive.json
  tests/
    pester/
    fixtures/                 # fake SystemProfile JSONs: nvidia-laptop, amd-desktop, intel-igpu...
```

## Tweak module contract

Every tweak lives in `engine/tweaks/<id>/` with exactly two files.

### `manifest.json`

```json
{
  "id": "disable-game-dvr",
  "name": "Disable Xbox Game DVR / background recording",
  "category": "gaming",
  "description": "Stops Game Bar background capture which costs FPS and adds input lag.",
  "impact": "medium",
  "risk": "safe",
  "requires": {
    "os_min_build": 22000,
    "gpu_vendor": null,
    "cpu_vendor": null,
    "form_factor": null
  },
  "touches": [
    "HKCU\\System\\GameConfigStore\\GameDVR_Enabled",
    "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\GameDVR\\AppCaptureEnabled"
  ],
  "warning": null
}
```

- `impact`: `low | medium | high` — be conservative
- `risk`: `safe | caution | advanced`
- `requires`: any field may be `null` (no constraint) or a value / array of allowed values. `gpu_vendor`: `nvidia | amd | intel`. `form_factor`: `laptop | desktop`.
- `touches`: every registry path, service name, scheduled task, or appx package the tweak modifies. Used for dry-run display and backup. Must be complete.
- `warning`: required (non-null) when `risk` is `caution` or `advanced`.
- `list_driven` (optional, default false): true for tweaks that act on a per-machine list of items the user confirms individually (e.g. startup entries, appx packages). See "List-driven tweaks" below.

### `tweak.ps1`

Must define exactly these four functions and nothing else at top level — allowed above them: the `Set-StrictMode`/`$ErrorActionPreference` lines, the `Import-Module` of Common.psm1, and read-only configuration variables (registry entries, GUIDs). No other top-level side effects, no extra functions (shared logic goes in Common.psm1):

```powershell
function Detect  { ... }   # returns "applied" | "not-applied" | "partial" | "unknown"
function Backup  { param($BackupDir) ... }   # saves current state into $BackupDir, returns list of files written
function Apply   { ... }   # returns $true on success; throw on failure
function Revert  { param($BackupDir) ... }   # restores from $BackupDir, returns $true
```

Rules:
- Import `Common.psm1`. Use its helpers for registry and service work so backup is consistent.
- `Apply` must be idempotent. Running it twice is harmless.
- `Apply` returns `$true`, or `@{ requiresReboot = $true }` when a reboot/sign-out is needed for full effect.
- `Revert` must restore the *exact* prior state from backup, not a "sensible default", and must be driven ONLY by the backup dir contents (never by `DSSO_KBF_ITEMS`).
- All output to the host goes through `Write-Result` (JSON to stdout). No `Write-Host` noise.
- Never `Restart-Computer`. Return `requiresReboot: true` in the result instead.
- Engine .ps1/.psm1 files are ASCII-only: PowerShell 5.1 reads BOM-less files as ANSI and non-ASCII breaks parsing.

### List-driven tweaks (owner decision 2026-10-17)

A tweak with `"list_driven": true` additionally defines a fifth function `Get-Items` returning an array of `@{ id; name; detail; active }` — the per-machine items (e.g. detected startup entries). Selection is passed via the `DSSO_KBF_ITEMS` env var (comma-separated item ids), set by Invoke-Tweak's `-Items` parameter:
- `Detect` with no selection returns `unknown`; with a selection it reports over those items.
- `Apply`/`Backup` THROW when no selection is set (safe by default — "all" must be explicit).
- The CLI skips list-driven tweaks unless `DSSO_KBF_ITEMS` is set; per-item checkboxes live in the GUI.

The Rust loader validates every manifest at startup and refuses to load a tweak whose `tweak.ps1` is missing any of the four functions (five for list-driven tweaks).

## System profile schema

`Detect-System.ps1` emits this JSON. Rust deserialises it into `SystemProfile`.

```json
{
  "os": { "build": 26100, "version": "24H2", "edition": "Pro" },
  "cpu": { "vendor": "intel", "name": "...", "cores": 8, "threads": 16, "hybrid": true },
  "gpu": [ { "vendor": "nvidia", "name": "...", "driver": "566.03", "vram_mb": 8192 } ],
  "ram_mb": 16384,
  "storage": [ { "drive": "C:", "type": "nvme" } ],
  "form_factor": "laptop",
  "state": {
    "vbs_enabled": true,
    "hvci_enabled": true,
    "hags_enabled": false,
    "game_mode": true,
    "game_dvr": true,
    "power_plan": "Balanced",
    "fso_global": true,
    "mouse_accel": true
  }
}
```

Sources: `Get-CimInstance Win32_*`, `Get-ComputerInfo`, `Win32_DeviceGuard`, registry. Add fields as tweaks need them; keep the Rust struct in sync.

## Initial tweak set (build these first, in this order)

Safe tier:
1. `disable-game-dvr`
2. `enable-game-mode`
3. `power-plan-high-performance` (desktop) / `power-plan-balanced-tuned` (laptop: keep Balanced, fix USB selective suspend + PCIe link state)
4. `disable-mouse-acceleration`
5. `disable-startup-bloat` (list-driven, user confirms each)
6. `remove-appx-bloat` (Xbox apps, Cortana, Teams consumer, etc. — list-driven, user confirms each)
7. `visual-effects-performance`
8. `disable-transparency-animations`

Caution tier:
9. `toggle-hags` (recommend based on GPU vendor + driver; expose as a toggle, not a one-way switch)
10. `disable-fullscreen-optimizations-global`
11. `nvidia-low-latency-prefer-max-perf` (requires nvidia)
12. `disable-nagle` (per adapter; `impact` must be `low` and the description must be honest: Nagle only affects TCP-based games — most modern games use UDP, where this does nothing)
13. `services-trim` (SysMain, DiagTrack, Print Spooler if no printer — detect first)

Advanced tier:
14. `disable-vbs-hvci` (big warning: reduces security, needs reboot)

**Do not implement:** RAM cleaning, core unparking, timer resolution hacks, disabling CPU vulnerability mitigations, registry "cleaning", anything whose effect we cannot measure.

## Backup & revert

- On first `Apply` of a session: create a System Restore Point (`Checkpoint-Computer`), then continue even if it fails (log it, warn user). The warning must name the actual cause: Windows silently skips restore points created within 24 h of the previous one (`SystemRestorePointCreationFrequency`), and System Protection may be disabled on C: — detect which case it was and say so.
- Every apply writes to `%LOCALAPPDATA%\dsso-kbf\backups\<ISO-timestamp>\<tweak-id>\` plus a `session.json` listing every tweak applied and its result.
- "Revert All" walks sessions newest → oldest and calls each tweak's `Revert` with its backup dir.
- Backups page in the GUI lists sessions, lets the user revert one tweak or a whole session.

## Benchmark module

- Bundle PresentMon. Rust spawns it with `--process_name <game.exe>` and CSV output.
- Parse frametimes → avg FPS, 1% low, 0.1% low, frametime stddev.
- Store results per session so "before" and "after" can be compared side by side.
- Also capture cheap system metrics: idle CPU %, idle RAM MB, boot time (from Event Log 100 under Diagnostics-Performance).
- GUI shows before/after table. If a tweak made things worse, say so.

## Profiles

A profile = ordered list of tweak ids + which tiers it includes. Three defaults ship (`safe`, `balanced`, `aggressive`). The app filters each profile against the detected `SystemProfile` so the user only ever sees tweaks their machine qualifies for.

The **Dashboard** page shows: detected hardware summary → recommended profile → N applicable tweaks → one "Review & Apply" button that opens dry-run first.

## CLI

The CLI is a **separate console bin target** (`src-tauri/src/bin/dsso-cli.rs`) that builds `dsso-cli.exe` and shares the same engine code. It is NOT a flag on the GUI exe — the GUI exe is built with the Windows GUI subsystem and has no console, so its stdout is invisible from CMD.

The embedded requireAdministrator manifest applies to every bin in the crate, so `dsso-cli.exe` also demands an elevated terminal (fine — it applies system tweaks anyway). Side effect: `cargo test` cannot execute the CLI bin's test harness unelevated — use `cargo test --lib` (all unit tests live in the lib), or run from an elevated terminal.

`dsso-cli.exe <command>`:
- `profile` — print SystemProfile JSON
- `list [--tier safe|caution|advanced]` — list applicable tweaks
- `dry-run <profile|tweak-id...>`
- `apply <profile|tweak-id...>`
- `revert <session-id|all>`
- `bench --exe <name> --duration <sec>`

Same engine, same backups, same logs as the GUI.

## Testing requirements

- Pester tests for every tweak: `Detect` returns a valid value; `Backup` writes files; `Apply` then `Detect` = applied; `Revert` then `Detect` = original state. Run inside a throwaway registry hive where possible (use `HKCU:\Software\DssoKbfTest` for unit tests, real keys only in a manual integration test).
- Rust tests for manifest validation, profile filtering against fixture SystemProfiles, PresentMon CSV parsing.
- A tweak is not done until its Pester test passes apply→revert round trip.

## Build phases

Work through these in order. Finish, test, and commit each phase before starting the next. Ask before moving on if anything in the spec is ambiguous.

1. **Scaffold** — Tauri 2 + React + Vite + Tailwind, admin manifest in `build.rs`, logging to `%LOCALAPPDATA%`, elevation check at startup. App opens, shows "running as admin: yes".
2. **Detection** — `Detect-System.ps1` + `Common.psm1`, Rust `SystemProfile` struct, `profile` IPC command + CLI command. Dashboard page renders the hardware summary.
3. **Tweak engine** — manifest loader + validator, the four-function contract, `powershell.rs` runner, backup system, tweaks 1–4 with Pester tests. CLI `list`, `dry-run`, `apply`, `revert` all working.
4. **Rest of the safe tier** (5–8) + profile filtering + Tweaks page + Backups page in the GUI.
5. **Caution + advanced tiers** (9–14) with proper warnings and opt-in UI.
6. **Benchmark** — PresentMon integration, metrics, before/after view.
7. **Polish** — README with screenshots, release build via `tauri build`, GitHub Actions workflow for Windows builds. Sign release builds with **Azure Trusted Signing** so SmartScreen / Smart App Control don't block users.

## Dev commands (CMD)

```
npm install
npm run tauri dev          (run from an ELEVATED terminal — see Admin note in Stack)
npm run tauri build
cargo test --lib --manifest-path src-tauri\Cargo.toml   (--lib: see CLI section; full `cargo test` needs an elevated terminal)
powershell -NoProfile -Command "Install-Module Pester -Force -SkipPublisherCheck"   (one-time: upgrade inbox Pester 3.4 to Pester 5)
powershell -NoProfile -Command "Invoke-Pester tests\pester"
```

## Style

- Rust: `cargo fmt`, `cargo clippy` clean, `thiserror` for error types, no `unwrap()` outside tests.
- TypeScript: strict mode, no `any`, every IPC call typed in `lib/ipc.ts`.
- PowerShell: `Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'Stop'` at the top of every script.
- Commit messages: `phase-N: short description`.
