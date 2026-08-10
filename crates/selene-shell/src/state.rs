/// Hyprland state snapshot/restore -- save and reload compositor options.
//
/// The `State` QObject reads Hyprland options (animations, gaps,
/// border, rounding, VRR) via `hyprctl getoption`, saves them to
/// state.json, and restores via `hyprctl keyword`. game_mode() and
/// focus_mode() presets are one-click toggles.

use core::pin::Pin;
use cxx_qt_lib::QString;
use std::process::Command;

/// Hyprland state snapshot/restore (Ambxst game/focus mode).
#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(QString, status)]
        #[qproperty(bool, saved)]
        type State = super::StateRust;

        #[qinvokable]
        fn snapshot(self: Pin<&mut Self>);

        #[qinvokable]
        fn restore(self: Pin<&mut Self>);

        #[qinvokable]
        fn game_mode(self: Pin<&mut Self>);

        #[qinvokable]
        fn focus_mode(self: Pin<&mut Self>);

        #[qinvokable]
        fn clear(self: Pin<&mut Self>);
    }
}

#[derive(Default)]
pub struct StateRust {
    status: QString,
    saved: bool,
}

const OPTIONS: &[&str] = &[
    "animations:enabled",
    "general:border_size",
    "general:gaps_in",
    "general:gaps_out",
    "decoration:rounding",
    "misc:vrr",
    "misc:disable_autoreload",
];

fn get_option(name: &str) -> Option<String> {
    let out = Command::new("hyprctl")
        .args(["getoption", name])
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let stdout = String::from_utf8_lossy(&out.stdout);
    // Output is e.g. "int: 1\nset: true\n" or "bool: true\nset: true\n"
    for line in stdout.lines() {
        let stripped = line.trim();
        if !stripped.starts_with("set:") {
            return Some(stripped.to_string());
        }
    }
    None
}

fn set_option(name: &str, value: &str) {
    let mut parts = name.splitn(2, ':');
    let (category, sub) = (parts.next().unwrap_or(""), parts.next().unwrap_or(""));
    // hyprctl keyword <category>:<sub> <value>
    let _ = Command::new("hyprctl")
        .args(["keyword", &format!("{category}:{sub}"), value])
        .output();
}

fn storage_path() -> std::path::PathBuf {
    let home = std::env::var_os("HOME")
        .map(|h| h.to_string_lossy().to_string())
        .unwrap_or_else(|| "/tmp".to_string());
    std::path::PathBuf::from(format!("{home}/.local/share/selene/state.json"))
}

fn save_json(options: &[(String, String)]) {
    let mut json = String::from("{");
    for (i, (k, v)) in options.iter().enumerate() {
        if i > 0 {
            json.push(',');
        }
        json.push_str(&format!("\"{k}\":\"{v}\""));
    }
    json.push('}');
    let path = storage_path();
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let _ = std::fs::write(&path, &json);
}

fn read_snapshot() -> Option<Vec<(String, String)>> {
    let path = storage_path();
    let text = std::fs::read_to_string(&path).ok()?;
    let raw: serde_json::Value = serde_json::from_str(&text).ok()?;
    let obj = raw.as_object()?;
    let mut out = Vec::new();
    for (k, v) in obj {
        if let Some(s) = v.as_str() {
            out.push((k.clone(), s.to_string()));
        }
    }
    Some(out)
}

impl qobject::State {
    pub fn snapshot(self: Pin<&mut Self>) {
        let mut saved: Vec<(String, String)> = Vec::new();
        for name in OPTIONS {
            if let Some(val) = get_option(name) {
                saved.push((name.to_string(), val));
            }
        }
        let mut this = self;
        if saved.is_empty() {
            this.as_mut()
                .set_status(QString::from("no Hyprland connection"));
            return;
        }
        save_json(&saved);
        this.as_mut().set_saved(true);
        this.as_mut()
            .set_status(QString::from(format!("saved {} options", saved.len())));
    }

    pub fn restore(self: Pin<&mut Self>) {
        let sn = match read_snapshot() {
            Some(s) => s,
            None => {
                let mut this = self;
                this.as_mut().set_status(QString::from("no snapshot to restore"));
                return;
            }
        };
        for (name, value) in &sn {
            set_option(name, value);
        }
        let mut this = self;
        this.as_mut().set_saved(true);
        this.as_mut().set_status(QString::from(format!("restored {} options", sn.len())));
    }

    pub fn game_mode(self: Pin<&mut Self>) {
        // Save current state, then apply performance/gaming presets.
        let mut saved: Vec<(String, String)> = Vec::new();
        for name in OPTIONS {
            if let Some(val) = get_option(name) {
                saved.push((name.to_string(), val));
            }
        }
        let mut this = self;
        if !saved.is_empty() {
            save_json(&saved);
            this.as_mut().set_saved(true);
        }
        set_option("animations:enabled", "false");
        set_option("general:gaps_in", "0");
        set_option("general:gaps_out", "0");
        set_option("misc:vrr", "true");
        this.as_mut()
            .set_status(QString::from("game mode on (snapshot saved)"));
    }

    pub fn focus_mode(self: Pin<&mut Self>) {
        // Focus mode: silent. Save + disable distractions.
        let mut saved: Vec<(String, String)> = Vec::new();
        for name in OPTIONS {
            if let Some(val) = get_option(name) {
                saved.push((name.to_string(), val));
            }
        }
        let mut this = self;
        if !saved.is_empty() {
            save_json(&saved);
            this.as_mut().set_saved(true);
        }
        set_option("animations:enabled", "false");
        this.as_mut()
            .set_status(QString::from("focus mode on (animations off)"));
    }

    pub fn clear(self: Pin<&mut Self>) {
        let path = storage_path();
        let _ = std::fs::remove_file(&path);
        let mut this = self;
        this.as_mut().set_saved(false);
        this.as_mut().set_status(QString::from("cleared"));
    }
}
