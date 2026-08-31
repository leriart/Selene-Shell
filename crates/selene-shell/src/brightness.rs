/// Backlight control -- brightnessctl wrapper.
//
/// The `Brightness` QObject reads the current / max backlight level
/// through `brightnessctl` and exposes a 0.0-1.0 fraction. Setting
/// runs `brightnessctl set` and re-reads to stay honest. The QML
/// side (Dashboard controls tab) renders a slider.

use core::pin::Pin;
use cxx_qt_lib::QString;
use std::process::Command;

/// Backlight mirror (laptop screens; `available` is false on desktops).
#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(f64, brightness)]
        #[qproperty(i32, max_brightness)]
        #[qproperty(bool, available)]
        #[qproperty(QString, status)]
        type Brightness = super::BrightnessRust;

        #[qinvokable]
        fn refresh(self: Pin<&mut Self>);

        #[qinvokable]
        fn apply_brightness(self: Pin<&mut Self>, value: f64);

        #[qinvokable]
        fn increase(self: Pin<&mut Self>);

        #[qinvokable]
        fn decrease(self: Pin<&mut Self>);
    }
}

#[derive(Default)]
pub struct BrightnessRust {
    brightness: f64,
    max_brightness: i32,
    available: bool,
    status: QString,
}

fn run_brightnessctl(args: &[&str]) -> Option<String> {
    let out = Command::new("brightnessctl").args(args).output().ok()?;
    if !out.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

/// (current, max) raw device counters.
fn read_levels() -> Option<(i64, i64)> {
    let cur = run_brightnessctl(&["get"])?.parse::<i64>().ok()?;
    let max = run_brightnessctl(&["max"])?.parse::<i64>().ok()?;
    if max <= 0 {
        return None;
    }
    Some((cur, max))
}

impl qobject::Brightness {
    pub fn refresh(self: Pin<&mut Self>) {
        let mut this = self;
        match read_levels() {
            Some((cur, max)) => {
                this.as_mut()
                    .set_brightness((cur as f64 / max as f64).clamp(0.0, 1.0));
                this.as_mut().set_max_brightness(max as i32);
                this.as_mut().set_available(true);
                this.as_mut().set_status(QString::from("ok"));
            }
            None => {
                this.as_mut().set_available(false);
                this.as_mut()
                    .set_status(QString::from("brightnessctl unavailable"));
            }
        }
    }

    pub fn apply_brightness(self: Pin<&mut Self>, value: f64) {
        let fraction = value.clamp(0.0, 1.0);
        // Keep a 1% floor so the panel never goes fully dark.
        let percent = ((fraction * 100.0).round() as i64).max(1);
        let _ = run_brightnessctl(&["set", &format!("{percent}%")]);
        self.refresh();
    }

    pub fn increase(self: Pin<&mut Self>) {
        let _ = run_brightnessctl(&["set", "+5%"]);
        self.refresh();
    }

    pub fn decrease(self: Pin<&mut Self>) {
        let _ = run_brightnessctl(&["set", "5%-"]);
        self.refresh();
    }
}
