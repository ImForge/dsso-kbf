//! dsso-cli.exe — console CLI sharing the engine with the GUI (see CLAUDE.md, CLI).
//! Note: the embedded requireAdministrator manifest applies to every bin in the
//! crate, so run this from an elevated terminal.

use dsso_kbf_lib::engine::{logging, profile};

fn print_usage() {
    eprintln!(
        "Da Sigma Squads Optimizer KBF — CLI\n\
         \n\
         Usage: dsso-cli <command>\n\
         \n\
         Commands:\n\
         \x20 profile    print the detected SystemProfile as JSON"
    );
}

fn main() {
    logging::init();

    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("profile") => cmd_profile(),
        Some(other) => {
            eprintln!("unknown command: {other}\n");
            print_usage();
            std::process::exit(2);
        }
        None => {
            print_usage();
            std::process::exit(2);
        }
    }
}

fn cmd_profile() {
    match profile::detect() {
        Ok(p) => match serde_json::to_string_pretty(&p) {
            Ok(json) => println!("{json}"),
            Err(e) => {
                eprintln!("error: cannot serialise profile: {e}");
                std::process::exit(1);
            }
        },
        Err(e) => {
            eprintln!("error: {e}");
            std::process::exit(1);
        }
    }
}
