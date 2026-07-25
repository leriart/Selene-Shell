use core::pin::Pin;
use cxx_qt::Threading;
use cxx_qt_lib::QString;
use hyprland::data::{Client, Workspace, Workspaces};
use hyprland::event_listener::EventListener;
use hyprland::prelude::*;

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
                this.as_mut().set_workspace_count(ws.to_vec().len() as i32);
            }
            Err(err) => {
                this.as_mut().set_connected(false);
                this.as_mut()
                    .set_hyprland_status(QString::from(format!("workspaces: {err}")));
                this.as_mut().set_workspace_count(0);
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
}
