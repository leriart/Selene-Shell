/// Native Qt wallpaper engine -- port of NothingLess's
/// `VideoWallpaperService.qml` to Rust. Owns hardware-accelerated
/// video decoding, an on-disk downscale cache for 4K/1440p videos,
/// and a pause state machine that stops decoding while the screen is
/// locked or game mode is active.
///
/// QML side (`WallpaperSurface.qml`) reads `effective_path` /
/// `paused` / `paused_reason` to drive `MediaPlayer`.
use core::pin::Pin;
use cxx_qt_lib::QString;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

/// Wallpaper engine -- GPU detection, hwaccel, downscale cache, pause.
#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(QString, gpu_vendor)]
        #[qproperty(QString, hw_encoder)]
        #[qproperty(QString, hw_scale_filter)]
        #[qproperty(QString, cache_dir)]
        #[qproperty(i32, optimal_fps)]
        #[qproperty(bool, using_hardware)]
        #[qproperty(bool, available)]
        #[qproperty(QString, current_path)]
        #[qproperty(QString, effective_path)]
        #[qproperty(bool, video)]
        #[qproperty(bool, paused)]
        #[qproperty(QString, paused_reason)]
        #[qproperty(QString, status)]
        type WallpaperEngine = super::WallpaperEngineRust;

        #[qinvokable]
        fn refresh(self: Pin<&mut Self>);

        #[qinvokable]
        fn set_wallpaper(self: Pin<&mut Self>, path: &QString);

        #[qinvokable]
        fn pause_for(self: Pin<&mut Self>, reason: &QString);

        #[qinvokable]
        fn resume_for(self: Pin<&mut Self>, reason: &QString);

        #[qinvokable]
        fn clear_path(self: Pin<&mut Self>);
    }
}

pub struct WallpaperEngineRust {
    gpu_vendor: QString,
    hw_encoder: QString,
    hw_scale_filter: QString,
    cache_dir: QString,
    optimal_fps: i32,
    using_hardware: bool,
    available: bool,
    current_path: QString,
    effective_path: QString,
    video: bool,
    paused: bool,
    paused_reason: QString,
    status: QString,
}

impl Default for WallpaperEngineRust {
    fn default() -> Self {
        Self {
            gpu_vendor: QString::from(""),
            hw_encoder: QString::from(""),
            hw_scale_filter: QString::from(""),
            cache_dir: QString::from(""),
            optimal_fps: 24,
            using_hardware: false,
            available: false,
            current_path: QString::from(""),
            effective_path: QString::from(""),
            video: false,
            paused: false,
            paused_reason: QString::from(""),
            status: QString::from(""),
        }
    }
}

/// Reasons the wallpaper pauses. Combined with OR semantics so multiple
/// reasons stack (locked + game mode both flip it off; clearing one
/// keeps it paused while the other is still set).
#[derive(Default, Clone, Debug)]
struct PauseMask(u8);

const PAUSE_NONE: u8 = 0;
const PAUSE_LOCKED: u8 = 1 << 0;
const PAUSE_GAME: u8 = 1 << 1;
const PAUSE_OCCLUDED: u8 = 1 << 2;

fn pause_mask_slot() -> &'static std::sync::Mutex<PauseMask> {
    static SLOT: std::sync::OnceLock<std::sync::Mutex<PauseMask>> =
        std::sync::OnceLock::new();
    SLOT.get_or_init(|| std::sync::Mutex::new(PauseMask::default()))
}

fn gpu_vendor_path() -> Option<PathBuf> {
    let entries = std::fs::read_dir("/sys/class/drm").ok()?;
    for entry in entries.flatten() {
        let p = entry.path();
        if p.file_name()?.to_str()?.starts_with("card")
            && !p
                .file_name()
                .and_then(|s| s.to_str())
                .map(|s| s.contains('-'))
                .unwrap_or(true)
        {
            let v = p.join("device/vendor");
            if v.exists() {
                return Some(v);
            }
        }
    }
    None
}

fn detect_gpu_vendor() -> String {
    // /sys/class/drm/cardN/device/vendor: 0x10de (nvidia), 0x1002 (amd),
    // 0x8086 (intel), 0x106b (apple).
    let Some(path) = gpu_vendor_path() else {
        return "unknown".to_string();
    };
    let raw = std::fs::read_to_string(&path)
        .ok()
        .map(|s| s.trim().to_lowercase())
        .unwrap_or_default();
    match raw.as_str() {
        "0x10de" => "nvidia".to_string(),
        "0x1002" => "amd".to_string(),
        "0x8086" => "intel".to_string(),
        "0x106b" => "apple".to_string(),
        _ => "unknown".to_string(),
    }
}

fn ffmpeg_hwaccels() -> Vec<String> {
    let out = Command::new("ffmpeg")
        .args(["-hide_banner", "-hwaccels"])
        .output()
        .ok();
    let stdout = out
        .as_ref()
        .map(|o| String::from_utf8_lossy(&o.stdout).to_string())
        .unwrap_or_default();
    stdout
        .lines()
        .skip_while(|l| !l.trim().is_empty())
        .filter_map(|l| {
            let t = l.trim();
            if t.is_empty() { None } else { Some(t.to_lowercase()) }
        })
        .collect()
}

/// Pick the best (encoder, scale filter) pair for the GPU vendor from
/// the list of hwaccels ffmpeg actually exposes. Falls back to "" (use
/// libx264 / scale) when nothing hardware-side is available.
fn pick_hw_pair(vendor: &str, hwaccels: &[String]) -> (String, String) {
    let has = |name: &str| hwaccels.iter().any(|h| h == name);
    match vendor {
        "nvidia" if has("cuda") => ("h264_nvenc".into(), "scale_cuda".into()),
        "amd" if has("vaapi") => ("h264_vaapi".into(), "scale_vaapi".into()),
        "intel" if has("qsv") => ("h264_qsv".into(), "scale_qsv".into()),
        "intel" if has("vaapi") => ("h264_vaapi".into(), "scale_vaapi".into()),
        _ => (String::new(), String::new()),
    }
}

/// djb2 of a file path; matches NothingLess's hash so the cache file
/// name is stable across runs.
fn hash_path(path: &str) -> u64 {
    let mut hash: u64 = 5381;
    for b in path.as_bytes() {
        hash = hash.wrapping_mul(33).wrapping_add(u64::from(*b));
    }
    hash
}

fn home_dir() -> PathBuf {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/"))
}

fn ensure_dir(p: &Path) -> std::io::Result<()> {
    std::fs::create_dir_all(p)
}

fn is_video(path: &str) -> bool {
    let lower = path.to_lowercase();
    matches!(
        lower.rsplit('.').next().unwrap_or(""),
        "mp4" | "webm" | "mkv" | "mov" | "avi"
    )
}

/// Spawn a fire-and-forget ffmpeg that writes a downscaled copy at
/// `cache_path`. Detached so the shell doesn't wait on it; stdout/stderr
/// are discarded. Errors here are non-fatal -- the QML side will fall
/// back to the original path if the cache is missing later.
fn spawn_downscale(
    original: &Path,
    cache_path: &Path,
    target_height: u32,
    vendor: &str,
    enc: &str,
    scale: &str,
) -> std::io::Result<()> {
    if let Some(parent) = cache_path.parent() {
        ensure_dir(parent)?;
    }
    let target = target_height.to_string();
    let mut cmd: Vec<String>;
    if !enc.is_empty() && !scale.is_empty() {
        cmd = match vendor {
            "intel" => vec![
                "ffmpeg".into(),
                "-hwaccel".into(),
                "qsv".into(),
                "-hwaccel_output_format".into(),
                "qsv".into(),
                "-i".into(),
                original.to_string_lossy().to_string(),
                "-vf".into(),
                format!("{scale}=-1:{target}"),
                "-c:v".into(),
                enc.into(),
                "-preset".into(),
                "veryfast".into(),
                "-an".into(),
                "-y".into(),
                cache_path.to_string_lossy().to_string(),
            ],
            "amd" => vec![
                "ffmpeg".into(),
                "-hwaccel".into(),
                "vaapi".into(),
                "-hwaccel_output_format".into(),
                "vaapi".into(),
                "-i".into(),
                original.to_string_lossy().to_string(),
                "-vf".into(),
                format!("format=nv12,hwupload,{scale}=-1:{target}"),
                "-c:v".into(),
                enc.into(),
                "-preset".into(),
                "veryfast".into(),
                "-an".into(),
                "-y".into(),
                cache_path.to_string_lossy().to_string(),
            ],
            "nvidia" => vec![
                "ffmpeg".into(),
                "-hwaccel".into(),
                "cuda".into(),
                "-hwaccel_output_format".into(),
                "cuda".into(),
                "-i".into(),
                original.to_string_lossy().to_string(),
                "-vf".into(),
                format!("{scale}=-1:{target}"),
                "-c:v".into(),
                enc.into(),
                "-preset".into(),
                "p1".into(),
                "-an".into(),
                "-y".into(),
                cache_path.to_string_lossy().to_string(),
            ],
            _ => Vec::new(),
        };
    } else {
        cmd = Vec::new();
    }
    if cmd.is_empty() {
        cmd = vec![
            "ffmpeg".into(),
            "-i".into(),
            original.to_string_lossy().to_string(),
            "-vf".into(),
            format!("scale=-1:{target}"),
            "-c:v".into(),
            "libx264".into(),
            "-preset".into(),
            "ultrafast".into(),
            "-crf".into(),
            "28".into(),
            "-an".into(),
            "-y".into(),
            cache_path.to_string_lossy().to_string(),
        ];
    }
    Command::new(&cmd[0])
        .args(&cmd[1..])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map(|_| ())
}

fn parse_reason(s: &str) -> u8 {
    match s {
        "locked" => PAUSE_LOCKED,
        "game" => PAUSE_GAME,
        "occluded" => PAUSE_OCCLUDED,
        "none" | "" => PAUSE_NONE,
        _ => PAUSE_NONE,
    }
}

fn pause_reason_label(mask: u8) -> String {
    let mut parts: Vec<&str> = Vec::new();
    if mask & PAUSE_LOCKED != 0 {
        parts.push("locked");
    }
    if mask & PAUSE_GAME != 0 {
        parts.push("game");
    }
    if mask & PAUSE_OCCLUDED != 0 {
        parts.push("occluded");
    }
    parts.join("+")
}

impl qobject::WallpaperEngine {
    pub fn refresh(self: Pin<&mut Self>) {
        let vendor = detect_gpu_vendor();
        let hwaccels = ffmpeg_hwaccels();
        let (enc, scale) = pick_hw_pair(&vendor, &hwaccels);
        let using_hw = !enc.is_empty();
        // Hardware decoders sustain 24 fps easily; software decoding
        // drops to 15 fps to free up the main thread.
        let optimal_fps = if using_hw { 24 } else { 15 };
        let cache = home_dir().join(".cache/selene/video-cache");
        let _ = ensure_dir(&cache);

        let ffmpeg_ok = Command::new("which")
            .arg("ffmpeg")
            .output()
            .map(|o| o.status.success())
            .unwrap_or(false);

        let mut this = self;
        this.as_mut().set_gpu_vendor(QString::from(vendor.as_str()));
        this.as_mut().set_hw_encoder(QString::from(enc.as_str()));
        this.as_mut().set_hw_scale_filter(QString::from(scale.as_str()));
        this.as_mut().set_cache_dir(QString::from(
            cache.to_string_lossy().as_ref(),
        ));
        this.as_mut().set_optimal_fps(optimal_fps);
        this.as_mut().set_using_hardware(using_hw);
        this.as_mut().set_available(ffmpeg_ok);
        this.as_mut().set_status(QString::from(if ffmpeg_ok {
            if using_hw {
                "engine ready (hw)"
            } else {
                "engine ready (sw)"
            }
        } else {
            "ffmpeg missing"
        }));
    }

    pub fn set_wallpaper(self: Pin<&mut Self>, path: &QString) {
        let raw = path.to_string();
        if raw.is_empty() {
            return;
        }
        let video = is_video(&raw);
        let cache_dir = home_dir().join(".cache/selene/video-cache");
        let _ = ensure_dir(&cache_dir);

        // Default target height for downscaling: 1440p ceiling. 4K
        // sources keep their detail; smaller sources fall through to
        // the software fallback and re-encode to 1440p anyway (ffmpeg
        // skips changes that would upscale).
        let target_h: u32 = 1440;
        let effective = if video {
            let hash = hash_path(&raw);
            let ext = raw.rsplit('.').next().unwrap_or("mp4");
            let cache_path = cache_dir.join(format!("{:x}-{}.{}", hash, target_h, ext));
            let cached_str = cache_path.to_string_lossy().to_string();

            // Kick off downscale in the background. We never block the
            // UI on it -- MediaPlayer picks up the cache on its own
            // when it's ready.
            let vendor = self.gpu_vendor().to_string();
            let enc = self.hw_encoder().to_string();
            let scale = self.hw_scale_filter().to_string();
            let _ = spawn_downscale(
                Path::new(&raw),
                &cache_path,
                target_h,
                &vendor,
                &enc,
                &scale,
            );
            cached_str
        } else {
            raw.clone()
        };

        let mut this = self;
        this.as_mut().set_current_path(QString::from(raw.as_str()));
        this.as_mut().set_effective_path(QString::from(effective.as_str()));
        this.as_mut().set_video(video);
    }

    pub fn pause_for(self: Pin<&mut Self>, reason: &QString) {
        let bit = parse_reason(&reason.to_string());
        if bit == PAUSE_NONE {
            return;
        }
        let mask = {
            let mut m = pause_mask_slot().lock().unwrap();
            m.0 |= bit;
            m.0
        };
        let mut this = self;
        this.as_mut().set_paused(mask != PAUSE_NONE);
        this.as_mut().set_paused_reason(QString::from(pause_reason_label(mask).as_str()));
    }

    pub fn resume_for(self: Pin<&mut Self>, reason: &QString) {
        let bit = parse_reason(&reason.to_string());
        if bit == PAUSE_NONE {
            return;
        }
        let mask = {
            let mut m = pause_mask_slot().lock().unwrap();
            m.0 &= !bit;
            m.0
        };
        let mut this = self;
        this.as_mut().set_paused(mask != PAUSE_NONE);
        this.as_mut().set_paused_reason(QString::from(pause_reason_label(mask).as_str()));
    }

    pub fn clear_path(self: Pin<&mut Self>) {
        let mut this = self;
        this.as_mut().set_current_path(QString::from(""));
        this.as_mut().set_effective_path(QString::from(""));
        this.as_mut().set_video(false);
    }
}
