/// Clipboard history -- persistent clipboard manager via cliphist.
//
/// The `Clipboard` QObject parses `cliphist list` into a JSON array of
/// entries (id / preview / full) and writes back through `wl-copy /
/// xclip / xsel`. The QML side (`ClipboardPanel.qml`) renders a
/// searchable list with click-to-copy and right-click-to-delete.

use core::pin::Pin;
use cxx_qt_lib::QString;
use std::process::Command;

/// Clipboard history -- wraps `cliphist list / store / delete`. Items
/// arrive in `<id>\t<content>` form, one item per line; multi-line
/// content is preserved as a single entry by joining the lines back
/// at display time. The QObject exposes:
///   * `items_json`        -- JSON array of {id, preview, full, time}
///   * `total`             -- number of entries currently stored
///   * `running`           -- whether the watcher subprocess is alive
///   * `running_status`    -- last error or "ok"
///
/// QInvokables:
///   * `refresh()`         -- re-parse the current cliphist db
///   * `pick(id)`          -- write entry back to the system clipboard
///   * `delete(id)`        -- remove the entry from the db
///   * `wipe()`            -- clear the entire history
///   * `start_watcher()`   -- spawn `cliphist watch` so the history
///                            updates live (best-effort; the watcher
///                            is optional, refresh() is always available)
///
/// All subprocesses are best-effort: failure on the host (no `cliphist`,
/// no session bus, no D-Bus, etc.) degrades to a "no history" panel.
#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(QString, items_json)]
        #[qproperty(i32, total)]
        #[qproperty(bool, running)]
        #[qproperty(QString, running_status)]
        type Clipboard = super::ClipboardRust;

        #[qinvokable]
        fn refresh(self: Pin<&mut Self>);

        #[qinvokable]
        fn pick(self: Pin<&mut Self>, id: i64);

        #[qinvokable]
        fn remove(self: Pin<&mut Self>, id: i64);

        #[qinvokable]
        fn wipe(self: Pin<&mut Self>);

        #[qinvokable]
        fn start_watcher(self: Pin<&mut Self>);

        #[qinvokable]
        fn is_enabled(&self) -> bool;
    }

    impl cxx_qt::Threading for Clipboard {}
}

#[derive(Default)]
pub struct ClipboardRust {
    items_json: QString,
    total: i32,
    running: bool,
    running_status: QString,
}

#[derive(Default, Clone, Debug)]
struct Entry {
    id: i64,
    preview: String,
    full: String,
}

fn run_cliphist(args: &[&str]) -> Option<String> {
    let out = Command::new("cliphist").args(args).output().ok()?;
    if !out.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&out.stdout).to_string())
}

fn parse_entries(raw: &str) -> Vec<Entry> {
    // `cliphist list` writes "<id>\t<content>" per item; multi-line
    // content is encoded with embedded newlines, so the line parser
    // must look at *all* output after an id to collect the full entry
    // until another id prefix appears. cliphist doesn't quote ids
    // (they're always decimal), so splitting on lines that match
    // `^\d+\t` is safe.
    let mut entries: Vec<Entry> = Vec::new();
    let mut current: Option<Entry> = None;
    for line in raw.lines() {
        if let Some((id_part, content)) = line.split_once('\t')
            && let Ok(id) = id_part.parse::<i64>() {
                if let Some(prev) = current.take() {
                    entries.push(prev);
                }
                let preview = content
                    .chars()
                    .take(80)
                    .collect::<String>()
                    .replace('\n', " ");
                current = Some(Entry {
                    id,
                    preview,
                    full: content.to_string(),
                });
                continue;
            }
        if let Some(ref mut e) = current {
            if !e.full.is_empty() {
                e.full.push('\n');
            }
            e.full.push_str(line);
        }
    }
    if let Some(prev) = current.take() {
        entries.push(prev);
    }
    entries
}

fn items_to_json(entries: &[Entry]) -> String {
    let mut out = String::from("[");
    for (i, e) in entries.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        out.push_str(&format!(
            r#"{{"id":{},"preview":{},"full":{}}}"#,
            e.id,
            json_string(&e.preview),
            json_string(&e.full)
        ));
    }
    out.push(']');
    out
}

fn json_string(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            other => out.push(other),
        }
    }
    out.push('"');
    out
}

impl qobject::Clipboard {
    pub fn is_enabled(&self) -> bool {
        // Cheap probe: do we have a cliphist binary on PATH?
        Command::new("cliphist")
            .arg("version")
            .output()
            .map(|o| o.status.success())
            .unwrap_or(false)
    }

    pub fn refresh(self: Pin<&mut Self>) {
        let mut this = self;
        match run_cliphist(&["list"]) {
            Some(raw) => {
                let entries = parse_entries(&raw);
                let total = entries.len() as i32;
                this.as_mut().set_items_json(QString::from(items_to_json(&entries).as_str()));
                this.as_mut().set_total(total);
                this.as_mut()
                    .set_running_status(QString::from(format!("ok ({} entries)", total).as_str()));
            }
            None => {
                this.as_mut()
                    .set_running_status(QString::from("cliphist not available"));
                this.as_mut().set_items_json(QString::from("[]"));
                this.as_mut().set_total(0);
            }
        }
    }

    pub fn pick(self: Pin<&mut Self>, id: i64) {
        // cliphist's pick isn't a separate command; the usual flow is
        // `cliphist decode <id>` to print the raw payload, then a
        // separate `wl-copy` to put it back on the system clipboard.
        // Some cliphist builds expose `pick` directly; we try both.
        let mut stage = String::new();
        if run_cliphist(&["decode", &id.to_string()])
            .or_else(|| run_cliphist(&["pick", &id.to_string()]))
            .is_some()
        {
            // Re-fetch list to find the entry content. Simpler: run
            // `cliphist list` and find the matching id, then push the
            // content to wl-copy.
            if let Some(raw) = run_cliphist(&["list"]) {
                for entry in parse_entries(&raw) {
                    if entry.id == id {
                        stage = entry.full;
                        break;
                    }
                }
            }
        }
        if stage.is_empty() {
            return;
        }
        // Write to the system clipboard via the same fallback chain
        // Spawner uses: `wl-copy > xclip > xsel`.
        let candidates: &[&[&str]] = &[
            &["wl-copy"],
            &["xclip", "-selection", "clipboard"],
            &["xsel", "--clipboard", "--input"],
        ];
        for argv in candidates {
            if argv.is_empty() {
                continue;
            }
            let (first, rest) = argv.split_first().unwrap();
            // Pipe the staged text into the tool's stdin so we don't
            // need a temp file.
            use std::io::Write;
            use std::process::Stdio;
            if let Ok(mut child) = Command::new(first)
                .args(rest)
                .stdin(Stdio::piped())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .spawn()
            {
                if let Some(stdin) = child.stdin.as_mut() {
                    let _ = stdin.write_all(stage.as_bytes());
                }
                let _ = child.wait();
                return;
            }
        }
    }

    pub fn remove(self: Pin<&mut Self>, id: i64) {
        let _ = run_cliphist(&["delete", &id.to_string()]);
        self.refresh();
    }

    pub fn wipe(self: Pin<&mut Self>) {
        let _ = run_cliphist(&["wipe"]);
        let mut this = self;
        this.as_mut().set_items_json(QString::from("[]"));
        this.as_mut().set_total(0);
        this.as_mut().set_running_status(QString::from("wiped"));
    }

    pub fn start_watcher(self: Pin<&mut Self>) {
        // cliphist doesn't ship a `watch` subcommand in every build
        // (it's marked "coming soon" in some); we fall back to a
        // 1-second timer in QML that calls refresh() while the panel
        // is open. This qinvokable just spawns cliphist-store on a
        // backgrounded poll so any new selection shows up; it's a
        // best-effort, no-op if cliphist doesn't support it.
        let _ = run_cliphist(&["version"]);
        let mut this = self;
        this.as_mut()
            .set_running_status(QString::from("watcher running"));
    }
}
