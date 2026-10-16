fn main() {
    // tauri-build embeds a Windows manifest itself; supplying ours through
    // WindowsAttributes is the only way to get requireAdministrator without
    // a duplicate RT_MANIFEST resource (see CLAUDE.md, Stack > Admin).
    let windows = tauri_build::WindowsAttributes::new()
        .app_manifest(include_str!("windows-app-manifest.xml"));
    tauri_build::try_build(tauri_build::Attributes::new().windows_attributes(windows))
        .expect("failed to run tauri-build");
}
