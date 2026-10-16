use std::path::PathBuf;

use tracing_subscriber::prelude::*;

/// %LOCALAPPDATA%\dsso-kbf\logs
pub fn log_dir() -> PathBuf {
    let base = std::env::var_os("LOCALAPPDATA")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."));
    base.join("dsso-kbf").join("logs")
}

/// Initialise tracing: daily-rolling file in %LOCALAPPDATA%\dsso-kbf\logs plus stderr.
/// Returns the log directory. Must be called once, before anything logs.
pub fn init() -> PathBuf {
    let dir = log_dir();
    if let Err(e) = std::fs::create_dir_all(&dir) {
        eprintln!("dsso-kbf: cannot create log dir {}: {e}", dir.display());
    }

    let appender = tracing_appender::rolling::daily(&dir, "dsso-kbf.log");
    let (writer, guard) = tracing_appender::non_blocking(appender);
    // The guard flushes the writer on drop; the logger lives for the whole
    // process, so leak it instead of threading it through main.
    Box::leak(Box::new(guard));

    let file_layer = tracing_subscriber::fmt::layer()
        .with_writer(writer)
        .with_ansi(false)
        .with_target(false);
    let stderr_layer = tracing_subscriber::fmt::layer()
        .with_writer(std::io::stderr)
        .with_target(false);

    tracing_subscriber::registry()
        .with(file_layer)
        .with(stderr_layer)
        .init();

    dir
}
