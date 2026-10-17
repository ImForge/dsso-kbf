//! Tweak manifest loader + validator, and the bridge that invokes a tweak's
//! four functions through engine/Invoke-Tweak.ps1.

use std::fmt;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::engine::powershell::{self, PowershellError};
use crate::engine::profile::{CpuVendor, FormFactor, GpuVendor, SystemProfile};

pub const REQUIRED_FUNCTIONS: [&str; 4] = ["Detect", "Backup", "Apply", "Revert"];

#[derive(Debug, Error)]
pub enum RegistryError {
    #[error("cannot read {path}: {source}")]
    Io {
        path: String,
        #[source]
        source: std::io::Error,
    },
    #[error("{path}: invalid manifest: {source}")]
    InvalidManifest {
        path: String,
        #[source]
        source: serde_json::Error,
    },
    #[error("{id}: manifest id does not match directory name {dir}")]
    IdMismatch { id: String, dir: String },
    #[error("{id}: risk is {risk} but warning is null — caution/advanced tweaks must warn")]
    MissingWarning { id: String, risk: String },
    #[error("{id}: touches is empty — every tweak must declare what it modifies")]
    EmptyTouches { id: String },
    #[error("{id}: tweak.ps1 is missing")]
    MissingScript { id: String },
    #[error("{id}: tweak.ps1 does not define required function(s): {missing}")]
    MissingFunctions { id: String, missing: String },
    #[error("{id}: a tweak cannot be both list_driven and toggle")]
    ListDrivenAndToggle { id: String },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Impact {
    Low,
    Medium,
    High,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Risk {
    Safe,
    Caution,
    Advanced,
}

impl fmt::Display for Risk {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let s = match self {
            Risk::Safe => "safe",
            Risk::Caution => "caution",
            Risk::Advanced => "advanced",
        };
        f.write_str(s)
    }
}

/// A requires field: a single allowed value or an array of them.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum OneOrMany<T> {
    One(T),
    Many(Vec<T>),
}

impl<T: PartialEq> OneOrMany<T> {
    pub fn contains(&self, v: &T) -> bool {
        match self {
            OneOrMany::One(x) => x == v,
            OneOrMany::Many(xs) => xs.contains(v),
        }
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Requires {
    #[serde(default)]
    pub os_min_build: Option<u32>,
    #[serde(default)]
    pub gpu_vendor: Option<OneOrMany<GpuVendor>>,
    #[serde(default)]
    pub cpu_vendor: Option<OneOrMany<CpuVendor>>,
    #[serde(default)]
    pub form_factor: Option<OneOrMany<FormFactor>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TweakManifest {
    pub id: String,
    pub name: String,
    pub category: String,
    pub description: String,
    pub impact: Impact,
    pub risk: Risk,
    pub requires: Requires,
    pub touches: Vec<String>,
    pub warning: Option<String>,
    /// True for tweaks acting on a per-machine item list the user confirms
    /// individually; such tweaks must define a fifth function, Get-Items.
    #[serde(default)]
    pub list_driven: bool,
    /// True for two-way switches (e.g. HAGS): direction comes from
    /// DSSO_KBF_TARGET and the tweak must define Get-Toggle.
    #[serde(default)]
    pub toggle: bool,
}

#[derive(Debug, Clone)]
pub struct Tweak {
    pub manifest: TweakManifest,
    pub dir: PathBuf,
}

impl Tweak {
    pub fn id(&self) -> &str {
        &self.manifest.id
    }

    pub fn script_path(&self) -> PathBuf {
        self.dir.join("tweak.ps1")
    }

    pub fn is_applicable(&self, p: &SystemProfile) -> bool {
        let r = &self.manifest.requires;
        if let Some(min) = r.os_min_build
            && p.os.build < min
        {
            return false;
        }
        if let Some(cv) = &r.cpu_vendor
            && !cv.contains(&p.cpu.vendor)
        {
            return false;
        }
        if let Some(gv) = &r.gpu_vendor
            && !p.gpu.iter().any(|g| gv.contains(&g.vendor))
        {
            return false;
        }
        if let Some(ff) = &r.form_factor
            && !ff.contains(&p.form_factor)
        {
            return false;
        }
        true
    }
}

pub struct TweakRegistry {
    engine_dir: PathBuf,
    tweaks: Vec<Tweak>,
}

impl TweakRegistry {
    /// Load every tweak under <engine>/tweaks. A tweak that fails validation is
    /// refused (returned as an error) without blocking the valid ones.
    pub fn load(engine_dir: &Path) -> (Self, Vec<RegistryError>) {
        let mut tweaks = Vec::new();
        let mut errors = Vec::new();
        let tweaks_dir = engine_dir.join("tweaks");

        let entries = match std::fs::read_dir(&tweaks_dir) {
            Ok(e) => e,
            Err(source) => {
                errors.push(RegistryError::Io {
                    path: tweaks_dir.display().to_string(),
                    source,
                });
                return (
                    Self {
                        engine_dir: engine_dir.to_path_buf(),
                        tweaks,
                    },
                    errors,
                );
            }
        };

        for entry in entries.flatten() {
            let dir = entry.path();
            if !dir.is_dir() {
                continue;
            }
            match Self::load_one(&dir) {
                Ok(tweak) => tweaks.push(tweak),
                Err(e) => errors.push(e),
            }
        }
        tweaks.sort_by(|a, b| a.manifest.id.cmp(&b.manifest.id));

        for e in &errors {
            tracing::error!("tweak refused: {e}");
        }
        tracing::info!(
            loaded = tweaks.len(),
            refused = errors.len(),
            "tweak registry loaded"
        );

        (
            Self {
                engine_dir: engine_dir.to_path_buf(),
                tweaks,
            },
            errors,
        )
    }

    fn load_one(dir: &Path) -> Result<Tweak, RegistryError> {
        let manifest_path = dir.join("manifest.json");
        let raw = std::fs::read_to_string(&manifest_path).map_err(|source| RegistryError::Io {
            path: manifest_path.display().to_string(),
            source,
        })?;
        let manifest: TweakManifest =
            serde_json::from_str(&raw).map_err(|source| RegistryError::InvalidManifest {
                path: manifest_path.display().to_string(),
                source,
            })?;

        let dir_name = dir
            .file_name()
            .map(|s| s.to_string_lossy().into_owned())
            .unwrap_or_default();
        if manifest.id != dir_name {
            return Err(RegistryError::IdMismatch {
                id: manifest.id,
                dir: dir_name,
            });
        }
        if manifest.risk != Risk::Safe && manifest.warning.is_none() {
            return Err(RegistryError::MissingWarning {
                risk: manifest.risk.to_string(),
                id: manifest.id,
            });
        }
        if manifest.touches.is_empty() {
            return Err(RegistryError::EmptyTouches { id: manifest.id });
        }

        let script = dir.join("tweak.ps1");
        if !script.is_file() {
            return Err(RegistryError::MissingScript { id: manifest.id });
        }
        let body = std::fs::read_to_string(&script).map_err(|source| RegistryError::Io {
            path: script.display().to_string(),
            source,
        })?;
        if manifest.list_driven && manifest.toggle {
            return Err(RegistryError::ListDrivenAndToggle { id: manifest.id });
        }
        let mut required: Vec<&str> = REQUIRED_FUNCTIONS.to_vec();
        if manifest.list_driven {
            required.push("Get-Items");
        }
        if manifest.toggle {
            required.push("Get-Toggle");
        }
        let missing: Vec<&str> = required
            .into_iter()
            .filter(|f| !defines_function(&body, f))
            .collect();
        if !missing.is_empty() {
            return Err(RegistryError::MissingFunctions {
                id: manifest.id,
                missing: missing.join(", "),
            });
        }

        Ok(Tweak {
            manifest,
            dir: dir.to_path_buf(),
        })
    }

    pub fn engine_dir(&self) -> &Path {
        &self.engine_dir
    }

    pub fn all(&self) -> &[Tweak] {
        &self.tweaks
    }

    pub fn get(&self, id: &str) -> Option<&Tweak> {
        self.tweaks.iter().find(|t| t.manifest.id == id)
    }

    pub fn applicable<'a>(&'a self, profile: &SystemProfile) -> Vec<&'a Tweak> {
        self.tweaks
            .iter()
            .filter(|t| t.is_applicable(profile))
            .collect()
    }
}

fn defines_function(body: &str, name: &str) -> bool {
    body.lines().any(|line| {
        let line = line.trim_start();
        line.strip_prefix("function ")
            .map(|rest| {
                let fn_name: String = rest
                    .chars()
                    .take_while(|c| c.is_alphanumeric() || *c == '-' || *c == '_')
                    .collect();
                fn_name == name
            })
            .unwrap_or(false)
    })
}

// ---- invoking the four functions ----------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TweakFunction {
    Detect,
    Backup,
    Apply,
    Revert,
    GetItems,
    GetToggle,
}

impl TweakFunction {
    fn as_str(self) -> &'static str {
        match self {
            TweakFunction::Detect => "Detect",
            TweakFunction::Backup => "Backup",
            TweakFunction::Apply => "Apply",
            TweakFunction::Revert => "Revert",
            TweakFunction::GetItems => "Get-Items",
            TweakFunction::GetToggle => "Get-Toggle",
        }
    }
}

/// What a toggle tweak's Get-Toggle returns.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToggleInfo {
    pub current: String,
    pub recommended: String,
    pub reason: String,
}

/// One entry of a list-driven tweak's Get-Items output.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TweakItem {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub detail: Option<String>,
    pub active: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum DetectState {
    Applied,
    NotApplied,
    Partial,
    Unknown,
}

impl fmt::Display for DetectState {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let s = match self {
            DetectState::Applied => "applied",
            DetectState::NotApplied => "not-applied",
            DetectState::Partial => "partial",
            DetectState::Unknown => "unknown",
        };
        f.write_str(s)
    }
}

/// What Invoke-Tweak.ps1 prints: { ok, value?, error? }.
#[derive(Debug, Deserialize)]
pub struct FunctionOutput {
    pub ok: bool,
    #[serde(default)]
    pub value: serde_json::Value,
    #[serde(default)]
    pub error: Option<String>,
}

#[derive(Debug, Error)]
pub enum InvokeError {
    #[error(transparent)]
    Powershell(#[from] PowershellError),
    #[error("{id}/{function} failed: {message}")]
    TweakFailed {
        id: String,
        function: &'static str,
        message: String,
    },
}

/// Optional arguments for Invoke-Tweak.ps1. items and target are mutually
/// exclusive in practice (list-driven vs toggle tweaks).
#[derive(Default)]
pub struct InvokeOpts<'a> {
    pub backup_dir: Option<&'a Path>,
    pub items: Option<&'a str>,
    pub target: Option<&'a str>,
}

pub fn invoke(
    engine_dir: &Path,
    tweak: &Tweak,
    function: TweakFunction,
    opts: &InvokeOpts<'_>,
) -> Result<serde_json::Value, InvokeError> {
    let script = engine_dir.join("Invoke-Tweak.ps1");
    let tweak_path = tweak.script_path().display().to_string();
    let mut args: Vec<String> = vec![
        "-TweakPath".into(),
        tweak_path,
        "-Function".into(),
        function.as_str().into(),
    ];
    if let Some(dir) = opts.backup_dir {
        args.push("-BackupDir".into());
        args.push(dir.display().to_string());
    }
    if let Some(items) = opts.items {
        args.push("-Items".into());
        args.push(items.to_string());
    }
    if let Some(target) = opts.target {
        args.push("-Target".into());
        args.push(target.to_string());
    }
    let arg_refs: Vec<&str> = args.iter().map(String::as_str).collect();
    let out: FunctionOutput = powershell::run_script_json(&script, &arg_refs)?;
    if !out.ok {
        return Err(InvokeError::TweakFailed {
            id: tweak.manifest.id.clone(),
            function: function.as_str(),
            message: out.error.unwrap_or_else(|| "unknown error".into()),
        });
    }
    Ok(out.value)
}

pub fn detect(
    engine_dir: &Path,
    tweak: &Tweak,
    opts: &InvokeOpts<'_>,
) -> Result<DetectState, InvokeError> {
    let value = invoke(engine_dir, tweak, TweakFunction::Detect, opts)?;
    let state = match value.as_str() {
        Some("applied") => DetectState::Applied,
        Some("not-applied") => DetectState::NotApplied,
        Some("partial") => DetectState::Partial,
        _ => DetectState::Unknown,
    };
    Ok(state)
}

/// Run a toggle tweak's Get-Toggle.
pub fn get_toggle(engine_dir: &Path, tweak: &Tweak) -> Result<ToggleInfo, InvokeError> {
    let value = invoke(
        engine_dir,
        tweak,
        TweakFunction::GetToggle,
        &InvokeOpts::default(),
    )?;
    serde_json::from_value(value).map_err(|e| InvokeError::TweakFailed {
        id: tweak.manifest.id.clone(),
        function: "Get-Toggle",
        message: format!("invalid Get-Toggle output: {e}"),
    })
}

/// Run a list-driven tweak's Get-Items. PowerShell unwraps single-element
/// arrays at function boundaries, so a lone object is normalised back into a
/// one-element list.
pub fn get_items(engine_dir: &Path, tweak: &Tweak) -> Result<Vec<TweakItem>, InvokeError> {
    let value = invoke(
        engine_dir,
        tweak,
        TweakFunction::GetItems,
        &InvokeOpts::default(),
    )?;
    let raw = match value {
        serde_json::Value::Array(a) => a,
        serde_json::Value::Null => Vec::new(),
        one => vec![one],
    };
    let items = raw
        .into_iter()
        .filter_map(|v| serde_json::from_value(v).ok())
        .collect();
    Ok(items)
}

/// A default profile definition from engine/profiles/<name>.json.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ProfileDef {
    pub name: String,
    pub tiers: Vec<String>,
    pub tweaks: Vec<String>,
}

impl TweakRegistry {
    pub fn load_profile_def(&self, name: &str) -> Option<Result<ProfileDef, String>> {
        let path = self
            .engine_dir
            .join("profiles")
            .join(format!("{name}.json"));
        if !path.is_file() {
            return None;
        }
        let load = std::fs::read_to_string(&path)
            .map_err(|e| format!("cannot read {}: {e}", path.display()))
            .and_then(|raw| {
                serde_json::from_str(&raw)
                    .map_err(|e| format!("invalid profile {}: {e}", path.display()))
            });
        Some(load)
    }
}

/// Normalise a Backup return value (one path or an array of paths).
pub fn value_as_strings(v: &serde_json::Value) -> Vec<String> {
    match v {
        serde_json::Value::String(s) => vec![s.clone()],
        serde_json::Value::Array(a) => a
            .iter()
            .filter_map(|x| x.as_str().map(str::to_owned))
            .collect(),
        _ => Vec::new(),
    }
}

/// True when an Apply return value asked for a reboot ({ requiresReboot: true }).
pub fn value_requires_reboot(v: &serde_json::Value) -> bool {
    v.get("requiresReboot")
        .and_then(serde_json::Value::as_bool)
        .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::engine::profile::SystemProfile;

    fn repo_engine_dir() -> PathBuf {
        PathBuf::from(concat!(env!("CARGO_MANIFEST_DIR"), "/../engine"))
    }

    fn fixture(name: &str) -> SystemProfile {
        let path = format!("{}/../tests/fixtures/{name}", env!("CARGO_MANIFEST_DIR"));
        let raw = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{path}: {e}"));
        serde_json::from_str(&raw).unwrap_or_else(|e| panic!("{path}: {e}"))
    }

    #[test]
    fn real_engine_tweaks_all_load() {
        let (reg, errors) = TweakRegistry::load(&repo_engine_dir());
        assert!(errors.is_empty(), "refused tweaks: {errors:?}");
        assert_eq!(reg.all().len(), 14);
        assert!(reg.get("disable-game-dvr").is_some());
        let startup = reg.get("disable-startup-bloat").expect("startup tweak");
        assert!(startup.manifest.list_driven);
        let hags = reg.get("toggle-hags").expect("hags tweak");
        assert!(hags.manifest.toggle);
        assert_eq!(hags.manifest.risk, Risk::Caution);
        let vbs = reg.get("disable-vbs-hvci").expect("vbs tweak");
        assert_eq!(vbs.manifest.risk, Risk::Advanced);
        assert!(vbs.manifest.warning.is_some());
    }

    #[test]
    fn toggle_without_get_toggle_is_refused() {
        let dir = std::env::temp_dir()
            .join("dsso-kbf-test-manifest")
            .join("bad-toggle-tweak");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("mkdir");
        std::fs::write(
            dir.join("manifest.json"),
            r#"{
              "id": "bad-toggle-tweak", "name": "x", "category": "x", "description": "x",
              "impact": "low", "risk": "caution", "toggle": true,
              "requires": { "os_min_build": null, "gpu_vendor": null, "cpu_vendor": null, "form_factor": null },
              "touches": ["HKLM\\X"], "warning": "w"
            }"#,
        )
        .expect("write manifest");
        std::fs::write(
            dir.join("tweak.ps1"),
            "function Detect {}\nfunction Backup {}\nfunction Apply {}\nfunction Revert {}\n",
        )
        .expect("write script");

        let err = TweakRegistry::load_one(&dir).expect_err("must refuse");
        match err {
            RegistryError::MissingFunctions { missing, .. } => {
                assert!(missing.contains("Get-Toggle"), "{missing}");
            }
            other => panic!("wrong error: {other}"),
        }
    }

    #[test]
    fn default_profiles_load_and_name_known_tweaks() {
        let (reg, _) = TweakRegistry::load(&repo_engine_dir());
        for name in ["safe", "balanced", "aggressive"] {
            let def = reg
                .load_profile_def(name)
                .unwrap_or_else(|| panic!("{name}.json missing"))
                .unwrap_or_else(|e| panic!("{name}: {e}"));
            assert!(!def.tweaks.is_empty());
            for id in &def.tweaks {
                assert!(
                    reg.get(id).is_some(),
                    "profile {name} names unknown tweak {id}"
                );
            }
        }
    }

    #[test]
    fn list_driven_without_get_items_is_refused() {
        let dir = std::env::temp_dir()
            .join("dsso-kbf-test-manifest")
            .join("bad-list-tweak");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("mkdir");
        std::fs::write(
            dir.join("manifest.json"),
            r#"{
              "id": "bad-list-tweak", "name": "x", "category": "x", "description": "x",
              "impact": "low", "risk": "safe", "list_driven": true,
              "requires": { "os_min_build": null, "gpu_vendor": null, "cpu_vendor": null, "form_factor": null },
              "touches": ["HKCU\\X"], "warning": null
            }"#,
        )
        .expect("write manifest");
        std::fs::write(
            dir.join("tweak.ps1"),
            "function Detect {}\nfunction Backup {}\nfunction Apply {}\nfunction Revert {}\n",
        )
        .expect("write script");

        let err = TweakRegistry::load_one(&dir).expect_err("must refuse");
        match err {
            RegistryError::MissingFunctions { missing, .. } => {
                assert!(missing.contains("Get-Items"), "{missing}");
            }
            other => panic!("wrong error: {other}"),
        }
    }

    #[test]
    fn filtering_respects_form_factor() {
        let (reg, _) = TweakRegistry::load(&repo_engine_dir());
        let laptop = fixture("nvidia-laptop.json");
        let desktop = fixture("amd-desktop.json");

        let laptop_ids: Vec<&str> = reg.applicable(&laptop).iter().map(|t| t.id()).collect();
        assert!(laptop_ids.contains(&"power-plan-balanced-tuned"));
        assert!(!laptop_ids.contains(&"power-plan-high-performance"));

        let desktop_ids: Vec<&str> = reg.applicable(&desktop).iter().map(|t| t.id()).collect();
        assert!(desktop_ids.contains(&"power-plan-high-performance"));
        assert!(!desktop_ids.contains(&"power-plan-balanced-tuned"));
    }

    #[test]
    fn caution_without_warning_is_refused() {
        let dir = std::env::temp_dir()
            .join("dsso-kbf-test-manifest")
            .join("bad-tweak");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("mkdir");
        std::fs::write(
            dir.join("manifest.json"),
            r#"{
              "id": "bad-tweak", "name": "x", "category": "x", "description": "x",
              "impact": "low", "risk": "caution",
              "requires": { "os_min_build": null, "gpu_vendor": null, "cpu_vendor": null, "form_factor": null },
              "touches": ["HKCU\\X"], "warning": null
            }"#,
        )
        .expect("write manifest");
        std::fs::write(
            dir.join("tweak.ps1"),
            "function Detect {}\nfunction Backup {}\nfunction Apply {}\nfunction Revert {}\n",
        )
        .expect("write script");

        let err = TweakRegistry::load_one(&dir).expect_err("must refuse");
        assert!(matches!(err, RegistryError::MissingWarning { .. }), "{err}");
    }

    #[test]
    fn missing_function_is_refused() {
        let body = "function Detect {}\nfunction Backup {}\nfunction Apply {}\n";
        assert!(defines_function(body, "Detect"));
        assert!(!defines_function(body, "Revert"));
        // Substring traps: 'function Detects' is not 'Detect'.
        assert!(!defines_function("function Detects {}", "Detect"));
    }

    #[test]
    fn requires_accepts_single_value_and_array() {
        let single: Requires =
            serde_json::from_str(r#"{ "gpu_vendor": "nvidia" }"#).expect("single");
        let many: Requires =
            serde_json::from_str(r#"{ "gpu_vendor": ["nvidia", "amd"] }"#).expect("array");
        let gv_single = single.gpu_vendor.expect("some");
        let gv_many = many.gpu_vendor.expect("some");
        assert!(gv_single.contains(&GpuVendor::Nvidia));
        assert!(!gv_single.contains(&GpuVendor::Amd));
        assert!(gv_many.contains(&GpuVendor::Amd));
        assert!(!gv_many.contains(&GpuVendor::Intel));
    }
}
