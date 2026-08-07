use core::pin::Pin;
use cxx_qt_lib::QString;
use std::process::Command;

/// Audio control via pactl. Mirrors the small surface typically exposed by
/// a status bar / quick-settings panel: a single sink's volume + mute, plus
/// the list of available sinks for the user to choose from.
#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(i32, volume_percent)]
        #[qproperty(bool, muted)]
        #[qproperty(QString, default_sink_name)]
        #[qproperty(QString, sinks_json)]
        #[qproperty(bool, available)]
        #[qproperty(QString, status)]
        type Audio = super::AudioRust;

        #[qinvokable]
        fn refresh(self: Pin<&mut Self>);

        #[qinvokable]
        fn set_volume(self: Pin<&mut Self>, percent: i32);

        #[qinvokable]
        fn bump(self: Pin<&mut Self>, delta_percent: i32);

        #[qinvokable]
        fn toggle_mute(self: Pin<&mut Self>);

        #[qinvokable]
        fn set_mute(self: Pin<&mut Self>, muted: bool);

        #[qinvokable]
        fn set_default_sink(self: Pin<&mut Self>, name: &QString);
    }
}

#[derive(Default)]
pub struct AudioRust {
    volume_percent: i32,
    muted: bool,
    default_sink_name: QString,
    sinks_json: QString,
    available: bool,
    status: QString,
}

#[derive(serde::Serialize, Clone, Debug)]
struct Sink {
    id: String,
    name: String,
    description: String,
    volume_percent: i32,
    muted: bool,
    default: bool,
}

fn default_sink_name() -> String {
    let out = Command::new("pactl")
        .args(["get-default-sink"])
        .output()
        .ok();
    if let Some(o) = out {
        if o.status.success() {
            return String::from_utf8_lossy(&o.stdout).trim().to_string();
        }
    }
    String::new()
}

fn read_sinks() -> Vec<Sink> {
    let mut sinks: Vec<Sink> = Vec::new();
    let dump = match Command::new("pactl").args(["list", "sinks"]).output() {
        Ok(o) if o.status.success() => String::from_utf8_lossy(&o.stdout).to_string(),
        _ => return sinks,
    };

    let default = default_sink_name();
    let mut current: Option<Sink> = None;
    let mut current_volume: f64 = 0.0;
    let mut current_muted: bool = false;

    for raw_line in dump.lines() {
        let line = raw_line.trim();
        if let Some(rest) = line.strip_prefix("Sink #") {
            // Flush previous
            if let Some(c) = current.take() {
                sinks.push(Sink {
                    volume_percent: current_volume.round() as i32,
                    muted: current_muted,
                    ..c
                });
            }
            current_volume = 0.0;
            current_muted = false;
            current = Some(Sink {
                id: rest.trim().to_string(),
                name: String::new(),
                description: String::new(),
                volume_percent: 0,
                muted: false,
                default: false,
            });
        } else if let Some(c) = current.as_mut() {
            if let Some(v) = line.strip_prefix("Name: ") {
                c.name = v.trim().to_string();
                c.default = c.name == default;
            } else if let Some(v) = line.strip_prefix("Description: ") {
                c.description = v.trim().to_string();
            } else if line.starts_with("Mute: ") {
                current_muted = line.trim_end().ends_with("yes");
            } else if line.starts_with("Volume: ") {
                // Line looks like: "Volume: front-left: 13108 / 20% / -41.94 dB,   front-right: ..."
                let pct = line
                    .split('/')
                    .nth(1)
                    .and_then(|s| s.trim().strip_suffix('%'))
                    .and_then(|s| s.trim().parse::<f64>().ok())
                    .unwrap_or(0.0);
                current_volume = pct;
            }
        }
    }
    if let Some(c) = current.take() {
        sinks.push(Sink {
            volume_percent: current_volume.round() as i32,
            muted: current_muted,
            ..c
        });
    }
    sinks
}

fn run_pactl(args: &[&str]) -> Option<String> {
    let out = Command::new("pactl")
        .args(args)
        .output()
        .ok()?;
    if !out.status.success() {
        let stderr = String::from_utf8_lossy(&out.stderr).trim().to_string();
        return Some(format!("err: {stderr}"));
    }
    None
}

impl qobject::Audio {
    pub fn refresh(self: Pin<&mut Self>) {
        let sinks = read_sinks();
        let default = default_sink_name();
        let default_sink = sinks.iter().find(|s| s.name == default).cloned();
        let available = !sinks.is_empty();

        let vol = default_sink
            .as_ref()
            .map(|s| s.volume_percent)
            .unwrap_or(0);
        let muted = default_sink.as_ref().map(|s| s.muted).unwrap_or(false);

        let json = serde_json::to_string(&sinks).unwrap_or_else(|_| "[]".to_string());

        let mut this = self;
        this.as_mut().set_volume_percent(vol);
        this.as_mut().set_muted(muted);
        this.as_mut()
            .set_default_sink_name(QString::from(default.as_str()));
        this.as_mut()
            .set_sinks_json(QString::from(json.as_str()));
        this.as_mut().set_available(available);
        let status = if available {
            format!("{}% {}", vol, if muted { "(muted)" } else { "" })
        } else {
            "pactl not reachable".to_string()
        };
        this.as_mut().set_status(QString::from(status.as_str()));
    }

    pub fn set_volume(self: Pin<&mut Self>, percent: i32) {
        let clamped = percent.clamp(0, 200);
        let target = format!("{}%", clamped);
        let mut this = self;
        let result = run_pactl(&["set-sink-volume", "@DEFAULT_SINK@", &target]);
        match result {
            None => {
                this.as_mut().set_volume_percent(clamped);
                this.as_mut().set_status(QString::from(format!("{clamped}%")));
            }
            Some(err) => {
                this.as_mut().set_status(QString::from(err.as_str()));
            }
        }
        this.as_mut().refresh();
    }

    pub fn bump(self: Pin<&mut Self>, delta_percent: i32) {
        let current = *self.volume_percent();
        self.set_volume(current + delta_percent);
    }

    pub fn toggle_mute(self: Pin<&mut Self>) {
        let mut this = self;
        let result = run_pactl(&["set-sink-mute", "@DEFAULT_SINK@", "toggle"]);
        match result {
            None => {
                let new_state = !*this.muted();
                this.as_mut().set_muted(new_state);
                let status = if new_state { "muted" } else { "unmuted" };
                this.as_mut().set_status(QString::from(status));
            }
            Some(err) => {
                this.as_mut().set_status(QString::from(err.as_str()));
            }
        }
    }

    pub fn set_mute(self: Pin<&mut Self>, muted: bool) {
        let arg = if muted { "1" } else { "0" };
        let mut this = self;
        let result = run_pactl(&["set-sink-mute", "@DEFAULT_SINK@", arg]);
        match result {
            None => {
                this.as_mut().set_muted(muted);
                let status = if muted { "muted" } else { "unmuted" };
                this.as_mut().set_status(QString::from(status));
            }
            Some(err) => {
                this.as_mut().set_status(QString::from(err.as_str()));
            }
        }
    }

    pub fn set_default_sink(self: Pin<&mut Self>, name: &QString) {
        let sink = name.to_string();
        if sink.is_empty() {
            return;
        }
        let mut this = self;
        let result = run_pactl(&["set-default-sink", &sink]);
        match result {
            None => {
                this.as_mut()
                    .set_default_sink_name(QString::from(sink.as_str()));
                this.as_mut()
                    .set_status(QString::from(format!("default -> {sink}")));
            }
            Some(err) => {
                this.as_mut().set_status(QString::from(err.as_str()));
            }
        }
        this.as_mut().refresh();
    }
}
