use core::pin::Pin;
use cxx_qt::Threading;
use cxx_qt_lib::QString;
use serde::{Deserialize, Serialize};
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(QString, notifications_json)]
        #[qproperty(QString, status_json)]
        #[qproperty(bool, dnd_enabled)]
        #[qproperty(bool, dbus_connected)]
        #[qproperty(i32, unread_count)]
        type Notifier = super::NotifierRust;

        #[qinvokable]
        fn notify(
            self: Pin<&mut Self>,
            app_name: &QString,
            title: &QString,
            body: &QString,
            urgency: i32,
            icon: &QString,
        ) -> i32;

        #[qinvokable]
        fn mark_read(self: Pin<&mut Self>, id: i32);

        #[qinvokable]
        fn mark_all_read(self: Pin<&mut Self>);

        #[qinvokable]
        fn clear(self: Pin<&mut Self>);

        #[qinvokable]
        fn toggle_dnd(self: Pin<&mut Self>);

        #[qinvokable]
        fn refresh_from_disk(self: Pin<&mut Self>);

        #[qinvokable]
        fn storage_dir(&self) -> QString;

        #[qinvokable]
        fn count(&self) -> i32;
    }

    impl cxx_qt::Threading for Notifier {}
}

#[derive(Default)]
pub struct NotifierRust {
    notifications_json: QString,
    status_json: QString,
    dnd_enabled: bool,
    dbus_connected: bool,
    unread_count: i32,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Notification {
    pub id: u32,
    pub app_name: String,
    pub title: String,
    pub body: String,
    pub timestamp: u64,
    pub urgency: u8,
    pub icon: String,
    pub read: bool,
}

#[derive(Default)]
pub struct Store {
    pub next_id: u32,
    pub entries: Vec<Notification>,
    pub dnd: bool,
    pub storage_dir: Option<std::path::PathBuf>,
    pub dbus_connected: bool,
    pub dbus_error: Option<String>,
}

type SharedStore = Arc<Mutex<Store>>;

fn shared() -> &'static SharedStore {
    use std::sync::OnceLock;
    static STORE: OnceLock<SharedStore> = OnceLock::new();
    STORE.get_or_init(|| Arc::new(Mutex::new(Store::default())))
}

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn storage_path() -> std::path::PathBuf {
    let mut path = std::env::var_os("SELENE_SHARE")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| {
            let home = std::env::var_os("HOME")
                .map(|h| h.to_string_lossy().to_string())
                .unwrap_or_else(|| "/tmp".to_string());
            std::path::PathBuf::from(format!("{home}/.local/share/selene"))
        });
    path.push("notifications.json");
    path
}

fn persist_to_disk(state: &Store) {
    let Some(dir) = state.storage_dir.as_ref() else {
        return;
    };
    if std::fs::create_dir_all(dir).is_err() {
        return;
    }
    let path = dir.join("notifications.json");
    if let Ok(s) = serde_json::to_string_pretty(&state.entries) {
        let _ = std::fs::write(&path, s);
    }
}

fn unread_count(state: &Store) -> i32 {
    state.entries.iter().filter(|n| !n.read).count() as i32
}

fn entries_json(state: &Store) -> QString {
    QString::from(
        serde_json::to_string(&state.entries)
            .unwrap_or_else(|_| "[]".to_string())
            .as_str(),
    )
}

fn status_json(state: &Store) -> QString {
    let mut obj = serde_json::json!({
        "dnd": state.dnd,
        "count": state.entries.len(),
        "unread": unread_count(state),
        "next_id": state.next_id,
    });
    if let Some(err) = &state.dbus_error {
        obj["dbus_error"] = serde_json::Value::String(err.clone());
    } else {
        obj["dbus_error"] = serde_json::Value::Null;
    }
    obj["dbus_connected"] = serde_json::Value::Bool(state.dbus_connected);
    QString::from(obj.to_string().as_str())
}

fn ensure_storage_dir(state: &mut Store) {
    if state.storage_dir.is_none() {
        let path = storage_path();
        let dir = path
            .parent()
            .map(|p| p.to_path_buf())
            .unwrap_or_else(|| std::path::PathBuf::from("."));
        let _ = std::fs::create_dir_all(&dir);
        if let Ok(text) = std::fs::read_to_string(&path) {
            if let Ok(items) = serde_json::from_str::<Vec<Notification>>(&text) {
                state.next_id = items.iter().map(|n| n.id + 1).max().unwrap_or(1);
                state.entries = items;
            }
        }
        state.storage_dir = Some(dir);
    }
}

impl qobject::Notifier {
    pub fn storage_dir(&self) -> QString {
        QString::from(storage_path().to_string_lossy().as_ref())
    }

    pub fn count(&self) -> i32 {
        shared()
            .lock()
            .map(|s| s.entries.len() as i32)
            .unwrap_or(0)
    }

    pub fn notify(
        self: Pin<&mut Self>,
        app_name: &QString,
        title: &QString,
        body: &QString,
        urgency: i32,
        icon: &QString,
    ) -> i32 {
        let app = app_name.to_string();
        let ttl = title.to_string();
        let bdy = body.to_string();
        let icn = icon.to_string();

        let mut store = match shared().lock() {
            Ok(s) => s,
            Err(_) => return -1,
        };
        ensure_storage_dir(&mut store);
        if store.dnd {
            return 0;
        }
        let id = store.next_id;
        store.next_id = store.next_id.saturating_add(1);
        let entry = Notification {
            id,
            app_name: app,
            title: ttl,
            body: bdy,
            timestamp: now_secs(),
            urgency: urgency.clamp(0, 2) as u8,
            icon: icn,
            read: false,
        };
        store.entries.push(entry);
        let count = unread_count(&store);
        let entries = entries_json(&store);
        let status = status_json(&store);
        persist_to_disk(&store);
        drop(store);

        let mut this = self;
        this.as_mut().set_notifications_json(entries);
        this.as_mut().set_status_json(status);
        this.as_mut().set_unread_count(count);
        id as i32
    }

    pub fn mark_read(self: Pin<&mut Self>, id: i32) {
        let mut store = match shared().lock() {
            Ok(s) => s,
            Err(_) => return,
        };
        if let Some(n) = store.entries.iter_mut().find(|n| n.id == id as u32) {
            if !n.read {
                n.read = true;
            }
        }
        let count = unread_count(&store);
        let entries = entries_json(&store);
        let status = status_json(&store);
        persist_to_disk(&store);
        drop(store);

        let mut this = self;
        this.as_mut().set_notifications_json(entries);
        this.as_mut().set_status_json(status);
        this.as_mut().set_unread_count(count);
    }

    pub fn mark_all_read(self: Pin<&mut Self>) {
        let mut store = match shared().lock() {
            Ok(s) => s,
            Err(_) => return,
        };
        for n in store.entries.iter_mut() {
            n.read = true;
        }
        let count = unread_count(&store);
        let entries = entries_json(&store);
        let status = status_json(&store);
        persist_to_disk(&store);
        drop(store);

        let mut this = self;
        this.as_mut().set_notifications_json(entries);
        this.as_mut().set_status_json(status);
        this.as_mut().set_unread_count(count);
    }

    pub fn clear(self: Pin<&mut Self>) {
        let mut store = match shared().lock() {
            Ok(s) => s,
            Err(_) => return,
        };
        store.entries.clear();
        persist_to_disk(&store);
        drop(store);

        let mut this = self;
        this.as_mut().set_notifications_json(QString::from("[]"));
        this.as_mut().set_unread_count(0);
    }

    pub fn toggle_dnd(self: Pin<&mut Self>) {
        let mut store = match shared().lock() {
            Ok(s) => s,
            Err(_) => return,
        };
        store.dnd = !store.dnd;
        let status = status_json(&store);
        let dnd = store.dnd;
        drop(store);

        let mut this = self;
        this.as_mut().set_dnd_enabled(dnd);
        this.as_mut().set_status_json(status);
    }

    pub fn refresh_from_disk(self: Pin<&mut Self>) {
        let mut store = match shared().lock() {
            Ok(s) => s,
            Err(_) => return,
        };
        store.storage_dir = None;
        ensure_storage_dir(&mut store);
        let count = unread_count(&store);
        let entries = entries_json(&store);
        let status = status_json(&store);
        let dnd = store.dnd;
        let dbus_connected = store.dbus_connected;
        drop(store);

        let mut this = self;
        this.as_mut().set_dnd_enabled(dnd);
        this.as_mut().set_dbus_connected(dbus_connected);
        this.as_mut().set_notifications_json(entries);
        this.as_mut().set_status_json(status);
        this.as_mut().set_unread_count(count);
    }
}
