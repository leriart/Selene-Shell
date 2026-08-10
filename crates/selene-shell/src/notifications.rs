use core::pin::Pin;
use cxx_qt::Threading;
use cxx_qt_lib::QString;
use serde::{Deserialize, Serialize};
use std::sync::{Arc, Mutex, OnceLock};
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
        #[qproperty(bool, game_mode)]
        #[qproperty(QString, power_profile)]
        #[qproperty(i32, unread_count)]
        #[qproperty(i32, history_max)]
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
        fn invoke_action(self: Pin<&mut Self>, id: i32, action_key: &QString);

        #[qinvokable]
        fn close_notification(self: Pin<&mut Self>, id: i32);

        #[qinvokable]
        fn apply_history_max(self: Pin<&mut Self>, max: i32);

        #[qinvokable]
        fn start_dbus(self: Pin<&mut Self>);

        #[qinvokable]
        fn apply_game_mode(self: Pin<&mut Self>, enabled: bool);

        #[qinvokable]
        fn apply_power_profile(self: Pin<&mut Self>, profile: &QString);

        #[qinvokable]
        fn storage_dir(&self) -> QString;

        #[qinvokable]
        fn count(&self) -> i32;
    }

    impl cxx_qt::Threading for Notifier {}
}

const DEFAULT_HISTORY_MAX: i32 = 200;

#[derive(Default)]
pub struct NotifierRust {
    notifications_json: QString,
    status_json: QString,
    dnd_enabled: bool,
    dbus_connected: bool,
    game_mode: bool,
    power_profile: QString,
    unread_count: i32,
    history_max: i32,
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
    #[serde(default)]
    pub actions: Vec<String>,
    #[serde(default)]
    pub expire_timeout: i32,
}

#[derive(Default)]
pub struct Store {
    pub next_id: u32,
    pub entries: Vec<Notification>,
    pub dnd: bool,
    pub storage_dir: Option<std::path::PathBuf>,
    pub dbus_connected: bool,
    pub dbus_error: Option<String>,
    pub history_max_override: i32,
}

type SharedStore = Arc<Mutex<Store>>;

fn shared() -> &'static SharedStore {
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

/// Insert (or replace, when replaces_id matches) a notification, persist and
/// return the JSON blobs the QML side needs. Caller drops the lock and queues
/// the property updates.
fn store_push(
    app_name: String,
    replaces_id: u32,
    icon: String,
    title: String,
    body: String,
    urgency: u8,
    actions: Vec<String>,
    expire_timeout: i32,
) -> Option<(u32, QString, QString, i32)> {
    let mut store = shared().lock().ok()?;
    ensure_storage_dir(&mut store);
    if store.dnd {
        return None;
    }
    let id = if replaces_id > 0 {
        replaces_id
    } else {
        let id = store.next_id.max(1);
        store.next_id = id.saturating_add(1);
        id
    };
    let entry = Notification {
        id,
        app_name,
        title,
        body,
        timestamp: now_secs(),
        urgency: urgency.min(2),
        icon,
        read: false,
        actions,
        expire_timeout,
    };
    if let Some(existing) = store.entries.iter_mut().find(|n| n.id == id) {
        *existing = entry;
    } else {
        store.entries.push(entry);
    }
    // FIFO cap -- drop oldest entries when the history max is exceeded.
    let max = if store.history_max_override > 0 {
        store.history_max_override
    } else {
        DEFAULT_HISTORY_MAX
    };
    if max > 0 && store.entries.len() > max as usize {
        let drop = store.entries.len() - max as usize;
        store.entries.drain(0..drop);
    }
    let count = unread_count(&store);
    let entries = entries_json(&store);
    let status = status_json(&store);
    persist_to_disk(&store);
    Some((id, entries, status, count))
}

// ---------------------------------------------------------------------------
// D-Bus daemon: org.freedesktop.Notifications
// ---------------------------------------------------------------------------

const FDO_PATH: &str = "/org/freedesktop/Notifications";
const FDO_NAME: &str = "org.freedesktop.Notifications";

static DBUS_STARTED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
static DBUS_CONN: OnceLock<zbus::blocking::Connection> = OnceLock::new();

struct FdoNotifications {
    qt: cxx_qt::CxxQtThread<qobject::Notifier>,
    conn: zbus::Connection,
}

#[zbus::interface(name = "org.freedesktop.Notifications")]
impl FdoNotifications {
    async fn notify(
        &mut self,
        app_name: String,
        replaces_id: u32,
        app_icon: String,
        summary: String,
        body: String,
        actions: Vec<String>,
        hints: std::collections::HashMap<String, zbus::zvariant::Value<'_>>,
        expire_timeout: i32,
    ) -> u32 {
        let urgency = hints
            .get("urgency")
            .and_then(|v| u8::try_from(v.clone()).ok())
            .unwrap_or(1);
        let icon = if app_icon.is_empty() {
            hints
                .get("image-path")
                .or_else(|| hints.get("image_path"))
                .and_then(|v| String::try_from(v.clone()).ok())
                .unwrap_or_default()
        } else {
            app_icon
        };

        let Some((id, entries, status, count)) = store_push(
            app_name,
            replaces_id,
            icon,
            summary,
            body,
            urgency,
            actions,
            expire_timeout,
        ) else {
            // DND active or store poisoned: spec says the id is still
            // returned; 0 signals "not shown".
            return 0;
        };

        let _ = self.qt.queue(move |mut n| {
            n.as_mut().set_notifications_json(entries);
            n.as_mut().set_status_json(status);
            n.as_mut().set_unread_count(count);
        });
        id
    }

    async fn close_notification(&mut self, id: u32) {
        remove_entry(id);
        if let Ok(store) = shared().lock() {
            let entries = entries_json(&store);
            let status = status_json(&store);
            let count = unread_count(&store);
            drop(store);
            let _ = self.qt.queue(move |mut n| {
                n.as_mut().set_notifications_json(entries);
                n.as_mut().set_status_json(status);
                n.as_mut().set_unread_count(count);
            });
        }
        // Reason 2: dismissed by CloseNotification call.
        let _ = self
            .conn
            .emit_signal(
                None::<&str>,
                FDO_PATH,
                "org.freedesktop.Notifications",
                "NotificationClosed",
                &(id, 2u32),
            )
            .await;
    }

    async fn get_capabilities(&self) -> Vec<&'static str> {
        vec!["body", "body-markup", "icon-static", "actions", "persistence"]
    }

    async fn get_server_information(&self) -> (String, String, String, String) {
        (
            "selene".to_string(),
            "selene".to_string(),
            env!("CARGO_PKG_VERSION").to_string(),
            "1.2".to_string(),
        )
    }
}

fn remove_entry(id: u32) {
    if let Ok(mut store) = shared().lock() {
        let before = store.entries.len();
        store.entries.retain(|n| n.id != id);
        if store.entries.len() != before {
            persist_to_disk(&store);
        }
    }
}

fn set_dbus_state(qt: &cxx_qt::CxxQtThread<qobject::Notifier>, connected: bool, err: Option<String>) {
    if let Ok(mut store) = shared().lock() {
        store.dbus_connected = connected;
        store.dbus_error = err;
    }
    let status = shared()
        .lock()
        .map(|s| status_json(&s))
        .unwrap_or_else(|_| QString::from("{}"));
    let _ = qt.queue(move |mut n| {
        n.as_mut().set_dbus_connected(connected);
        n.as_mut().set_status_json(status);
    });
}

fn dbus_thread_main(qt: cxx_qt::CxxQtThread<qobject::Notifier>) {
    let conn = match zbus::blocking::Connection::session() {
        Ok(c) => c,
        Err(err) => {
            set_dbus_state(&qt, false, Some(format!("session bus: {err}")));
            return;
        }
    };

    let server = FdoNotifications {
        qt: qt.clone(),
        conn: conn.inner().clone(),
    };
    if let Err(err) = conn.object_server().at(FDO_PATH, server) {
        set_dbus_state(&qt, false, Some(format!("object server: {err}")));
        return;
    }

    // DoNotQueue: if another daemon (dunst, mako, quickshell, ...) already
    // owns the well-known name, fail loudly instead of silently queueing.
    let flags = zbus::fdo::RequestNameFlags::DoNotQueue.into();
    let reply = conn.request_name_with_flags(FDO_NAME, flags);
    match reply {
        Ok(zbus::fdo::RequestNameReply::PrimaryOwner) => {
            set_dbus_state(&qt, true, None);
        }
        Ok(other) => {
            set_dbus_state(
                &qt,
                false,
                Some(format!(
                    "name '{FDO_NAME}' owned by another daemon (reply={other:?}); \
                     stop quickshell / mako / dunst first"
                )),
            );
            return;
        }
        Err(err) => {
            set_dbus_state(
                &qt,
                false,
                Some(format!("name taken (another daemon is running): {err}")),
            );
            return;
        }
    }

    if DBUS_CONN.set(conn).is_err() {
        set_dbus_state(&qt, false, Some("connection already stored".into()));
        return;
    }

    // The connection's internal executor keeps dispatching method calls on
    // its own thread; this thread just stays alive holding the state.
    loop {
        std::thread::park();
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
        let Some((id, entries, status, count)) = store_push(
            app_name.to_string(),
            0,
            icon.to_string(),
            title.to_string(),
            body.to_string(),
            urgency.clamp(0, 2) as u8,
            Vec::new(),
            -1,
        ) else {
            return 0;
        };

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
        // Apply the cap on disk reads so a historic file with thousands of
        // entries doesn't push the panel into the disk I/O ceiling.
        let max = if store.history_max_override > 0 {
            store.history_max_override
        } else {
            DEFAULT_HISTORY_MAX
        } as usize;
        if max > 0 && store.entries.len() > max {
            let drop = store.entries.len() - max;
            store.entries.drain(0..drop);
        }
        let count = unread_count(&store);
        let entries = entries_json(&store);
        let status = status_json(&store);
        let dnd = store.dnd;
        let dbus_connected = store.dbus_connected;
        // Reflect the effective cap on the UI so the Settings panel can
        // surface it.
        let current_max = if store.history_max_override > 0 {
            store.history_max_override
        } else {
            DEFAULT_HISTORY_MAX
        };
        drop(store);

        let mut this = self;
        this.as_mut().set_dnd_enabled(dnd);
        this.as_mut().set_dbus_connected(dbus_connected);
        this.as_mut().set_notifications_json(entries);
        this.as_mut().set_status_json(status);
        this.as_mut().set_unread_count(count);
        this.as_mut().set_history_max(current_max);
    }

    pub fn apply_history_max(self: Pin<&mut Self>, max: i32) {
        let clamped = max.clamp(0, 10_000);
        if let Ok(mut store) = shared().lock() {
            store.history_max_override = clamped;
            // Apply immediately: drop oldest beyond the new cap.
            let limit = if clamped > 0 { clamped as usize } else { DEFAULT_HISTORY_MAX as usize };
            if store.entries.len() > limit {
                let drop = store.entries.len() - limit;
                store.entries.drain(0..drop);
            }
        }
        let mut this = self;
        this.as_mut().set_history_max(clamped);
    }

    pub fn apply_game_mode(self: Pin<&mut Self>, enabled: bool) {
        // When game mode is on, also turn on DND and bump
        // power-profile to performance so games get full CPU/GPU.
        let mut this = self;
        this.as_mut().set_game_mode(enabled);
        // Force DND to the desired state.
        if let Ok(mut store) = shared().lock() {
            store.dnd = enabled;
            let status = status_json(&store);
            let dnd = store.dnd;
            drop(store);
            this.as_mut().set_dnd_enabled(dnd);
            this.as_mut().set_status_json(status);
        }
        let profile = if enabled { "performance" } else { "balanced" };
        let _ = std::process::Command::new("powerprofilesctl")
            .arg("set")
            .arg(profile)
            .output();
        this.as_mut()
            .set_power_profile(QString::from(profile));
    }

    pub fn apply_power_profile(self: Pin<&mut Self>, profile: &QString) {
        let p = profile.to_string();
        let valid = matches!(p.as_str(), "power-saver" | "balanced" | "performance");
        if !valid {
            return;
        }
        let _ = std::process::Command::new("powerprofilesctl")
            .arg("set")
            .arg(&p)
            .output();
        let mut this = self;
        this.as_mut()
            .set_power_profile(QString::from(p.as_str()));
    }

    pub fn close_notification(self: Pin<&mut Self>, id: i32) {
        remove_entry(id as u32);
        if let Ok(store) = shared().lock() {
            let entries = entries_json(&store);
            let status = status_json(&store);
            let count = unread_count(&store);
            drop(store);
            let mut this = self;
            this.as_mut().set_notifications_json(entries);
            this.as_mut().set_status_json(status);
            this.as_mut().set_unread_count(count);
        }
        // Reason 3: revoked by the user (shell side).
        emit_closed(id as u32, 3);
    }

    pub fn invoke_action(self: Pin<&mut Self>, id: i32, action_key: &QString) {
        let key = action_key.to_string();
        if key.is_empty() {
            return;
        }
        emit_action_invoked(id as u32, key);
        let mut this = self;
        this.as_mut().mark_read(id);
    }

    pub fn start_dbus(self: Pin<&mut Self>) {
        if DBUS_STARTED.swap(true, std::sync::atomic::Ordering::SeqCst) {
            return;
        }
        let qt: cxx_qt::CxxQtThread<qobject::Notifier> = self.as_ref().qt_thread();
        std::thread::Builder::new()
            .name("selene-dbus".into())
            .spawn(move || dbus_thread_main(qt))
            .expect("selene: failed to spawn dbus thread");
    }
}

/// Emit NotificationClosed from outside the interface method context.
fn emit_closed(id: u32, reason: u32) {
    let Some(conn) = DBUS_CONN.get() else { return; };
    let _ = conn.emit_signal(
        None::<&str>,
        FDO_PATH,
        "org.freedesktop.Notifications",
        "NotificationClosed",
        &(id, reason),
    );
}

/// Emit ActionInvoked so the originating app (e.g. a chat client with
/// "reply"/"open" buttons) receives the callback.
fn emit_action_invoked(id: u32, key: String) {
    let Some(conn) = DBUS_CONN.get() else { return; };
    let _ = conn.emit_signal(
        None::<&str>,
        FDO_PATH,
        "org.freedesktop.Notifications",
        "ActionInvoked",
        &(id, key),
    );
}
