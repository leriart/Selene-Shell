use core::pin::Pin;
use cxx_qt::Threading;
use cxx_qt_lib::QString;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(QString, apps_json)]
        #[qproperty(QString, actions_json)]
        #[qproperty(QString, search_paths)]
        #[qproperty(i32, app_count)]
        type Spawner = super::SpawnerRust;

        #[qinvokable]
        fn refresh(self: Pin<&mut Self>);

        #[qinvokable]
        fn launch(self: Pin<&mut Self>, exec: &QString) -> i32;

        #[qinvokable]
        fn run_action(self: Pin<&mut Self>, action_label: &QString) -> i32;
    }

    impl cxx_qt::Threading for Spawner {}
}

#[derive(Default)]
pub struct SpawnerRust {
    apps_json: QString,
    actions_json: QString,
    search_paths: QString,
    app_count: i32,
}

struct DesktopEntry {
    name: String,
    exec: String,
    nodisplay: bool,
}

struct BuiltinAction {
    label: &'static str,
    command: &'static str,
    args: &'static [&'static str],
}

const BUILTIN_ACTIONS: &[BuiltinAction] = &[
    BuiltinAction {
        label: "Lock screen",
        command: "loginctl",
        args: &["lock-session"],
    },
    BuiltinAction {
        label: "Suspend",
        command: "systemctl",
        args: &["suspend"],
    },
    BuiltinAction {
        label: "Reload selene",
        command: "selene",
        args: &["reload"],
    },
    BuiltinAction {
        label: "Quit selene",
        command: "selene",
        args: &["quit"],
    },
    BuiltinAction {
        label: "Open settings",
        command: "selene",
        args: &["run", "settings"],
    },
    BuiltinAction {
        label: "Screenshot region",
        command: "grim",
        args: &["-g"],
    },
    BuiltinAction {
        label: "Color picker",
        command: "hyprpicker",
        args: &["-a"],
    },
];

impl qobject::Spawner {
    pub fn refresh(self: Pin<&mut Self>) {
        let apps = enumerate_apps(&default_search_paths_borrowed());
        let apps_count = apps.len();
        let apps_json = apps_to_json(&apps);
        let actions_json = actions_to_json();

        let mut this = self;
        this.as_mut()
            .set_apps_json(QString::from(apps_json.as_str()));
        this.as_mut()
            .set_actions_json(QString::from(actions_json.as_str()));
        this.as_mut()
            .set_search_paths(QString::from(default_search_paths().join("\n").as_str()));
        this.as_mut().set_app_count(apps_count as i32);
    }

    pub fn launch(self: Pin<&mut Self>, exec: &QString) -> i32 {
        spawn_command(exec)
    }

    pub fn run_action(self: Pin<&mut Self>, action_label: &QString) -> i32 {
        let needle = action_label.to_string();
        let Some(action) = BUILTIN_ACTIONS.iter().find(|a| a.label == needle) else {
            return -1;
        };
        let mut full = action.command.to_owned();
        for arg in action.args.iter() {
            full.push(' ');
            full.push_str(arg);
        }
        spawn_command_owned(&full)
    }
}

fn default_search_paths() -> Vec<String> {
    let mut out = vec![
        "/usr/share/applications".to_string(),
        "/usr/local/share/applications".to_string(),
    ];
    if let Some(home) = std::env::var_os("HOME") {
        let home = home.to_string_lossy().to_string();
        out.push(format!("{home}/.local/share/applications"));
        out.push(format!("{home}/.local/share/flatpak/exports/share/applications"));
    }
    out
}

fn default_search_paths_borrowed() -> Vec<PathBuf> {
    default_search_paths().into_iter().map(PathBuf::from).collect()
}

fn apps_to_json(apps: &[DesktopEntry]) -> String {
    let mut out = String::from("[");
    for (i, entry) in apps.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        out.push_str(&json_escape(&format!(
            "{{\"label\":\"{}\",\"exec\":\"{}\"}}",
            entry.name, entry.exec
        )));
    }
    out.push(']');
    out
}

fn actions_to_json() -> String {
    let mut out = String::from("[");
    for (i, action) in BUILTIN_ACTIONS.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        let mut exec = action.command.to_owned();
        for arg in action.args.iter() {
            exec.push(' ');
            exec.push_str(arg);
        }
        out.push_str(&format!(
            "{{\"label\":{},\"exec\":{}}}",
            json_escape_as_string(action.label),
            json_escape_as_string(&exec)
        ));
    }
    out.push(']');
    out
}

fn json_escape(s: &str) -> String {
    s.chars()
        .flat_map(|c| match c {
            '"' => vec!['\\', '"'],
            '\\' => vec!['\\', '\\'],
            '\n' => vec!['\\', 'n'],
            '\r' => vec!['\\', 'r'],
            '\t' => vec!['\\', 't'],
            other => vec![other],
        })
        .collect()
}

fn json_escape_as_string(s: &str) -> String {
    format!("\"{}\"", json_escape(s))
}

fn enumerate_apps(roots: &[PathBuf]) -> Vec<DesktopEntry> {
    let mut out: Vec<DesktopEntry> = Vec::new();
    let mut seen = std::collections::HashSet::new();

    for root in roots {
        if !root.exists() {
            continue;
        }
        walk_desktop_dir(root, &mut |entry: DesktopEntry| {
            if entry.nodisplay {
                return;
            }
            if seen.insert(entry.name.clone()) {
                out.push(entry);
            }
        });
    }

    out.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
    out
}

fn walk_desktop_dir<F: FnMut(DesktopEntry)>(dir: &Path, cb: &mut F) {
    let Ok(read) = fs::read_dir(dir) else {
        return;
    };
    for entry in read.flatten() {
        let path = entry.path();
        if path.is_dir() {
            walk_desktop_dir(&path, cb);
        } else if path.extension().and_then(|s| s.to_str()) == Some("desktop") {
            if let Some(parsed) = parse_desktop(&path) {
                cb(parsed);
            }
        }
    }
}

fn parse_desktop(path: &Path) -> Option<DesktopEntry> {
    let content = fs::read_to_string(path).ok()?;
    let mut in_entry = false;
    let mut name = None;
    let mut exec = None;
    let mut nodisplay = false;

    for raw in content.lines() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if line.starts_with('[') {
            in_entry = line == "[Desktop Entry]";
            continue;
        }
        if !in_entry {
            continue;
        }
        if let Some(v) = line.strip_prefix("Name=") {
            if name.is_none() {
                name = Some(v.to_string());
            }
        } else if let Some(v) = line.strip_prefix("Exec=") {
            exec = Some(clean_exec(v));
        } else if let Some(v) = line.strip_prefix("NoDisplay=") {
            nodisplay = v.trim().eq_ignore_ascii_case("true");
        }
    }

    Some(DesktopEntry {
        name: name?,
        exec: exec?,
        nodisplay,
    })
}

fn clean_exec(raw: &str) -> String {
    let mut cleaned = String::new();
    let mut first = true;
    for token in raw.split_whitespace() {
        if token.starts_with('%') {
            continue;
        }
        if !first {
            cleaned.push(' ');
        }
        cleaned.push_str(token);
        first = false;
    }
    cleaned
}

fn spawn_command(exec: &QString) -> i32 {
    spawn_command_owned(&exec.to_string())
}

fn spawn_command_owned(exec: &str) -> i32 {
    if exec.is_empty() {
        return -1;
    }
    let parts: Vec<&str> = exec.split_whitespace().collect();
    let Some((first, rest)) = parts.split_first() else {
        return -1;
    };
    match Command::new(first)
        .args(rest)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
    {
        Ok(child) => child.id() as i32,
        Err(_) => -1,
    }
}
