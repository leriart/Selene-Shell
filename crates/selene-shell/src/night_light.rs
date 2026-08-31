/// Night light -- wlsunset wrapper.
//
/// The `NightLight` QObject toggles a `wlsunset` subprocess that warms
/// the display color temperature at night (NothingLess NightMode port).
/// State is tracked by the subprocess itself: `toggle` spawns wlsunset
/// detached, `off` kills it, `refresh` probes with pgrep so the QML
/// chip stays honest after a shell reload.

use core::pin::Pin;
use cxx_qt_lib::QString;
use std::process::{Command, Stdio};

/// Warm-color overlay toggle (night light / blue-light filter).
#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(bool, active)]
        #[qproperty(bool, available)]
        #[qproperty(i32, temperature)]
        #[qproperty(QString, status)]
        type NightLight = super::NightLightRust;

        #[qinvokable]
        fn refresh(self: Pin<&mut Self>);

        #[qinvokable]
        fn toggle(self: Pin<&mut Self>);

        #[qinvokable]
        fn on(self: Pin<&mut Self>);

        #[qinvokable]
        fn off(self: Pin<&mut Self>);

        #[qinvokable]
        fn apply_temperature(self: Pin<&mut Self>, kelvin: i32);
    }
}

pub struct NightLightRust {
    active: bool,
    available: bool,
    temperature: i32,
    status: QString,
}

impl Default for NightLightRust {
    fn default() -> Self {
        Self {
            active: false,
            available: false,
            temperature: 3400,
            status: QString::from(""),
        }
    }
}

/// True when wlsunset is installed (checked once per refresh).
fn wlsunset_available() -> bool {
    Command::new("which")
        .arg("wlsunset")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

/// True when a wlsunset process is currently running.
fn wlsunset_running() -> bool {
    Command::new("pgrep")
        .args(["-x", "wlsunset"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn stop_wlsunset() {
    let _ = Command::new("pkill")
        .args(["-x", "wlsunset"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

fn start_wlsunset(temperature: i32) -> Result<(), String> {
    // wlsunset -T <day> -t <night>: we only care about the night value;
    // keep the day temperature neutral so toggling off isn't required
    // during daylight.
    Command::new("wlsunset")
        .args(["-T", "6500", "-t", &temperature.to_string()])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map(|_| ())
        .map_err(|e| format!("wlsunset: {e}"))
}

impl qobject::NightLight {
    pub fn refresh(self: Pin<&mut Self>) {
        let running = wlsunset_running();
        let available = wlsunset_available();
        let mut this = self;
        this.as_mut().set_active(running);
        this.as_mut().set_available(available);
        let status = if !available {
            "wlsunset not installed"
        } else if running {
            "night light on"
        } else {
            "night light off"
        };
        this.as_mut().set_status(QString::from(status));
    }

    pub fn on(self: Pin<&mut Self>) {
        let temperature = *self.temperature();
        let mut this = self;
        match start_wlsunset(temperature) {
            Ok(()) => {
                this.as_mut().set_active(true);
                this.as_mut().set_status(QString::from("night light on"));
            }
            Err(err) => {
                this.as_mut().set_status(QString::from(err.as_str()));
            }
        }
    }

    pub fn off(self: Pin<&mut Self>) {
        stop_wlsunset();
        let mut this = self;
        this.as_mut().set_active(false);
        this.as_mut().set_status(QString::from("night light off"));
    }

    pub fn toggle(self: Pin<&mut Self>) {
        if wlsunset_running() {
            self.off();
        } else {
            self.on();
        }
    }

    pub fn apply_temperature(self: Pin<&mut Self>, kelvin: i32) {
        let clamped = kelvin.clamp(1000, 6500);
        let was_active = *self.active();
        let mut this = self;
        this.as_mut().set_temperature(clamped);
        // Live-apply: restart the filter at the new temperature.
        if was_active {
            stop_wlsunset();
            let _ = start_wlsunset(clamped);
        }
    }
}
