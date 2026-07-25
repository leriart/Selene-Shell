use core::pin::Pin;
use cxx_qt_lib::QString;
use std::fs;

/// Dynamic Island mirror.
#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        // System metrics, /proc-backed
        #[qproperty(f64, load_avg_1)]
        #[qproperty(f64, load_avg_5)]
        #[qproperty(f64, load_avg_15)]
        #[qproperty(i32, ram_used_mb)]
        #[qproperty(i32, ram_total_mb)]
        #[qproperty(i32, procs_running)]
        #[qproperty(i32, procs_total)]
        // Media (MPRIS later, mocked for now)
        #[qproperty(QString, media_title)]
        #[qproperty(QString, media_artist)]
        #[qproperty(bool, media_playing)]
        // Power menu ready flag
        #[qproperty(QString, power_summary)]
        type Island = super::IslandRust;

        #[qinvokable]
        fn refresh(self: Pin<&mut Self>);
    }
}

#[derive(Default)]
pub struct IslandRust {
    load_avg_1: f64,
    load_avg_5: f64,
    load_avg_15: f64,
    ram_used_mb: i32,
    ram_total_mb: i32,
    procs_running: i32,
    procs_total: i32,
    media_title: QString,
    media_artist: QString,
    media_playing: bool,
    power_summary: QString,
}

impl qobject::Island {
    pub fn refresh(self: Pin<&mut Self>) {
        let mut this = self;

        // /proc/loadavg: "1.23 1.45 1.67 1/234 56789"
        if let Ok(text) = fs::read_to_string("/proc/loadavg") {
            let mut parts = text.split_whitespace();
            let l1 = parts.next().and_then(|s| s.parse::<f64>().ok()).unwrap_or(0.0);
            let l5 = parts.next().and_then(|s| s.parse::<f64>().ok()).unwrap_or(0.0);
            let l15 = parts.next().and_then(|s| s.parse::<f64>().ok()).unwrap_or(0.0);
            let procs = parts.next().unwrap_or("");
            let procs_split: Vec<&str> = procs.split('/').collect();
            let running = procs_split
                .first()
                .and_then(|s| s.parse::<i32>().ok())
                .unwrap_or(0);
            let total = procs_split
                .get(1)
                .and_then(|s| s.parse::<i32>().ok())
                .unwrap_or(0);

            this.as_mut().set_load_avg_1(l1);
            this.as_mut().set_load_avg_5(l5);
            this.as_mut().set_load_avg_15(l15);
            this.as_mut().set_procs_running(running);
            this.as_mut().set_procs_total(total);
        }

        // /proc/meminfo
        if let Ok(text) = fs::read_to_string("/proc/meminfo") {
            let mut total_kb = 0u64;
            let mut avail_kb = 0u64;
            for line in text.lines() {
                let mut parts = line.split_whitespace();
                let Some(key) = parts.next() else { continue; };
                let Some(value) = parts.next() else { continue; };
                match key {
                    "MemTotal:" => total_kb = value.parse().unwrap_or(0),
                    "MemAvailable:" => avail_kb = value.parse().unwrap_or(0),
                    _ => {}
                }
            }
            let used_kb = total_kb.saturating_sub(avail_kb);
            this.as_mut().set_ram_total_mb((total_kb / 1024) as i32);
            this.as_mut().set_ram_used_mb((used_kb / 1024) as i32);
        }

        // Mocked media + power info. Real impl: MPRIS D-Bus subscription +
        // loginctl/systemd dispatchers.
        if this.media_title().is_empty() {
            this.as_mut().set_media_title(QString::from("Nothing playing"));
            this.as_mut().set_media_artist(QString::from("--"));
        }
        if this.power_summary().is_empty() {
            this.as_mut()
                .set_power_summary(QString::from("lock / suspend / reboot / logout"));
        }
    }
}
