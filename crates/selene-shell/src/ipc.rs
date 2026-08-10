//! cava-bg IPC -- UNIX socket listener that accepts JSON palette
//! updates from `cava-bg` (or any external source) and pushes them
//! into the QML `Tokens` singleton through the cxx-qt queue.
//!
//! The socket lives at `~/.local/share/selene/ipc.sock` and expects
//! one JSON line per update in the same shape the Palette engine uses:
//! `{"accent":"#...","surface":"#...","background":"#...","text_color":"#..."}`.

use core::pin::Pin;
use cxx_qt::Threading;
use cxx_qt_lib::QString;
use std::io::{BufRead, BufReader};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(QString, accent)]
        #[qproperty(QString, surface)]
        #[qproperty(QString, background)]
        #[qproperty(QString, text_color)]
        #[qproperty(bool, listening)]
        #[qproperty(QString, status)]
        type IpcPalette = super::IpcPaletteRust;

        #[qinvokable]
        fn start_ipc(self: Pin<&mut Self>);
    }

    impl cxx_qt::Threading for IpcPalette {}
}

#[derive(Default)]
pub struct IpcPaletteRust {
    accent: QString,
    surface: QString,
    background: QString,
    text_color: QString,
    listening: bool,
    status: QString,
}

static IPC_STARTED: AtomicBool = AtomicBool::new(false);

fn ipc_socket_path() -> PathBuf {
    let home = std::env::var_os("HOME")
        .map(|h| h.to_string_lossy().to_string())
        .unwrap_or_else(|| "/tmp".to_string());
    PathBuf::from(format!("{home}/.local/share/selene/ipc.sock"))
}

fn handle_stream(stream: UnixStream, qt: cxx_qt::CxxQtThread<qobject::IpcPalette>) {
    let reader = BufReader::new(stream);
    for line in reader.lines() {
        let Ok(line) = line else { break; };
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let Ok(obj): Result<serde_json::Value, _> = serde_json::from_str(line) else {
            continue;
        };
        let accent = obj
            .get("accent")
            .and_then(|v| v.as_str())
            .unwrap_or("#a78bfa")
            .to_string();
        let surface = obj
            .get("surface")
            .and_then(|v| v.as_str())
            .unwrap_or("#16181c")
            .to_string();
        let background = obj
            .get("background")
            .and_then(|v| v.as_str())
            .unwrap_or("#0e0f12")
            .to_string();
        let text_color = obj
            .get("text_color")
            .and_then(|v| v.as_str())
            .unwrap_or("#e6e6ea")
            .to_string();

        let _ = qt.queue(move |mut ipc| {
            ipc.as_mut().set_accent(QString::from(accent.as_str()));
            ipc.as_mut().set_surface(QString::from(surface.as_str()));
            ipc.as_mut().set_background(QString::from(background.as_str()));
            ipc.as_mut()
                .set_text_color(QString::from(text_color.as_str()));
        });
    }
}

impl qobject::IpcPalette {
    pub fn start_ipc(self: Pin<&mut Self>) {
        if IPC_STARTED.swap(true, Ordering::SeqCst) {
            return;
        }
        let path = ipc_socket_path();
        if let Some(parent) = path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        let _ = std::fs::remove_file(&path); // clean stale socket
        let listener = match UnixListener::bind(&path) {
            Ok(l) => l,
            Err(err) => {
                let mut this = self;
                this.as_mut()
                    .set_status(QString::from(format!("ipc bind: {err}")));
                return;
            }
        };
        let qt: cxx_qt::CxxQtThread<qobject::IpcPalette> = self.as_ref().qt_thread();
        let mut this = self;
        this.as_mut().set_listening(true);
        this.as_mut()
            .set_status(QString::from(format!("ipc on {}", path.display())));
        std::thread::Builder::new()
            .name("selene-ipc".into())
            .spawn(move || {
                for stream in listener.incoming() {
                    match stream {
                        Ok(s) => {
                            let qt2 = qt.clone();
                            std::thread::spawn(move || handle_stream(s, qt2));
                        }
                        Err(_) => break,
                    }
                }
            })
            .expect("selene: failed to spawn ipc thread");
    }
}
