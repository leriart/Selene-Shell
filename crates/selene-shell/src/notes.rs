/// Notes -- persistent free-form notes (Brain_Shell / NothingLess port).
//
// The `Notes` QObject keeps a JSON array of `{ts, text}` entries on
// disk at `~/.local/share/selene/notes.json`. QML reads the whole
// list as JSON via `notes_json` and calls `add_note(text)` /
// `remove_note(index)` to mutate. Writes are synchronous and small
// (a few KB), so the main thread is fine -- no separate worker.
use core::pin::Pin;
use cxx_qt_lib::QString;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use std::sync::Mutex;

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(QString, notes_json)]
        #[qproperty(QString, status)]
        type Notes = super::NotesRust;

        #[qinvokable]
        fn refresh(self: Pin<&mut Self>);

        #[qinvokable]
        fn add_note(self: Pin<&mut Self>, text: &QString) -> bool;

        #[qinvokable]
        fn remove_note(self: Pin<&mut Self>, index: i32) -> bool;

        #[qinvokable]
        fn path(&self) -> QString;

        #[qinvokable]
        fn save_now(self: Pin<&mut Self>) -> bool;
    }
}

pub struct NotesRust {
    notes_json: QString,
    status: QString,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct NoteEntry {
    ts: String,
    text: String,
}

// Process-wide store. We only ever have one Notes QObject, so a global
// Mutex is simpler than threading state through the cxx-qt bridge.
fn entries_slot() -> &'static Mutex<Vec<NoteEntry>> {
    static SLOT: std::sync::OnceLock<Mutex<Vec<NoteEntry>>> =
        std::sync::OnceLock::new();
    SLOT.get_or_init(|| Mutex::new(Vec::new()))
}

impl Default for NotesRust {
    fn default() -> Self {
        Self {
            notes_json: QString::from("[]"),
            status: QString::from(""),
        }
    }
}

fn notes_path() -> PathBuf {
    let home = std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/"));
    home.join(".local/share/selene/notes.json")
}

fn load(path: &PathBuf) -> Vec<NoteEntry> {
    let raw = match fs::read_to_string(path) {
        Ok(s) => s,
        Err(_) => String::new(),
    };
    serde_json::from_str(&raw).unwrap_or_default()
}

fn store(path: &PathBuf, entries: &[NoteEntry]) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| format!("mkdir: {e}"))?;
    }
    let body = serde_json::to_string_pretty(entries)
        .map_err(|e| format!("json: {e}"))?;
    fs::write(path, body).map_err(|e| format!("write: {e}"))
}

fn serialize_to(entries: &[NoteEntry]) -> QString {
    QString::from(
        serde_json::to_string(entries)
            .unwrap_or_else(|_| "[]".to_string())
            .as_str(),
    )
}

fn now_iso() -> String {
    std::process::Command::new("date")
        .arg("-Iseconds")
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_else(|| "1970-01-01T00:00:00+00:00".to_string())
}

impl qobject::Notes {
    pub fn refresh(self: Pin<&mut Self>) {
        let entries = load(&notes_path());
        let json = serialize_to(&entries);
        let count = entries.len();
        if let Ok(mut slot) = entries_slot().lock() {
            *slot = entries;
        }
        let mut this = self;
        this.as_mut().set_notes_json(json);
        this.as_mut().set_status(QString::from(
            format!("loaded {count} entries").as_str(),
        ));
    }

    pub fn add_note(self: Pin<&mut Self>, text: &QString) -> bool {
        let trimmed = text.to_string().trim().to_string();
        if trimmed.is_empty() {
            return false;
        }
        let mut snapshot: Vec<NoteEntry> = match entries_slot().lock() {
            Ok(g) => g.clone(),
            Err(_) => Vec::new(),
        };
        snapshot.push(NoteEntry {
            ts: now_iso(),
            text: trimmed,
        });
        if let Err(err) = store(&notes_path(), &snapshot) {
            let mut me = self;
            me.as_mut().set_status(QString::from(err.as_str()));
            return false;
        }
        let json = serialize_to(&snapshot);
        if let Ok(mut slot) = entries_slot().lock() {
            *slot = snapshot;
        }
        let mut me = self;
        me.as_mut().set_notes_json(json);
        me.as_mut().set_status(QString::from("ok"));
        true
    }

    pub fn remove_note(self: Pin<&mut Self>, index: i32) -> bool {
        let mut snapshot: Vec<NoteEntry> = match entries_slot().lock() {
            Ok(g) => g.clone(),
            Err(_) => Vec::new(),
        };
        if index < 0 || (index as usize) >= snapshot.len() {
            return false;
        }
        snapshot.remove(index as usize);
        if let Err(err) = store(&notes_path(), &snapshot) {
            let mut me = self;
            me.as_mut().set_status(QString::from(err.as_str()));
            return false;
        }
        let json = serialize_to(&snapshot);
        if let Ok(mut slot) = entries_slot().lock() {
            *slot = snapshot;
        }
        let mut me = self;
        me.as_mut().set_notes_json(json);
        true
    }

    pub fn path(&self) -> QString {
        QString::from(notes_path().to_string_lossy().as_ref())
    }

    pub fn save_now(self: Pin<&mut Self>) -> bool {
        let snapshot: Vec<NoteEntry> = match entries_slot().lock() {
            Ok(g) => g.clone(),
            Err(_) => Vec::new(),
        };
        match store(&notes_path(), &snapshot) {
            Ok(()) => {
                let mut me = self;
                me.as_mut().set_status(QString::from("saved"));
                true
            }
            Err(err) => {
                let mut me = self;
                me.as_mut().set_status(QString::from(err.as_str()));
                false
            }
        }
    }
}
