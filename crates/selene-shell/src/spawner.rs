/// App launcher -- .desktop enumeration and process spawning.
//
/// The `Spawner` QObject walks /usr/share/applications and
/// ~/.local/share/applications, parses .desktop files, expands field
/// codes, applies TryExec preflights, and spawns via setsid --fork.
/// Launcher ranking by usage frequency is persisted to
/// launcher-stats.json. The QML side (`Launcher.qml`) provides a
/// Hax-style fuzzy search with \@/>/=/?/: prefixes and calls
/// copy_to_clipboard / open_url for the non-app actions.

use core::pin::Pin;
use cxx_qt_lib::QString;
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{Mutex, OnceLock};

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
        #[qproperty(QString, stats_json)]
        type Spawner = super::SpawnerRust;

        #[qinvokable]
        fn refresh(self: Pin<&mut Self>);

        #[qinvokable]
        fn launch(self: Pin<&mut Self>, exec: &QString) -> i32;

        #[qinvokable]
        fn run_action(self: Pin<&mut Self>, action_label: &QString) -> i32;

        #[qinvokable]
        fn record_launch(self: Pin<&mut Self>, label: &QString);

        #[qinvokable]
        fn open_url(self: Pin<&mut Self>, url: &QString) -> i32;

        #[qinvokable]
        fn copy_to_clipboard(self: Pin<&mut Self>, text: &QString) -> i32;

        #[qinvokable]
        fn stats_path(&self) -> QString;
    }

    impl cxx_qt::Threading for Spawner {}
}

#[derive(Default)]
pub struct SpawnerRust {
    apps_json: QString,
    actions_json: QString,
    search_paths: QString,
    app_count: i32,
    stats_json: QString,
}

struct DesktopEntry {
    name: String,
    exec: String,
    icon: String,
    nodisplay: bool,
    terminal: bool,
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
        let mut apps = enumerate_apps(&default_search_paths_borrowed());
        let stats = stats_load();
        // Sort by usage (desc) then alphabetical. New / unused apps float to
        // the bottom; the QML launcher can still filter, this just biases
        // the default ordering.
        apps.sort_by(|a, b| {
            let wa = stats.get(&a.name).copied().unwrap_or(0);
            let wb = stats.get(&b.name).copied().unwrap_or(0);
            wb.cmp(&wa).then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
        });
        let apps_count = apps.len();
        let apps_json = apps_to_json(&apps, &stats);
        let actions_json = actions_to_json();
        let stats_json = stats_to_json(&stats);

        let mut this = self;
        this.as_mut()
            .set_apps_json(QString::from(apps_json.as_str()));
        this.as_mut()
            .set_actions_json(QString::from(actions_json.as_str()));
        this.as_mut()
            .set_search_paths(QString::from(default_search_paths().join("\n").as_str()));
        this.as_mut().set_app_count(apps_count as i32);
        this.as_mut()
            .set_stats_json(QString::from(stats_json.as_str()));
        // seed the in-memory tracker so record_launch can update without
        // re-reading the file
        if let Ok(mut shared) = stats_shared().lock() {
            *shared = stats;
        }
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

    pub fn record_launch(self: Pin<&mut Self>, label: &QString) {
        let label = label.to_string();
        if label.is_empty() {
            return;
        }
        let Ok(mut shared) = stats_shared().lock() else {
            return;
        };
        let entry = shared.entry(label).or_insert(0);
        *entry = entry.saturating_add(1);
        stats_save(&shared);
        let new_json = stats_to_json(&shared);
        let mut this = self;
        this.as_mut()
            .set_stats_json(QString::from(new_json.as_str()));
    }

    pub fn open_url(self: Pin<&mut Self>, url: &QString) -> i32 {
        let url = url.to_string();
        // Allow only http(s) and file URIs; reject anything that could be
        // a shell injection (e.g. `xdg-open file:///etc` is fine, but
        // `data-text/html` are not). xdg-open will refuse untrusted URIs.
        let trimmed = url.trim();
        if !(trimmed.starts_with("http://")
            || trimmed.starts_with("https://")
            || trimmed.starts_with("file://"))
        {
            return -1;
        }
        spawn_command_owned(&format!("xdg-open '{trimmed}'"))
    }

    pub fn copy_to_clipboard(self: Pin<&mut Self>, text: &QString) -> i32 {
        let text = text.to_string();
        // Try the Wayland tool first, then X11's, then fall back to
        // xsel. The first hit wins; failures are silent.

        let Some(home) = std::env::var_os("HOME") else {
            return -1;
        };
        let home = home.to_string_lossy().to_string();
        let staging = format!("{home}/.local/share/selene/clipboard.txt");
        if let Some(parent) = std::path::Path::new(&staging).parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        if std::fs::write(&staging, &text).is_err() {
            return -1;
        }

        // wl-copy is the canonical Wayland tool; falls back to xclip on
        // X11 / xsel as a last resort. We don't shell-quote `text` --
        // the file path is the argument, not the contents.
        for cmd in &["wl-copy", "xclip", "xsel"] {
            let argv: Vec<&str> = match *cmd {
                "wl-copy" => vec!["wl-copy", "--type", "text/plain", "<", staging.as_str()],
                "xclip" => vec!["xclip", "-selection", "clipboard", staging.as_str()],
                "xsel" => vec!["xsel", "--clipboard", "--input", staging.as_str()],
                _ => continue,
            };
            if let Some((first, rest)) = argv.split_first() {
                let attempt = Command::new(first)
                    .args(rest)
                    .stdin(Stdio::null())
                    .stdout(Stdio::null())
                    .stderr(Stdio::null())
                    .spawn();
                if attempt.is_ok() {
                    return 0;
                }
            }
        }
        -1
    }

    pub fn stats_path(&self) -> QString {
        QString::from(stats_path().to_string_lossy().as_ref())
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

fn stats_path() -> PathBuf {
    let home = std::env::var_os("HOME")
        .map(|h| PathBuf::from(h))
        .unwrap_or_else(|| PathBuf::from("/"));
    home.join(".local/share/selene/launcher-stats.json")
}

fn stats_load() -> HashMap<String, u64> {
    let path = stats_path();
    fs::read_to_string(&path)
        .ok()
        .and_then(|s| serde_json::from_str::<HashMap<String, u64>>(&s).ok())
        .unwrap_or_default()
}

fn stats_save(stats: &HashMap<String, u64>) {
    let path = stats_path();
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    if let Ok(s) = serde_json::to_string_pretty(stats) {
        let _ = fs::write(&path, s);
    }
}

fn stats_shared() -> &'static Mutex<HashMap<String, u64>> {
    static STATS: OnceLock<Mutex<HashMap<String, u64>>> = OnceLock::new();
    STATS.get_or_init(|| Mutex::new(stats_load()))
}

fn stats_to_json(stats: &HashMap<String, u64>) -> String {
    serde_json::to_string(stats).unwrap_or_else(|_| "{}".to_string())
}

fn apps_to_json(apps: &[DesktopEntry], stats: &HashMap<String, u64>) -> String {
    let mut out = String::from("[");
    for (i, entry) in apps.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        let weight = stats.get(&entry.name).copied().unwrap_or(0);
        out.push_str(&json_escape(&format!(
            r#"{{"label":"{}","exec":"{}","icon":"{}","terminal":{},"weight":{}}}"#,
            entry.name,
            entry.exec,
            entry.icon,
            if entry.terminal { "true" } else { "false" },
            weight
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
    let mut icon = String::new();
    let mut nodisplay = false;
    let mut terminal = false;
    let mut try_exec: Option<String> = None;

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
            exec = Some(expand_field_codes(v));
        } else if let Some(v) = line.strip_prefix("Icon=") {
            icon = v.to_string();
        } else if let Some(v) = line.strip_prefix("NoDisplay=") {
            nodisplay = v.trim().eq_ignore_ascii_case("true");
        } else if let Some(v) = line.strip_prefix("Terminal=") {
            terminal = v.trim().eq_ignore_ascii_case("true");
        } else if let Some(v) = line.strip_prefix("TryExec=") {
            try_exec = Some(v.trim().to_string());
        }
    }

    // TryExec preflight: skip the entry when the named binary isn't resolvable
    // on PATH (the .desktop spec says launchers MUST NOT show the entry).
    if let Some(bin) = try_exec {
        if !binary_on_path(&bin) {
            return None;
        }
    }

    Some(DesktopEntry {
        name: name?,
        exec: exec?,
        icon,
        nodisplay,
        terminal,
    })
}

fn binary_on_path(bin: &str) -> bool {
    if bin.contains('/') {
        return Path::new(bin).exists();
    }
    let Some(path_var) = std::env::var_os("PATH") else {
        return false;
    };
    for dir in std::env::split_paths(&path_var) {
        if dir.join(bin).exists() {
            return true;
        }
    }
    false
}

/// Expand freedesktop .desktop field codes. Spec:
/// https://specifications.freedesktop.org/desktop-entry-spec/latest/ar01s07.html
/// We launch without file arguments, so %f/%F/%u/%U drop out entirely.
/// %i expands to the icon (left empty here), %c to the (translated) name,
/// %k to the desktop file location (left empty), %% is a literal percent.
fn expand_field_codes(raw: &str) -> String {
    let mut out = String::with_capacity(raw.len());
    let mut chars = raw.chars().peekable();
    while let Some(c) = chars.next() {
        if c != '%' {
            out.push(c);
            continue;
        }
        match chars.next() {
            Some('%') => out.push('%'),
            Some('f') | Some('F') | Some('u') | Some('U') => {
                // File/URL placeholders -- we don't pass files, drop them
                // (and a following space if the token was "%u " style).
            }
            Some('i') | Some('c') | Some('k') => {
                // Icon / name / location -- safe to drop for our launcher.
            }
            Some(other) => {
                // Deprecated codes (%d %D %n %N %v %m) -- drop silently.
                // Unknown codes: also drop, spec says they're reserved.
                let _ = other;
            }
            None => {
                // Trailing lone %, keep as-is.
                out.push('%');
            }
        }
    }
    // Collapse whitespace left behind by dropped tokens.
    out.split_whitespace().collect::<Vec<_>>().join(" ")
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
    // setsid: detach the child into its own session so it outlives the shell
    // process and doesn't receive our signal group. Mirrors what every
    // production launcher (rofi, fuzzel, walker) does.
    match Command::new("setsid")
        .arg("--fork")
        .arg(first)
        .args(rest)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
    {
        Ok(child) => child.id() as i32,
        Err(_) => {
            // setsid missing (unlikely on util-linux systems); fall back to a
            // plain spawn so the launcher still works.
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
    }
}
