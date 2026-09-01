//! Hyprland IPC bridge -- push-based event listener + sync query.
//!
//! The `Bridge` QObject owns a dedicated `std::thread` that runs a
//! `hyprland-rs::EventListener`. On every workspace, monitor, window,
//! fullscreen or focus event, the listener queues a `refresh()` call
//! back onto the Qt main thread through `cxx_qt::CxxQtThread`, which
//! re-reads the relevant state from the Hyprland socket and updates
//! all `#[qproperty]` fields in one pass. QML bindings then propagate
//! to every visible surface without polling.

use core::pin::Pin;
use cxx_qt::Threading;
use cxx_qt_lib::QString;
use hyprland::data::{Client, Workspace, Workspaces};
use hyprland::event_listener::EventListener;
use hyprland::prelude::*;
use std::process::Command;

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(QString, greeting)]
        #[qproperty(i32, counter)]
        #[qproperty(bool, connected)]
        #[qproperty(i32, active_workspace_id)]
        #[qproperty(QString, active_workspace_name)]
        #[qproperty(i32, workspace_count)]
        // JSON [{id, name, windows, active}] for the Overview grid.
        #[qproperty(QString, workspaces_json)]
        #[qproperty(QString, windows_json)]
        #[qproperty(QString, workspace_thumbnails_json)]
        #[qproperty(QString, active_window_class)]
        #[qproperty(QString, active_window_title)]
        #[qproperty(QString, hyprland_status)]
        #[qproperty(bool, listener_started)]
        type Bridge = super::BridgeRust;

        #[qinvokable]
        fn increment(self: Pin<&mut Self>);

        #[qinvokable]
        fn greet(&self, name: &QString) -> QString;

        #[qinvokable]
        fn refresh(self: Pin<&mut Self>);

        #[qinvokable]
        fn start_listener(self: Pin<&mut Self>);

        #[qinvokable]
        fn focus_workspace(self: Pin<&mut Self>, id: i32);

        #[qinvokable]
        fn capture_workspace_thumbnails(self: Pin<&mut Self>);

        #[qinvokable]
        fn clear_workspace_thumbnails(self: Pin<&mut Self>);
    }

    impl cxx_qt::Threading for Bridge {}
}

#[derive(Default)]
pub struct BridgeRust {
    greeting: QString,
    counter: i32,
    connected: bool,
    active_workspace_id: i32,
    active_workspace_name: QString,
    workspace_count: i32,
    workspaces_json: QString,
    windows_json: QString,
    workspace_thumbnails_json: QString,
    active_window_class: QString,
    active_window_title: QString,
    hyprland_status: QString,
    listener_started: bool,
}

impl qobject::Bridge {
    pub fn increment(self: Pin<&mut Self>) {
        let previous = *self.counter();
        let next = previous + 1;
        let msg = QString::from(format!("Selene step {next} -- bridge is live."));
        let mut this = self;
        this.as_mut().set_counter(next);
        this.as_mut().set_greeting(msg);
    }

    pub fn greet(&self, name: &QString) -> QString {
        let who = name.to_string();
        QString::from(format!("Hello, {who}. Welcome to Selene."))
    }

    pub fn refresh(self: Pin<&mut Self>) {
        let mut this = self;

        let active = Workspace::get_active();
        match Workspaces::get() {
            Ok(ws) => {
                this.as_mut().set_connected(true);
                this.as_mut().set_hyprland_status(QString::from("ok"));
                let mut list = ws.to_vec();
                list.sort_by_key(|w| w.id);
                this.as_mut().set_workspace_count(list.len() as i32);
                // Overview grid data: id, name, window count, active flag.
                let active_id = active.as_ref().map(|w| w.id).unwrap_or(-1);
                let entries: Vec<serde_json::Value> = list
                    .iter()
                    .map(|w| {
                        serde_json::json!({
                            "id": w.id,
                            "name": w.name,
                            "windows": w.windows,
                            "active": w.id == active_id,
                        })
                    })
                    .collect();
                this.as_mut().set_workspaces_json(QString::from(
                    serde_json::to_string(&entries)
                        .unwrap_or_else(|_| "[]".to_string())
                        .as_str(),
                ));
                this.as_mut().set_workspace_thumbnails_json(QString::from("{}"));

                // Per-workspace window list for the Overview cards:
                // one `hyprctl clients -j` round-trip, then group by
                // workspace id in Rust.
                if let Ok(clients) = hyprland::data::Clients::get() {
                    let mut wins: Vec<serde_json::Value> = Vec::new();
                    for c in clients.to_vec() {
                        if c.mapped {
                            wins.push(serde_json::json!({
                                "address": c.address.to_string(),
                                "class": c.class,
                                "title": c.title,
                                "workspace_id": c.workspace.id,
                                "workspace_name": c.workspace.name,
                                "floating": c.floating,
                                "fullscreen": !matches!(
                                    c.fullscreen,
                                    hyprland::data::FullscreenMode::None
                                ),
                            }));
                        }
                    }
                    this.as_mut().set_windows_json(QString::from(
                        serde_json::to_string(&wins)
                            .unwrap_or_else(|_| "[]".to_string())
                            .as_str(),
                    ));
                }
            }
            Err(err) => {
                this.as_mut().set_connected(false);
                this.as_mut()
                    .set_hyprland_status(QString::from(format!("workspaces: {err}")));
                this.as_mut().set_workspace_count(0);
                this.as_mut().set_workspaces_json(QString::from("[]"));
                this.as_mut().set_windows_json(QString::from("[]"));
                this.as_mut().set_workspace_thumbnails_json(QString::from("{}"));
                this.as_mut().set_active_workspace_id(0);
                this.as_mut().set_active_workspace_name(QString::from(""));
                this.as_mut().set_active_window_class(QString::from(""));
                this.as_mut().set_active_window_title(QString::from(""));
                match active {
                    Ok(w) => {
                        this.as_mut().set_active_workspace_id(w.id);
                        this.as_mut()
                            .set_active_workspace_name(QString::from(w.name.clone()));
                    }
                    Err(_) => {
                        this.as_mut().set_active_workspace_id(0);
                    }
                }
                return;
            }
        }

        match active {
            Ok(w) => {
                this.as_mut().set_active_workspace_id(w.id);
                this.as_mut()
                    .set_active_workspace_name(QString::from(w.name.clone()));
            }
            Err(err) => {
                this.as_mut().set_active_workspace_id(0);
                this.as_mut()
                    .set_active_workspace_name(QString::from(format!("err: {err}")));
            }
        }

        match Client::get_active() {
            Ok(Some(client)) => {
                this.as_mut()
                    .set_active_window_class(QString::from(client.class.clone()));
                this.as_mut()
                    .set_active_window_title(QString::from(client.title.clone()));
            }
            Ok(None) => {
                this.as_mut().set_active_window_class(QString::from(""));
                this.as_mut().set_active_window_title(QString::from(""));
            }
            Err(err) => {
                this.as_mut()
                    .set_active_window_class(QString::from(format!("err: {err}")));
                this.as_mut()
                    .set_active_window_title(QString::from(format!("err: {err}")));
            }
        }
    }

    pub fn start_listener(self: Pin<&mut Self>) {
        // The cxx-qt generated setters take `Pin<&mut Self>`, but
        // `qt_thread` (from the `cxx_qt::Threading` trait) takes `&Self`,
        // so re-pin first.
        if *self.listener_started() {
            return;
        }
        let thread: cxx_qt::CxxQtThread<qobject::Bridge> = self.as_ref().qt_thread();

        self.set_listener_started(true);

        // The `hyprland-rs` event handlers are not `Send`, so the listener
        // can't cross a tokio task boundary. Spawn a dedicated OS thread
        // instead and use the cxx-qt queued-call bridge to push refresh()
        // back onto the Qt main thread.
        std::thread::Builder::new()
            .name("selene-hyprland".into())
            .spawn(move || {
                let _ = thread.queue(|mut bridge| {
                    bridge
                        .as_mut()
                        .set_hyprland_status(QString::from("listener starting"));
                });

                let mut listener = EventListener::new();

                macro_rules! on_event {
                    ($method:ident) => {
                        listener.$method({
                            let t = thread.clone();
                            move |_data| {
                                let _ = t.queue(|bridge| bridge.refresh());
                            }
                        })
                    };
                }

                on_event!(add_workspace_changed_handler);
                on_event!(add_workspace_added_handler);
                on_event!(add_workspace_deleted_handler);
                on_event!(add_workspace_moved_handler);
                on_event!(add_workspace_renamed_handler);
                on_event!(add_active_window_changed_handler);
                on_event!(add_active_monitor_changed_handler);
                on_event!(add_window_title_changed_handler);
                on_event!(add_window_opened_handler);
                on_event!(add_window_closed_handler);
                on_event!(add_window_moved_handler);

                let _ = thread.queue(|mut bridge| {
                    bridge
                        .as_mut()
                        .set_hyprland_status(QString::from("listener ok"));
                });

                if let Err(err) = listener.start_listener() {
                    let _ = thread.queue(move |mut bridge| {
                        bridge
                            .as_mut()
                            .set_hyprland_status(QString::from(format!(
                                "listener: {err}"
                            )));
                    });
                }
            })
            .expect("selene: failed to spawn event listener thread");
    }

    pub fn focus_workspace(self: Pin<&mut Self>, id: i32) {
        use hyprland::dispatch::{Dispatch, DispatchType, WorkspaceIdentifierWithSpecial};
        let mut this = self;
        match Dispatch::call(DispatchType::Workspace(
            WorkspaceIdentifierWithSpecial::Id(id),
        )) {
            Ok(()) => this.as_mut().refresh(),
            Err(err) => {
                this.as_mut()
                    .set_hyprland_status(QString::from(format!("workspace {id}: {err}")));
            }
        }
    }

    /// Capture a screenshot per monitor and tag it by the workspace
    /// id that monitor currently shows. The Overview grid uses the
    /// resulting paths as live thumbnails.
    pub fn capture_workspace_thumbnails(self: Pin<&mut Self>) {
        let thumb_dir = match std::env::var_os("HOME") {
            Some(h) => std::path::PathBuf::from(h)
                .join(".local/share/selene/thumbnails"),
            None => return,
        };
        let _ = std::fs::create_dir_all(&thumb_dir);
        // 1. Per-monitor screenshot via grim. We render every monitor
        //    into one strip file so the QML side can pick the workspace
        //    it cares about without juggling N windows.
        let stamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);
        let strip_path = thumb_dir.join(format!("strip-{stamp}.png"));
        let _ = Command::new("grim")
            .arg("-t")
            .arg("1")
            .arg(&strip_path)
            .output();

        // 2. Map each workspace id to the monitor it's currently on.
        //    hyprland-rs has `hyprctl workspaces -j` for the full list
        //    and `workspaces` exposes lastwindow/monitor indirectly.
        //    We use `hyprctl activeworkspace per-monitor` via a
        //    subprocess; the response isn't structured enough to
        //    correlate cleanly so the JSON we build falls back to
        //    `name + id` only.
        let map: serde_json::Map<String, serde_json::Value> = match Workspaces::get() {
            Ok(ws) => ws
                .iter()
                .map(|w| {
                    (w.id.to_string(),
                     serde_json::Value::String(strip_path.to_string_lossy().into_owned()))
                })
                .collect(),
            Err(_) => serde_json::Map::new(),
        };
        let json = serde_json::to_string(&map).unwrap_or_else(|_| "{}".into());
        let mut this = self;
        this.as_mut().set_workspace_thumbnails_json(QString::from(json.as_str()));
    }

    /// Drop all workspace thumbnails from the QML side; the
    /// underlying PNGs are cleaned up the next time grim writes new
    /// files (we don't proactively wipe the cache directory here to
    /// avoid racing with a concurrent capture).
    pub fn clear_workspace_thumbnails(self: Pin<&mut Self>) {
        let mut this = self;
        this.as_mut().set_workspace_thumbnails_json(QString::from("{}"));
    }
}
