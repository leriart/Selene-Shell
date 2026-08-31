/// TodoBoard -- 3-column kanban (Brain_Shell port).
//
// Persistent JSON store at ~/.local/share/selene/todo.json. Three
// statuses: "todo", "doing", "done". Cards have `text`, optional
// `priority` (0..2), and `ts`. The QObject exposes `cards_json` so
// the QML side can group by status and re-render in one pass.
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
        #[qproperty(QString, cards_json)]
        #[qproperty(QString, status)]
        type TodoBoard = super::TodoBoardRust;

        #[qinvokable]
        fn refresh(self: Pin<&mut Self>);

        #[qinvokable]
        fn add_card(self: Pin<&mut Self>, text: &QString, status: &QString) -> bool;

        #[qinvokable]
        fn move_card(self: Pin<&mut Self>, index: i32, status: &QString) -> bool;

        #[qinvokable]
        fn remove_card(self: Pin<&mut Self>, index: i32) -> bool;

        #[qinvokable]
        fn path(&self) -> QString;
    }
}

pub struct TodoBoardRust {
    cards_json: QString,
    status: QString,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct Card {
    ts: String,
    text: String,
    status: String,
    priority: i32,
}

fn cards_slot() -> &'static Mutex<Vec<Card>> {
    static SLOT: std::sync::OnceLock<Mutex<Vec<Card>>> =
        std::sync::OnceLock::new();
    SLOT.get_or_init(|| Mutex::new(Vec::new()))
}

impl Default for TodoBoardRust {
    fn default() -> Self {
        Self {
            cards_json: QString::from("[]"),
            status: QString::from(""),
        }
    }
}

fn todo_path() -> PathBuf {
    let home = std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/"));
    home.join(".local/share/selene/todo.json")
}

fn load(path: &PathBuf) -> Vec<Card> {
    let raw = match fs::read_to_string(path) {
        Ok(s) => s,
        Err(_) => String::new(),
    };
    serde_json::from_str(&raw).unwrap_or_default()
}

fn store(path: &PathBuf, cards: &[Card]) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| format!("mkdir: {e}"))?;
    }
    let body = serde_json::to_string_pretty(cards)
        .map_err(|e| format!("json: {e}"))?;
    fs::write(path, body).map_err(|e| format!("write: {e}"))
}

fn serialize_to(cards: &[Card]) -> QString {
    QString::from(
        serde_json::to_string(cards)
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

impl qobject::TodoBoard {
    pub fn refresh(self: Pin<&mut Self>) {
        let cards = load(&todo_path());
        let json = serialize_to(&cards);
        let count = cards.len();
        if let Ok(mut slot) = cards_slot().lock() {
            *slot = cards;
        }
        let mut this = self;
        this.as_mut().set_cards_json(json);
        this.as_mut().set_status(QString::from(
            format!("loaded {count} cards").as_str(),
        ));
    }

    pub fn add_card(self: Pin<&mut Self>, text: &QString, status: &QString) -> bool {
        let t = text.to_string().trim().to_string();
        if t.is_empty() {
            return false;
        }
        let mut snapshot: Vec<Card> = match cards_slot().lock() {
            Ok(g) => g.clone(),
            Err(_) => Vec::new(),
        };
        snapshot.push(Card {
            ts: now_iso(),
            text: t,
            status: status.to_string(),
            priority: 0,
        });
        if let Err(err) = store(&todo_path(), &snapshot) {
            let mut me = self;
            me.as_mut().set_status(QString::from(err.as_str()));
            return false;
        }
        let json = serialize_to(&snapshot);
        if let Ok(mut slot) = cards_slot().lock() {
            *slot = snapshot;
        }
        let mut me = self;
        me.as_mut().set_cards_json(json);
        me.as_mut().set_status(QString::from("ok"));
        true
    }

    pub fn move_card(self: Pin<&mut Self>, index: i32, status: &QString) -> bool {
        let mut snapshot: Vec<Card> = match cards_slot().lock() {
            Ok(g) => g.clone(),
            Err(_) => Vec::new(),
        };
        if index < 0 || (index as usize) >= snapshot.len() {
            return false;
        }
        snapshot[index as usize].status = status.to_string();
        if let Err(err) = store(&todo_path(), &snapshot) {
            let mut me = self;
            me.as_mut().set_status(QString::from(err.as_str()));
            return false;
        }
        let json = serialize_to(&snapshot);
        if let Ok(mut slot) = cards_slot().lock() {
            *slot = snapshot;
        }
        let mut me = self;
        me.as_mut().set_cards_json(json);
        true
    }

    pub fn remove_card(self: Pin<&mut Self>, index: i32) -> bool {
        let mut snapshot: Vec<Card> = match cards_slot().lock() {
            Ok(g) => g.clone(),
            Err(_) => Vec::new(),
        };
        if index < 0 || (index as usize) >= snapshot.len() {
            return false;
        }
        snapshot.remove(index as usize);
        if let Err(err) = store(&todo_path(), &snapshot) {
            let mut me = self;
            me.as_mut().set_status(QString::from(err.as_str()));
            return false;
        }
        let json = serialize_to(&snapshot);
        if let Ok(mut slot) = cards_slot().lock() {
            *slot = snapshot;
        }
        let mut me = self;
        me.as_mut().set_cards_json(json);
        true
    }

    pub fn path(&self) -> QString {
        QString::from(todo_path().to_string_lossy().as_ref())
    }
}
