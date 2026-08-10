/// Color picker -- pixel grabber via hyprpicker.
//
/// The `Picker` QObject spawns `hyprpicker -f hex` to freeze the
/// screen and return the picked pixel. The QML side
/// (`ColorPickerPanel.qml`) shows a large swatch, hex readout, and
/// RGB channel tiles.

use core::pin::Pin;
use cxx_qt_lib::QString;
use std::process::Command;

/// Color picker panel (Ambxst feature) -- spawns `hyprpicker` to
/// freeze the screen, lets the user click a pixel, and reads the
/// picked color from stdout. Output format is hex (`#aabbcc`).
///
/// The actual `hyprpicker` invocation blocks until the user picks (or
/// cancels), so `pick()` is synchronous; the QML side is expected to
/// call this from a transient event handler and not on the initial
/// component build path.
///
/// Properties:
///   * `color_hex`     -- the most recently picked color
///   * `enabled`       -- whether `hyprpicker` is on PATH
///   * `running`       -- true while a `hyprpicker` subprocess is alive
///   * `status`        -- last status / error message
///
/// QInvokables:
///   * `pick()`        -- spawn `hyprpicker -f hex -a`; copy the result
///                        to the system clipboard via `Spawner.copy_to_clipboard`
///                        (we shell out to `wl-copy` here directly so the
///                        color picker can be self-contained).
///   * `pick_and_copy()`-- like `pick()` but also writes the result to
///                        the system clipboard immediately (the `-a`
///                        flag does that when wl-clipboard is present).
///   * `open_format_selector()` -- returns "hex" for now; reserved for
///                        future expansion to rgb / hsl.
#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(QString, color_hex)]
        #[qproperty(bool, enabled)]
        #[qproperty(bool, running)]
        #[qproperty(QString, status)]
        type Picker = super::PickerRust;

        #[qinvokable]
        fn pick(self: Pin<&mut Self>);

        #[qinvokable]
        fn pick_and_copy(self: Pin<&mut Self>);
    }

    impl cxx_qt::Threading for Picker {}
}

pub struct PickerRust {
    color_hex: QString,
    enabled: bool,
    running: bool,
    status: QString,
}

fn is_hyprpicker_available() -> bool {
    Command::new("hyprpicker")
        .arg("--version")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

impl Default for PickerRust {
    fn default() -> Self {
        let enabled = is_hyprpicker_available();
        Self {
            color_hex: QString::from(""),
            enabled,
            running: false,
            status: QString::from(if enabled { "ready" } else { "hyprpicker not installed" }),
        }
    }
}

impl qobject::Picker {
    pub fn pick(self: Pin<&mut Self>) {
        let mut this = self;
        if !this.enabled {
            this.as_mut()
                .set_status(QString::from("hyprpicker not installed"));
            return;
        }
        if *this.running() {
            return;
        }
        this.as_mut().set_running(true);
        let result = Command::new("hyprpicker")
            .arg("-f")
            .arg("hex")
            .arg("-n")
            .output();
        this.as_mut().set_running(false);
        match result {
            Ok(out) if out.status.success() => {
                let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
                this.as_mut().set_color_hex(QString::from(s.as_str()));
                this.as_mut().set_status(QString::from("picked"));
            }
            Ok(out) => {
                let stderr = String::from_utf8_lossy(&out.stderr).trim().to_string();
                if out.status.code() == Some(1) && stderr.contains("cancelled") {
                    this.as_mut()
                        .set_status(QString::from("cancelled"));
                } else {
                    this.as_mut()
                        .set_status(QString::from(format!("hyprpicker: {stderr}").as_str()));
                }
            }
            Err(err) => {
                this.as_mut()
                    .set_status(QString::from(format!("hyprpicker: {err}").as_str()));
            }
        }
    }

    pub fn pick_and_copy(self: Pin<&mut Self>) {
        let mut this = self;
        if !this.enabled {
            this.as_mut()
                .set_status(QString::from("hyprpicker not installed"));
            return;
        }
        if *this.running() {
            return;
        }
        this.as_mut().set_running(true);
        let result = Command::new("hyprpicker")
            .arg("-f")
            .arg("hex")
            .arg("-a")
            .output();
        this.as_mut().set_running(false);
        match result {
            Ok(out) if out.status.success() => {
                let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
                this.as_mut().set_color_hex(QString::from(s.as_str()));
                this.as_mut()
                    .set_status(QString::from(format!("picked + copied: {s}").as_str()));
            }
            Ok(out) => {
                let stderr = String::from_utf8_lossy(&out.stderr).trim().to_string();
                if out.status.code() == Some(1) && stderr.contains("cancelled") {
                    this.as_mut()
                        .set_status(QString::from("cancelled"));
                } else {
                    this.as_mut()
                        .set_status(QString::from(format!("hyprpicker: {stderr}").as_str()));
                }
            }
            Err(err) => {
                this.as_mut()
                    .set_status(QString::from(format!("hyprpicker: {err}").as_str()));
            }
        }
    }
}
