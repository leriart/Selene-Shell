/// Screenshots + screen recording -- grim/slurp + wf-recorder wrappers.
//
/// The `Screenshot` QObject captures the whole output, a slurp-drawn
/// region, or the active Hyprland window into
/// ~/Pictures/Screenshots/ with timestamped names. Region / window
/// grabs block on slurp / hyprctl, so every capture runs on its own
/// thread and reports back through the cxx-qt queued bridge.
///
/// Recording (NothingLess port) spawns wf-recorder detached into
/// ~/Videos/Recordings/; `record_stop` SIGINTs it so the mp4 finalizes
/// cleanly. State is probed with pgrep so the QML chip stays honest.

use core::pin::Pin;
use cxx_qt::Threading;
use cxx_qt_lib::QString;
use std::path::PathBuf;
use std::process::{Command, Stdio};

/// grim/slurp screen capture + wf-recorder screen recording.
#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(QString, last_path)]
        #[qproperty(QString, screenshots_dir)]
        #[qproperty(bool, capturing)]
        #[qproperty(bool, recording)]
        #[qproperty(bool, recorder_available)]
        #[qproperty(QString, status)]
        type Screenshot = super::ScreenshotRust;

        #[qinvokable]
        fn capture_screen(self: Pin<&mut Self>);

        #[qinvokable]
        fn capture_region(self: Pin<&mut Self>);

        #[qinvokable]
        fn capture_window(self: Pin<&mut Self>);

        #[qinvokable]
        fn record_screen(self: Pin<&mut Self>);

        #[qinvokable]
        fn record_region(self: Pin<&mut Self>);

        #[qinvokable]
        fn record_stop(self: Pin<&mut Self>);

        #[qinvokable]
        fn refresh(self: Pin<&mut Self>);
    }

    impl cxx_qt::Threading for Screenshot {}
}

#[derive(Default)]
pub struct ScreenshotRust {
    last_path: QString,
    screenshots_dir: QString,
    capturing: bool,
    recording: bool,
    recorder_available: bool,
    status: QString,
}

fn screenshots_dir() -> PathBuf {
    let home = std::env::var_os("HOME")
        .map(|h| h.to_string_lossy().to_string())
        .unwrap_or_else(|| "/tmp".to_string());
    PathBuf::from(format!("{home}/Pictures/Screenshots"))
}

fn recordings_dir() -> PathBuf {
    let home = std::env::var_os("HOME")
        .map(|h| h.to_string_lossy().to_string())
        .unwrap_or_else(|| "/tmp".to_string());
    PathBuf::from(format!("{home}/Videos/Recordings"))
}

/// Timestamped target path, e.g. screenshot-20260828-134502.png.
/// Uses `date` like island.rs so we stay chrono-free.
fn timestamp() -> String {
    Command::new("date")
        .arg("+%Y%m%d-%H%M%S")
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_else(|| "unknown".to_string())
}

fn target_path() -> PathBuf {
    screenshots_dir().join(format!("screenshot-{}.png", timestamp()))
}

fn recorder_available() -> bool {
    Command::new("which")
        .arg("wf-recorder")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn recorder_running() -> bool {
    Command::new("pgrep")
        .args(["-x", "wf-recorder"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

/// Spawn wf-recorder (optionally on a slurp region) detached.
fn start_recorder(region: Option<&str>) -> Result<PathBuf, String> {
    if !recorder_available() {
        return Err("wf-recorder not installed".to_string());
    }
    let dir = recordings_dir();
    std::fs::create_dir_all(&dir).map_err(|e| format!("mkdir: {e}"))?;
    let path = dir.join(format!("recording-{}.mp4", timestamp()));
    let mut cmd = Command::new("wf-recorder");
    if let Some(region) = region {
        cmd.args(["-g", region]);
    }
    cmd.arg("-f")
        .arg(&path)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    cmd.spawn()
        .map(|_| path)
        .map_err(|e| format!("wf-recorder: {e}"))
}

/// SIGINT every wf-recorder so the mp4 trailer is written.
fn stop_recorder() {
    let _ = Command::new("pkill")
        .args(["-INT", "-x", "wf-recorder"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

/// slurp region string ("x,y wxh") or a Vec<u8> stderr on failure.
fn slurp_region() -> Result<String, Vec<u8>> {
    let out = Command::new("slurp").output().map_err(|e| {
        format!("slurp: {e}").into_bytes()
    })?;
    if !out.status.success() {
        return Err(out.stderr);
    }
    let region = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if region.is_empty() {
        return Err(b"slurp: empty selection".to_vec());
    }
    Ok(region)
}

/// Active window geometry via `hyprctl activewindow -j` -> "x,y wxh".
fn active_window_region() -> Result<String, Vec<u8>> {
    let out = Command::new("hyprctl")
        .args(["activewindow", "-j"])
        .output()
        .map_err(|e| format!("hyprctl: {e}").into_bytes())?;
    if !out.status.success() {
        return Err(out.stderr);
    }
    let value: serde_json::Value = serde_json::from_slice(&out.stdout)
        .map_err(|e| format!("hyprctl json: {e}").into_bytes())?;
    let at = value.get("at").and_then(|v| v.as_array());
    let size = value.get("size").and_then(|v| v.as_array());
    match (at, size) {
        (Some(at), Some(size)) if at.len() == 2 && size.len() == 2 => {
            let x = at[0].as_i64().unwrap_or(0);
            let y = at[1].as_i64().unwrap_or(0);
            let w = size[0].as_i64().unwrap_or(0);
            let h = size[1].as_i64().unwrap_or(0);
            if w <= 0 || h <= 0 {
                return Err(b"hyprctl: window has no size".to_vec());
            }
            Ok(format!("{x},{y} {w}x{h}"))
        }
        _ => Err(b"hyprctl: no active window".to_vec()),
    }
}

/// Run grim (optionally with a -g region) into `path`.
fn run_grim(region: Option<&str>, path: &PathBuf) -> Result<(), Vec<u8>> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)
            .map_err(|e| format!("mkdir: {e}").into_bytes())?;
    }
    let mut cmd = Command::new("grim");
    if let Some(region) = region {
        cmd.args(["-g", region]);
    }
    let out = cmd
        .arg(path)
        .output()
        .map_err(|e| format!("grim: {e}").into_bytes())?;
    if !out.status.success() {
        return Err(out.stderr);
    }
    Ok(())
}

#[derive(Clone, Copy)]
enum Mode {
    Screen,
    Region,
    Window,
}

fn capture_main(mode: Mode, qt: cxx_qt::CxxQtThread<qobject::Screenshot>) {
    let path = target_path();
    let result = match mode {
        Mode::Screen => run_grim(None, &path),
        Mode::Region => slurp_region().and_then(|r| run_grim(Some(&r), &path)),
        Mode::Window => active_window_region().and_then(|r| run_grim(Some(&r), &path)),
    };
    let _ = qt.queue(move |mut this| {
        this.as_mut().set_capturing(false);
        match result {
            Ok(()) => {
                let shown = path.to_string_lossy().to_string();
                this.as_mut().set_last_path(QString::from(shown.as_str()));
                this.as_mut()
                    .set_status(QString::from(format!("saved {shown}")));
            }
            Err(stderr) => {
                let msg = String::from_utf8_lossy(&stderr).trim().to_string();
                let msg = if msg.is_empty() {
                    "capture failed".to_string()
                } else {
                    msg
                };
                this.as_mut().set_status(QString::from(msg.as_str()));
            }
        }
    });
}

impl qobject::Screenshot {
    fn dispatch(self: Pin<&mut Self>, mode: Mode, label: &'static str) {
        if *self.capturing() {
            return;
        }
        let qt: cxx_qt::CxxQtThread<qobject::Screenshot> = self.as_ref().qt_thread();
        std::thread::Builder::new()
            .name("selene-screenshot".into())
            .spawn(move || capture_main(mode, qt))
            .expect("selene: failed to spawn screenshot thread");
        let mut this = self;
        this.as_mut().set_capturing(true);
        this.as_mut()
            .set_status(QString::from(format!("capturing {label}...")));
        this.as_mut().set_screenshots_dir(QString::from(
            screenshots_dir().to_string_lossy().as_ref(),
        ));
    }

    pub fn capture_screen(self: Pin<&mut Self>) {
        self.dispatch(Mode::Screen, "screen");
    }

    pub fn capture_region(self: Pin<&mut Self>) {
        self.dispatch(Mode::Region, "region");
    }

    pub fn capture_window(self: Pin<&mut Self>) {
        self.dispatch(Mode::Window, "window");
    }

    pub fn refresh(self: Pin<&mut Self>) {
        let recording = recorder_running();
        let available = recorder_available();
        let mut this = self;
        this.as_mut().set_recording(recording);
        this.as_mut().set_recorder_available(available);
    }

    pub fn record_screen(self: Pin<&mut Self>) {
        if recorder_running() {
            // Toggle semantics: a second click stops the recording.
            self.record_stop();
            return;
        }
        let mut this = self;
        match start_recorder(None) {
            Ok(path) => {
                let shown = path.to_string_lossy().to_string();
                this.as_mut().set_recording(true);
                this.as_mut()
                    .set_status(QString::from(format!("recording -> {shown}")));
            }
            Err(err) => {
                this.as_mut().set_status(QString::from(err.as_str()));
            }
        }
    }

    pub fn record_region(self: Pin<&mut Self>) {
        if recorder_running() {
            self.record_stop();
            return;
        }
        // slurp blocks until the user draws the region; run it on a
        // worker so the shell doesn't freeze mid-selection.
        let qt: cxx_qt::CxxQtThread<qobject::Screenshot> = self.as_ref().qt_thread();
        let spawned = std::thread::Builder::new()
            .name("selene-record".into())
            .spawn(move || {
                let result = slurp_region()
                    .map_err(|e| String::from_utf8_lossy(&e).trim().to_string())
                    .and_then(|r| start_recorder(Some(&r)));
                let _ = qt.queue(move |mut this| match result {
                    Ok(path) => {
                        let shown = path.to_string_lossy().to_string();
                        this.as_mut().set_recording(true);
                        this.as_mut()
                            .set_status(QString::from(format!("recording -> {shown}")));
                    }
                    Err(err) => {
                        this.as_mut().set_status(QString::from(err.as_str()));
                    }
                });
            });
        if let Err(err) = spawned {
            let mut this = self;
            this.as_mut()
                .set_status(QString::from(format!("record thread: {err}")));
        }
    }

    pub fn record_stop(self: Pin<&mut Self>) {
        stop_recorder();
        let mut this = self;
        this.as_mut().set_recording(false);
        this.as_mut().set_status(QString::from("recording saved"));
    }
}
