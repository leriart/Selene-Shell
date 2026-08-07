use core::pin::Pin;
use cxx_qt_lib::QString;
use std::fs;
use std::process::Command;
use std::sync::{Mutex, OnceLock};

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
        // System metrics, /proc + /sys-backed
        #[qproperty(f64, load_avg_1)]
        #[qproperty(f64, load_avg_5)]
        #[qproperty(f64, load_avg_15)]
        #[qproperty(f64, cpu_percent)]
        #[qproperty(i32, ram_used_mb)]
        #[qproperty(i32, ram_total_mb)]
        #[qproperty(i32, procs_running)]
        #[qproperty(i32, procs_total)]
        // Battery, /sys/class/power_supply
        #[qproperty(i32, battery_percent)]
        #[qproperty(QString, battery_status)]
        #[qproperty(bool, battery_present)]
        // Clock, format "HH:MM" / "YYYY-MM-DD"
        #[qproperty(QString, time_hhmm)]
        #[qproperty(QString, date_ymd)]
        // Media (MPRIS via playerctl, mock-fallback)
        #[qproperty(QString, media_title)]
        #[qproperty(QString, media_artist)]
        #[qproperty(bool, media_playing)]
        #[qproperty(QString, media_player)]
        // Power menu summary
        #[qproperty(QString, power_summary)]
        type Island = super::IslandRust;

        #[qinvokable]
        fn refresh(self: Pin<&mut Self>);

        #[qinvokable]
        fn lock(self: Pin<&mut Self>);

        #[qinvokable]
        fn suspend(self: Pin<&mut Self>);

        #[qinvokable]
        fn reboot(self: Pin<&mut Self>);

        #[qinvokable]
        fn poweroff(self: Pin<&mut Self>);

        #[qinvokable]
        fn logout(self: Pin<&mut Self>);
    }
}

#[derive(Default)]
pub struct IslandRust {
    load_avg_1: f64,
    load_avg_5: f64,
    load_avg_15: f64,
    cpu_percent: f64,
    ram_used_mb: i32,
    ram_total_mb: i32,
    procs_running: i32,
    procs_total: i32,
    battery_percent: i32,
    battery_status: QString,
    battery_present: bool,
    time_hhmm: QString,
    date_ymd: QString,
    media_title: QString,
    media_artist: QString,
    media_playing: bool,
    media_player: QString,
    power_summary: QString,
}

#[derive(Default, Clone, Copy)]
struct CpuSample {
    total: u64,
    idle: u64,
}

fn last_cpu_sample() -> &'static Mutex<Option<CpuSample>> {
    static SAMPLE: OnceLock<Mutex<Option<CpuSample>>> = OnceLock::new();
    SAMPLE.get_or_init(|| Mutex::new(None))
}

/// Parse the first aggregate `cpu` line from /proc/stat. Fields are:
/// user nice system idle iowait irq softirq steal guest guest_nice.
/// Returns (total_jiffies, idle_jiffies).
fn read_cpu_sample() -> Option<CpuSample> {
    let text = fs::read_to_string("/proc/stat").ok()?;
    let line = text.lines().next()?;
    if !line.starts_with("cpu ") {
        return None;
    }
    let mut nums = line
        .split_whitespace()
        .skip(1)
        .filter_map(|s| s.parse::<u64>().ok());
    let user = nums.next()?;
    let nice = nums.next()?;
    let system = nums.next()?;
    let idle = nums.next()?;
    let iowait = nums.next().unwrap_or(0);
    let irq = nums.next().unwrap_or(0);
    let softirq = nums.next().unwrap_or(0);
    let steal = nums.next().unwrap_or(0);
    let idle_all = idle + iowait;
    let non_idle = user + nice + system + irq + softirq + steal;
    Some(CpuSample {
        total: idle_all + non_idle,
        idle: idle_all,
    })
}

fn cpu_percent_since_last() -> Option<f64> {
    let cur = read_cpu_sample()?;
    let mut guard = last_cpu_sample().lock().ok()?;
    let prev = guard.replace(cur)?;
    let totald = cur.total.saturating_sub(prev.total) as f64;
    let idled = cur.idle.saturating_sub(prev.idle) as f64;
    if totald <= 0.0 {
        return None;
    }
    Some(((totald - idled) / totald * 100.0).clamp(0.0, 100.0))
}

fn read_battery() -> Option<(i32, String)> {
    let base = std::path::Path::new("/sys/class/power_supply");
    let rd = fs::read_dir(base).ok()?;
    for entry in rd.flatten() {
        let path = entry.path();
        let ty = fs::read_to_string(path.join("type")).ok()?;
        if ty.trim() != "Battery" {
            continue;
        }
        let capacity = fs::read_to_string(path.join("capacity"))
            .ok()
            .and_then(|s| s.trim().parse::<i32>().ok())
            .unwrap_or(-1);
        let status = fs::read_to_string(path.join("status"))
            .map(|s| s.trim().to_string())
            .unwrap_or_else(|_| "Unknown".to_string());
        if capacity >= 0 {
            return Some((capacity, status));
        }
    }
    None
}

fn clock_strings() -> (String, String) {
    // No chrono dep; shell out to `date` once. Cheap (once per refresh tick).
    let out = Command::new("date")
        .arg("+%H:%M|%Y-%m-%d|%A")
        .output();
    match out {
        Ok(o) if o.status.success() => {
            let s = String::from_utf8_lossy(&o.stdout).trim().to_string();
            let mut parts = s.split('|');
            let hhmm = parts.next().unwrap_or("--:--").to_string();
            let ymd = parts.next().unwrap_or("").to_string();
            (hhmm, ymd)
        }
        _ => ("--:--".to_string(), "".to_string()),
    }
}

fn read_mpris() -> Option<(String, String, bool, String)> {
    // playerctl is the de-facto MPRIS CLI. We ask for the playing player's
    // metadata in one call. Returns None when no player or playerctl absent.
    let out = Command::new("playerctl")
        .args([
            "metadata",
            "--format",
            "{{playerName}}|{{status}}|{{title}}|{{artist}}",
        ])
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if s.is_empty() {
        return None;
    }
    let mut parts = s.splitn(4, '|');
    let player = parts.next().unwrap_or("").to_string();
    let status = parts.next().unwrap_or("").to_string();
    let title = parts.next().unwrap_or("").to_string();
    let artist = parts.next().unwrap_or("").to_string();
    if title.is_empty() {
        return None;
    }
    let playing = status.eq_ignore_ascii_case("playing");
    Some((title, artist, playing, player))
}

impl qobject::Island {
    pub fn refresh(self: Pin<&mut Self>) {
        let mut this = self;

        // /proc/loadavg
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

        // CPU% (delta of /proc/stat against the previous sample)
        if let Some(p) = cpu_percent_since_last() {
            this.as_mut().set_cpu_percent(p);
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

        // Battery
        match read_battery() {
            Some((pct, status)) => {
                this.as_mut().set_battery_present(true);
                this.as_mut().set_battery_percent(pct);
                this.as_mut().set_battery_status(QString::from(status.as_str()));
            }
            None => {
                this.as_mut().set_battery_present(false);
                this.as_mut().set_battery_percent(-1);
                this.as_mut().set_battery_status(QString::from(""));
            }
        }

        // Clock
        let (hhmm, ymd) = clock_strings();
        this.as_mut().set_time_hhmm(QString::from(hhmm.as_str()));
        this.as_mut().set_date_ymd(QString::from(ymd.as_str()));

        // MPRIS media
        match read_mpris() {
            Some((title, artist, playing, player)) => {
                this.as_mut().set_media_title(QString::from(title.as_str()));
                this.as_mut().set_media_artist(QString::from(artist.as_str()));
                this.as_mut().set_media_playing(playing);
                this.as_mut().set_media_player(QString::from(player.as_str()));
            }
            None => {
                if this.media_title().is_empty() || this.media_player().is_empty() {
                    this.as_mut().set_media_title(QString::from("Nothing playing"));
                    this.as_mut().set_media_artist(QString::from("--"));
                    this.as_mut().set_media_playing(false);
                    this.as_mut().set_media_player(QString::from(""));
                } else {
                    // Had media before; player went away. Clear.
                    this.as_mut().set_media_title(QString::from("Nothing playing"));
                    this.as_mut().set_media_artist(QString::from("--"));
                    this.as_mut().set_media_playing(false);
                    this.as_mut().set_media_player(QString::from(""));
                }
            }
        }

        if this.power_summary().is_empty() {
            this.as_mut()
                .set_power_summary(QString::from("lock / suspend / reboot / logout"));
        }
    }

    fn dispatch_power(self: Pin<&mut Self>, args: &[&str], label: &'static str) {
        let mut this = self;
        let status = match std::process::Command::new("loginctl")
            .args(args)
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn()
        {
            Ok(_) => format!("{label} dispatched"),
            Err(err) => format!("{label} failed: {err}"),
        };
        this.as_mut().set_power_summary(QString::from(status.as_str()));
    }

    pub fn lock(self: Pin<&mut Self>) {
        self.dispatch_power(&["lock-session"], "lock");
    }

    pub fn suspend(self: Pin<&mut Self>) {
        self.dispatch_power(&["suspend"], "suspend");
    }

    pub fn reboot(self: Pin<&mut Self>) {
        self.dispatch_power(&["reboot"], "reboot");
    }

    pub fn poweroff(self: Pin<&mut Self>) {
        self.dispatch_power(&["poweroff"], "poweroff");
    }

    pub fn logout(self: Pin<&mut Self>) {
        self.dispatch_power(&["terminate-user", "self"], "logout");
    }
}
