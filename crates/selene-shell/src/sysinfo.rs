/// Detailed system resources -- CPU / RAM / GPU / disk telemetry.
//
/// The `SystemResources` QObject polls /proc/stat, /proc/meminfo,
/// the thermal + hwmon sysfs trees, the AMD DRM sysfs (with an
/// `nvidia-smi` fallback) and `df` on a dedicated 2-second thread,
/// pushing every sample to QML through the cxx-qt queued bridge.
/// The QML side (`MetricsPanel.qml`) renders the gauges.

use core::pin::Pin;
use cxx_qt::Threading;
use cxx_qt_lib::QString;
use std::fs;
use std::process::Command;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

/// System resource telemetry (dashboard metrics tab).
#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        // CPU, /proc/stat delta + thermal sysfs
        #[qproperty(f64, cpu_usage)]
        #[qproperty(i32, cpu_temp)]
        // RAM, /proc/meminfo (values in MB)
        #[qproperty(f64, ram_usage)]
        #[qproperty(f64, ram_total)]
        #[qproperty(f64, ram_used)]
        // GPU, AMD sysfs or nvidia-smi fallback
        #[qproperty(f64, gpu_usage)]
        #[qproperty(i32, gpu_temp)]
        #[qproperty(bool, gpu_available)]
        // Disk, `df` output as JSON [{mount, size, used, avail, percent}]
        #[qproperty(QString, disk_usage_json)]
        #[qproperty(f64, disk_root_percent)]
        // Diagnostics
        #[qproperty(bool, running)]
        #[qproperty(QString, status)]
        type SystemResources = super::SystemResourcesRust;

        #[qinvokable]
        fn start_polling(self: Pin<&mut Self>);

        #[qinvokable]
        fn stop_polling(self: Pin<&mut Self>);
    }

    impl cxx_qt::Threading for SystemResources {}
}

#[derive(Default)]
pub struct SystemResourcesRust {
    cpu_usage: f64,
    cpu_temp: i32,
    ram_usage: f64,
    ram_total: f64,
    ram_used: f64,
    gpu_usage: f64,
    gpu_temp: i32,
    gpu_available: bool,
    disk_usage_json: QString,
    disk_root_percent: f64,
    running: bool,
    status: QString,
}

/// One aggregate /proc/stat sample: (total_jiffies, idle_jiffies).
#[derive(Default, Clone, Copy)]
struct CpuSample {
    total: u64,
    idle: u64,
}

/// One complete telemetry frame, gathered off the Qt thread.
#[derive(Default)]
struct Frame {
    cpu_usage: f64,
    cpu_temp: i32,
    ram_usage: f64,
    ram_total: f64,
    ram_used: f64,
    gpu_usage: f64,
    gpu_temp: i32,
    gpu_available: bool,
    disk_usage_json: String,
    disk_root_percent: f64,
}

fn poll_flag() -> &'static AtomicBool {
    static FLAG: AtomicBool = AtomicBool::new(false);
    &FLAG
}

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

fn cpu_percent(prev: &mut Option<CpuSample>) -> Option<f64> {
    let cur = read_cpu_sample()?;
    let last = prev.replace(cur)?;
    let totald = cur.total.saturating_sub(last.total) as f64;
    let idled = cur.idle.saturating_sub(last.idle) as f64;
    if totald <= 0.0 {
        return None;
    }
    Some(((totald - idled) / totald * 100.0).clamp(0.0, 100.0))
}

/// CPU temperature: prefer a thermal_zone whose type mentions the CPU
/// package, then fall back to hwmon sensors named coretemp / k10temp /
/// zenpower, then the first thermal_zone at all.
fn read_cpu_temp() -> Option<i32> {
    let preferred = ["x86_pkg_temp", "cpu", "soc", "acpitz"];
    let mut fallback: Option<i32> = None;
    if let Ok(rd) = fs::read_dir("/sys/class/thermal") {
        for entry in rd.flatten() {
            let path = entry.path();
            if !path
                .file_name()
                .map(|n| n.to_string_lossy().starts_with("thermal_zone"))
                .unwrap_or(false)
            {
                continue;
            }
            let ty = fs::read_to_string(path.join("type"))
                .map(|s| s.trim().to_lowercase())
                .unwrap_or_default();
            let temp = fs::read_to_string(path.join("temp"))
                .ok()
                .and_then(|s| s.trim().parse::<i64>().ok())
                .map(|milli| (milli / 1000) as i32);
            let Some(t) = temp else { continue };
            if t <= 0 || t > 150 {
                continue;
            }
            if preferred.iter().any(|p| ty.contains(p)) {
                return Some(t);
            }
            fallback.get_or_insert(t);
        }
    }
    if let Some(t) = read_hwmon_temp(&["coretemp", "k10temp", "zenpower", "cpu_thermal"]) {
        return Some(t);
    }
    fallback
}

/// First temp1_input of an hwmon chip whose name matches `names`.
fn read_hwmon_temp(names: &[&str]) -> Option<i32> {
    let rd = fs::read_dir("/sys/class/hwmon").ok()?;
    for entry in rd.flatten() {
        let path = entry.path();
        let name = fs::read_to_string(path.join("name"))
            .map(|s| s.trim().to_lowercase())
            .unwrap_or_default();
        if !names.iter().any(|n| name.contains(n)) {
            continue;
        }
        if let Ok(text) = fs::read_to_string(path.join("temp1_input")) {
            if let Ok(milli) = text.trim().parse::<i64>() {
                let t = (milli / 1000) as i32;
                if t > 0 && t <= 150 {
                    return Some(t);
                }
            }
        }
    }
    None
}

/// (total_mb, used_mb, percent) from /proc/meminfo.
fn read_meminfo() -> Option<(f64, f64, f64)> {
    let text = fs::read_to_string("/proc/meminfo").ok()?;
    let mut total_kb = 0u64;
    let mut avail_kb = 0u64;
    for line in text.lines() {
        let mut parts = line.split_whitespace();
        let Some(key) = parts.next() else { continue };
        let Some(value) = parts.next() else { continue };
        match key {
            "MemTotal:" => total_kb = value.parse().unwrap_or(0),
            "MemAvailable:" => avail_kb = value.parse().unwrap_or(0),
            _ => {}
        }
    }
    if total_kb == 0 {
        return None;
    }
    let used_kb = total_kb.saturating_sub(avail_kb);
    let total_mb = total_kb as f64 / 1024.0;
    let used_mb = used_kb as f64 / 1024.0;
    Some((total_mb, used_mb, used_mb / total_mb * 100.0))
}

/// AMD GPUs expose gpu_busy_percent in the DRM sysfs; temperature is
/// found on the amdgpu hwmon chip. Returns (usage%, temp_c).
fn read_amd_gpu() -> Option<(f64, i32)> {
    let rd = fs::read_dir("/sys/class/drm").ok()?;
    for entry in rd.flatten() {
        let path = entry.path();
        let name = path.file_name()?.to_string_lossy().to_string();
        // Only top-level cardN (not cardN-DP-1 connectors).
        if !name.starts_with("card") || name.contains('-') {
            continue;
        }
        let busy_path = path.join("device/gpu_busy_percent");
        let Ok(text) = fs::read_to_string(&busy_path) else {
            continue;
        };
        let usage = text.trim().parse::<f64>().ok()?;
        let temp = read_hwmon_temp(&["amdgpu", "radeon"]).unwrap_or(-1);
        return Some((usage.clamp(0.0, 100.0), temp));
    }
    None
}

/// nvidia-smi fallback: one CSV query for utilisation + temperature.
fn read_nvidia_gpu() -> Option<(f64, i32)> {
    let out = Command::new("nvidia-smi")
        .args([
            "--query-gpu=utilization.gpu,temperature.gpu",
            "--format=csv,noheader,nounits",
        ])
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let s = String::from_utf8_lossy(&out.stdout);
    let line = s.lines().next()?;
    let mut parts = line.split(',');
    let usage = parts.next()?.trim().parse::<f64>().ok()?;
    let temp = parts.next()?.trim().parse::<i32>().ok()?;
    Some((usage.clamp(0.0, 100.0), temp))
}

/// `df` over real filesystems -> JSON array + the / usage percent.
fn read_disks() -> (String, f64) {
    let out = Command::new("df")
        .args(["-P", "-B1", "-x", "tmpfs", "-x", "devtmpfs", "-x", "overlay", "-x", "squashfs"])
        .output();
    let Ok(out) = out else {
        return ("[]".to_string(), 0.0);
    };
    if !out.status.success() {
        return ("[]".to_string(), 0.0);
    }
    let text = String::from_utf8_lossy(&out.stdout);
    let mut disks: Vec<serde_json::Value> = Vec::new();
    let mut root_percent = 0.0f64;
    for line in text.lines().skip(1) {
        let cols: Vec<&str> = line.split_whitespace().collect();
        if cols.len() < 6 {
            continue;
        }
        let size = cols[1].parse::<u64>().unwrap_or(0);
        let used = cols[2].parse::<u64>().unwrap_or(0);
        let avail = cols[3].parse::<u64>().unwrap_or(0);
        let percent = cols[4].trim_end_matches('%').parse::<f64>().unwrap_or(0.0);
        let mount = cols[5..].join(" ");
        if size == 0 {
            continue;
        }
        if mount == "/" {
            root_percent = percent;
        }
        disks.push(serde_json::json!({
            "device": cols[0],
            "mount": mount,
            "size_gb": (size as f64 / 1e9 * 10.0).round() / 10.0,
            "used_gb": (used as f64 / 1e9 * 10.0).round() / 10.0,
            "avail_gb": (avail as f64 / 1e9 * 10.0).round() / 10.0,
            "percent": percent,
        }));
    }
    (
        serde_json::to_string(&disks).unwrap_or_else(|_| "[]".to_string()),
        root_percent,
    )
}

fn gather_frame(prev_cpu: &mut Option<CpuSample>) -> Frame {
    let mut frame = Frame::default();
    if let Some(p) = cpu_percent(prev_cpu) {
        frame.cpu_usage = p;
    }
    frame.cpu_temp = read_cpu_temp().unwrap_or(-1);
    if let Some((total, used, pct)) = read_meminfo() {
        frame.ram_total = total;
        frame.ram_used = used;
        frame.ram_usage = pct;
    }
    match read_amd_gpu().or_else(read_nvidia_gpu) {
        Some((usage, temp)) => {
            frame.gpu_usage = usage;
            frame.gpu_temp = temp;
            frame.gpu_available = true;
        }
        None => {
            frame.gpu_usage = 0.0;
            frame.gpu_temp = -1;
            frame.gpu_available = false;
        }
    }
    let (json, root) = read_disks();
    frame.disk_usage_json = json;
    frame.disk_root_percent = root;
    frame
}

fn poll_main(qt: cxx_qt::CxxQtThread<qobject::SystemResources>) {
    let mut prev_cpu: Option<CpuSample> = None;
    // Prime the CPU delta so the first published frame is meaningful.
    let _ = cpu_percent(&mut prev_cpu);
    std::thread::sleep(Duration::from_millis(500));

    while poll_flag().load(Ordering::SeqCst) {
        let frame = gather_frame(&mut prev_cpu);
        let disk_json = QString::from(frame.disk_usage_json.as_str());
        if qt
            .queue(move |mut this| {
                this.as_mut().set_cpu_usage(frame.cpu_usage);
                this.as_mut().set_cpu_temp(frame.cpu_temp);
                this.as_mut().set_ram_usage(frame.ram_usage);
                this.as_mut().set_ram_total(frame.ram_total);
                this.as_mut().set_ram_used(frame.ram_used);
                this.as_mut().set_gpu_usage(frame.gpu_usage);
                this.as_mut().set_gpu_temp(frame.gpu_temp);
                this.as_mut().set_gpu_available(frame.gpu_available);
                this.as_mut().set_disk_usage_json(disk_json);
                this.as_mut().set_disk_root_percent(frame.disk_root_percent);
            })
            .is_err()
        {
            break;
        }
        std::thread::sleep(Duration::from_secs(2));
    }

    let _ = qt.queue(|mut this| {
        this.as_mut().set_running(false);
        this.as_mut().set_status(QString::from("polling stopped"));
    });
}

impl qobject::SystemResources {
    pub fn start_polling(self: Pin<&mut Self>) {
        if poll_flag().swap(true, Ordering::SeqCst) {
            return; // already polling
        }
        let qt: cxx_qt::CxxQtThread<qobject::SystemResources> = self.as_ref().qt_thread();
        std::thread::Builder::new()
            .name("selene-sysinfo".into())
            .spawn(move || poll_main(qt))
            .expect("selene: failed to spawn sysinfo poll thread");
        let mut this = self;
        this.as_mut().set_running(true);
        this.as_mut()
            .set_status(QString::from("polling every 2s"));
    }

    pub fn stop_polling(self: Pin<&mut Self>) {
        poll_flag().store(false, Ordering::SeqCst);
        let mut this = self;
        this.as_mut().set_running(false);
        this.as_mut().set_status(QString::from("stopping"));
    }
}
