//! dsso-cli.exe — console CLI sharing the engine with the GUI (see CLAUDE.md, CLI).
//! Note: the embedded requireAdministrator manifest applies to every bin in the
//! crate, so run this from an elevated terminal.

use std::path::PathBuf;

use dsso_kbf_lib::engine::{backup, logging, powershell, profile, registry};
use registry::{Risk, Tweak, TweakRegistry};
use serde::Deserialize;

fn print_usage() {
    eprintln!(
        "Da Sigma Squads Optimizer KBF — CLI\n\
         \n\
         Usage: dsso-cli <command>\n\
         \n\
         Commands:\n\
         \x20 profile                          print the detected SystemProfile as JSON\n\
         \x20 list [--tier safe|caution|advanced]   list applicable tweaks with current state\n\
         \x20 dry-run <profile|tweak-id...>    show exactly what would change, change nothing\n\
         \x20 apply <profile|tweak-id...>      backup + apply tweaks (one session)\n\
         \x20 revert <session-id|all>          revert a backup session (newest first for all)"
    );
}

fn main() {
    logging::init();
    let args: Vec<String> = std::env::args().skip(1).collect();
    let code = match args.first().map(String::as_str) {
        Some("profile") => cmd_profile(),
        Some("list") => cmd_list(&args[1..]),
        Some("dry-run") => cmd_dry_run(&args[1..]),
        Some("apply") => cmd_apply(&args[1..]),
        Some("revert") => cmd_revert(&args[1..]),
        _ => {
            print_usage();
            2
        }
    };
    std::process::exit(code);
}

// ---- shared helpers -------------------------------------------------------

fn fail(message: &str) -> i32 {
    eprintln!("error: {message}");
    1
}

fn load_registry() -> Result<TweakRegistry, String> {
    let engine = powershell::resolve_engine_dir().map_err(|e| e.to_string())?;
    let (reg, errors) = TweakRegistry::load(&engine);
    for e in &errors {
        eprintln!("warning: tweak refused: {e}");
    }
    Ok(reg)
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ProfileFile {
    name: String,
    #[allow(dead_code)]
    tiers: Vec<String>,
    tweaks: Vec<String>,
}

/// Resolve CLI targets (tweak ids and/or profile names) into applicable tweaks,
/// preserving order and deduplicating. Non-applicable tweaks are skipped with a
/// warning; unknown targets are an error.
fn resolve_targets<'a>(
    reg: &'a TweakRegistry,
    system: &profile::SystemProfile,
    targets: &[String],
) -> Result<Vec<&'a Tweak>, String> {
    let mut out: Vec<&Tweak> = Vec::new();
    let mut push = |tweak: &'a Tweak, from_profile: bool| {
        if out.iter().any(|t| t.id() == tweak.id()) {
            return;
        }
        if !tweak.is_applicable(system) {
            // Profiles are expected to contain tweaks for other machines; only
            // warn loudly when the user named the tweak explicitly.
            if !from_profile {
                eprintln!(
                    "warning: {} is not applicable to this machine — skipped",
                    tweak.id()
                );
            }
            return;
        }
        out.push(tweak);
    };

    for target in targets {
        if let Some(tweak) = reg.get(target) {
            push(tweak, false);
            continue;
        }
        let profile_path = reg
            .engine_dir()
            .join("profiles")
            .join(format!("{target}.json"));
        if profile_path.is_file() {
            let raw = std::fs::read_to_string(&profile_path)
                .map_err(|e| format!("cannot read {}: {e}", profile_path.display()))?;
            let pf: ProfileFile = serde_json::from_str(&raw)
                .map_err(|e| format!("invalid profile {}: {e}", profile_path.display()))?;
            for id in &pf.tweaks {
                match reg.get(id) {
                    Some(tweak) => push(tweak, true),
                    None => eprintln!("warning: profile {} names unknown tweak {id}", pf.name),
                }
            }
            continue;
        }
        return Err(format!("unknown tweak or profile: {target}"));
    }
    Ok(out)
}

// ---- commands -------------------------------------------------------------

fn cmd_profile() -> i32 {
    match profile::detect() {
        Ok(p) => match serde_json::to_string_pretty(&p) {
            Ok(json) => {
                println!("{json}");
                0
            }
            Err(e) => fail(&format!("cannot serialise profile: {e}")),
        },
        Err(e) => fail(&e.to_string()),
    }
}

fn parse_tier(args: &[String]) -> Result<Option<Risk>, String> {
    match args {
        [] => Ok(None),
        [flag, value] if flag == "--tier" => match value.as_str() {
            "safe" => Ok(Some(Risk::Safe)),
            "caution" => Ok(Some(Risk::Caution)),
            "advanced" => Ok(Some(Risk::Advanced)),
            other => Err(format!("unknown tier: {other}")),
        },
        _ => Err("usage: list [--tier safe|caution|advanced]".into()),
    }
}

fn cmd_list(args: &[String]) -> i32 {
    let tier = match parse_tier(args) {
        Ok(t) => t,
        Err(e) => return fail(&e),
    };
    let reg = match load_registry() {
        Ok(r) => r,
        Err(e) => return fail(&e),
    };
    let system = match profile::detect() {
        Ok(p) => p,
        Err(e) => return fail(&e.to_string()),
    };

    println!(
        "{} · {} · build {}",
        system.cpu.name,
        match system.form_factor {
            profile::FormFactor::Laptop => "laptop",
            profile::FormFactor::Desktop => "desktop",
            profile::FormFactor::Unknown => "unknown form factor",
        },
        system.os.build
    );

    let tweaks: Vec<&Tweak> = reg
        .applicable(&system)
        .into_iter()
        .filter(|t| tier.is_none_or(|x| t.manifest.risk == x))
        .collect();
    println!("Applicable tweaks: {}\n", tweaks.len());
    for tweak in tweaks {
        let state = registry::detect(reg.engine_dir(), tweak)
            .map(|s| s.to_string())
            .unwrap_or_else(|e| format!("detect-error: {e}"));
        println!(
            "  {:<28} {:<9} {:<7} {:<12} {}",
            tweak.id(),
            tweak.manifest.risk.to_string(),
            format!("{:?}", tweak.manifest.impact).to_lowercase(),
            state,
            tweak.manifest.name
        );
    }
    0
}

fn cmd_dry_run(targets: &[String]) -> i32 {
    if targets.is_empty() {
        return fail("usage: dry-run <profile|tweak-id...>");
    }
    let reg = match load_registry() {
        Ok(r) => r,
        Err(e) => return fail(&e),
    };
    let system = match profile::detect() {
        Ok(p) => p,
        Err(e) => return fail(&e.to_string()),
    };
    let tweaks = match resolve_targets(&reg, &system, targets) {
        Ok(t) => t,
        Err(e) => return fail(&e),
    };
    if tweaks.is_empty() {
        println!("Nothing applicable to dry-run.");
        return 0;
    }

    println!("DRY RUN — nothing will be changed.\n");
    for tweak in tweaks {
        let state = registry::detect(reg.engine_dir(), tweak)
            .map(|s| s.to_string())
            .unwrap_or_else(|e| format!("detect-error: {e}"));
        println!("{} — {}", tweak.id(), tweak.manifest.name);
        println!(
            "  risk: {} · impact: {:?} · currently: {state}",
            tweak.manifest.risk, tweak.manifest.impact
        );
        if let Some(w) = &tweak.manifest.warning {
            println!("  WARNING: {w}");
        }
        println!("  would change:");
        for touch in &tweak.manifest.touches {
            println!("    {touch}");
        }
        println!();
    }
    0
}

fn cmd_apply(targets: &[String]) -> i32 {
    if targets.is_empty() {
        return fail("usage: apply <profile|tweak-id...>");
    }
    let reg = match load_registry() {
        Ok(r) => r,
        Err(e) => return fail(&e),
    };
    let system = match profile::detect() {
        Ok(p) => p,
        Err(e) => return fail(&e.to_string()),
    };
    let tweaks = match resolve_targets(&reg, &system, targets) {
        Ok(t) => t,
        Err(e) => return fail(&e),
    };
    if tweaks.is_empty() {
        println!("Nothing applicable to apply.");
        return 0;
    }

    let mut session = match backup::Session::begin(reg.engine_dir()) {
        Ok(s) => s,
        Err(e) => return fail(&format!("cannot start backup session: {e}")),
    };
    if session.record.restore_point.created {
        println!("System restore point created.");
    } else {
        let reason = match session.record.restore_point.reason.as_str() {
            "24h-skip" => "Windows skips restore points within 24h of the last one".to_string(),
            "protection-off" => "System Protection is disabled on C:".to_string(),
            other => other.to_string(),
        };
        println!(
            "WARNING: no system restore point ({reason}) — continuing with per-tweak backups."
        );
    }
    println!(
        "Session {} — backups in {}\n",
        session.record.id,
        session.dir.display()
    );

    let mut failed = 0usize;
    let mut reboot = false;
    for tweak in tweaks {
        match backup::apply_tweak(&reg, &mut session, tweak) {
            Ok(outcome) => {
                reboot = reboot || outcome.record.requires_reboot;
                match outcome.record.status {
                    backup::TweakRunStatus::Skipped => {
                        println!("  {:<28} skipped (already applied)", tweak.id());
                    }
                    backup::TweakRunStatus::Applied => {
                        let after = outcome
                            .state_after
                            .map(|s| s.to_string())
                            .unwrap_or_else(|| "unknown".into());
                        println!("  {:<28} applied (now: {after})", tweak.id());
                    }
                    backup::TweakRunStatus::Failed => {
                        failed += 1;
                        println!(
                            "  {:<28} FAILED: {}",
                            tweak.id(),
                            outcome.record.error.as_deref().unwrap_or("unknown error")
                        );
                    }
                    backup::TweakRunStatus::Reverted => {}
                }
            }
            Err(e) => {
                failed += 1;
                println!("  {:<28} ABORTED (backup failed): {e}", tweak.id());
            }
        }
    }

    println!("\nDone. Revert with: dsso-cli revert {}", session.record.id);
    if reboot {
        println!("One or more tweaks need a reboot to take full effect.");
    }
    if failed > 0 { 1 } else { 0 }
}

fn cmd_revert(args: &[String]) -> i32 {
    let [target] = args else {
        return fail("usage: revert <session-id|all>");
    };
    let reg = match load_registry() {
        Ok(r) => r,
        Err(e) => return fail(&e),
    };
    let sessions = match backup::list_sessions() {
        Ok(s) => s,
        Err(e) => return fail(&e.to_string()),
    };

    let selected: Vec<(PathBuf, backup::SessionRecord)> = if target == "all" {
        sessions
    } else {
        let found: Vec<_> = sessions
            .into_iter()
            .filter(|(_, r)| &r.id == target)
            .collect();
        if found.is_empty() {
            return fail(&format!("session {target} not found"));
        }
        found
    };
    if selected.is_empty() {
        println!("No backup sessions found.");
        return 0;
    }

    let mut failed = 0usize;
    for (dir, record) in selected {
        println!("Reverting session {}:", record.id);
        match backup::revert_session(&reg, &dir) {
            Ok(results) => {
                if results.is_empty() {
                    println!("  nothing to revert (no applied tweaks)");
                }
                for (id, result) in results {
                    match result {
                        Ok(()) => println!("  {id:<28} reverted"),
                        Err(e) => {
                            failed += 1;
                            println!("  {id:<28} FAILED: {e}");
                        }
                    }
                }
            }
            Err(e) => {
                failed += 1;
                println!("  session error: {e}");
            }
        }
    }
    if failed > 0 { 1 } else { 0 }
}
