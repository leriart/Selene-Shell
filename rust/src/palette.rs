use core::pin::Pin;
use cxx_qt_lib::QString;
use image::{ImageReader, imageops::FilterType};
use serde::Serialize;
use std::cmp::Reverse;
use std::collections::HashMap;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(QString, source_path)]
        #[qproperty(QString, dominant_json)]
        #[qproperty(QString, accent)]
        #[qproperty(QString, surface)]
        #[qproperty(QString, background)]
        #[qproperty(QString, text_color)]
        #[qproperty(QString, last_error)]
        #[qproperty(bool, available)]
        type Palette = super::PaletteRust;

        #[qinvokable]
        fn set_source(self: Pin<&mut Self>, path: &QString);

        #[qinvokable]
        fn refresh(self: Pin<&mut Self>);

        #[qinvokable]
        fn default_source(&self) -> QString;
    }

    impl cxx_qt::Threading for Palette {}
}

#[derive(Default)]
pub struct PaletteRust {
    source_path: QString,
    dominant_json: QString,
    accent: QString,
    surface: QString,
    background: QString,
    text_color: QString,
    last_error: QString,
    available: bool,
}

#[derive(Serialize)]
struct DominantColor {
    rgb: [u8; 3],
    hex: String,
    weight: u32,
}

fn default_source_path() -> PathBuf {
    if let Ok(p) = std::env::var("SELENE_WALLPAPER") {
        return PathBuf::from(p);
    }
    let home = std::env::var_os("HOME")
        .map(|h| PathBuf::from(h))
        .unwrap_or_else(|| PathBuf::from("/"));
    let candidates = [
        home.join(".local/share/selene/wallpaper.png"),
        home.join("Pictures/Wallpapers/current.png"),
        home.join(".config/swww/wallpaper.png"),
        home.join(".cache/wal/wallpaper.png"),
    ];
    candidates
        .into_iter()
        .find(|p| p.exists())
        .unwrap_or_else(|| home.join(".local/share/selene/wallpaper.png"))
}

/// Extract a single RGB24 frame from a video via ffmpeg's `pipe:1`. Returns
/// `None` if ffmpeg isn't available, the source isn't a recognized video,
/// or the pipe fails.
fn extract_video_frame(path: &Path, offset_secs: f32) -> Option<Vec<u8>> {
    if !Command::new("ffmpeg").arg("-version").output().is_ok() {
        return None;
    }
    let mut child = Command::new("ffmpeg")
        .args([
            "-ss", &format!("{:.2}", offset_secs.max(0.0)),
            "-i", path.to_string_lossy().as_ref(),
            "-frames:v", "1",
            "-vf", "scale=64:64",
            "-pix_fmt", "rgb24",
            "-f", "rawvideo",
            "pipe:1",
        ])
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .ok()?;
    let mut stdout = child.stdout.take()?;
    let mut data = Vec::new();
    stdout.read_to_end(&mut data).ok()?;
    let _ = child.wait();
    // 64*64 RGB24 -> 12288 bytes
    if data.len() != 64 * 64 * 3 {
        return None;
    }
    Some(data)
}

fn classify_is_video(path: &Path) -> bool {
    let Some(ext) = path.extension().and_then(|s| s.to_str()) else {
        return false;
    };
    matches!(
        ext.to_lowercase().as_str(),
        "mp4" | "webm" | "mkv" | "mov" | "avi" | "m4v"
    )
}

fn bucket_pixels_from_rgb24(data: &[u8], count: usize) -> Option<Vec<DominantColor>> {
    if data.len() % 3 != 0 {
        return None;
    }
    let mut buckets: HashMap<(u8, u8, u8), u32> = HashMap::new();
    for chunk in data.chunks(3) {
        let r = (chunk[0] >> 3) << 3;
        let g = (chunk[1] >> 3) << 3;
        let b = (chunk[2] >> 3) << 3;
        *buckets.entry((r, g, b)).or_insert(0) += 1;
    }
    if buckets.is_empty() {
        return None;
    }
    let mut sorted: Vec<_> = buckets.into_iter().collect();
    sorted.sort_by_key(|&(_, w)| Reverse(w));
    Some(
        sorted
            .into_iter()
            .take(count)
            .map(|((r, g, b), w)| DominantColor {
                rgb: [r, g, b],
                hex: format!("#{:02x}{:02x}{:02x}", r, g, b),
                weight: w,
            })
            .collect(),
    )
}

/// Probe an approximate duration for a video with `ffprobe`. Returns None
/// when ffprobe isn't available or the source isn't recognised. Only used
/// as a fallback for offset generation when no live frame timer exists.
fn probe_video_duration_secs(path: &Path) -> Option<f32> {
    let output = Command::new("ffprobe")
        .args([
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            path.to_string_lossy().as_ref(),
        ])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let stdout = String::from_utf8_lossy(&output.stdout);
    let trimmed = stdout.trim();
    let secs: f64 = trimmed.parse().ok()?;
    Some(secs as f32)
}

/// Extract the top-N dominant colors from an image or video file.
fn extract_dominant(path: &Path, count: usize) -> Option<Vec<DominantColor>> {
    if classify_is_video(path) {
        let offset = probe_video_duration_secs(path)
            .map(|d| (d * 0.5).max(0.5))
            .unwrap_or(0.0);
        if let Some(data) = extract_video_frame(path, offset) {
            if let Some(dom) = bucket_pixels_from_rgb24(&data, count) {
                return Some(dom);
            }
        }
        // Fall through to static-image extraction in case the file is
        // actually a still misnamed as video.
    }

    let img = ImageReader::open(path).ok()?.decode().ok()?;
    let small = img.resize_exact(64, 64, FilterType::Nearest).to_rgb8();

    let mut buckets: HashMap<(u8, u8, u8), u32> = HashMap::new();
    for px in small.pixels() {
        let r = (px[0] >> 3) << 3;
        let g = (px[1] >> 3) << 3;
        let b = (px[2] >> 3) << 3;
        *buckets.entry((r, g, b)).or_insert(0) += 1;
    }
    if buckets.is_empty() {
        return None;
    }

    let mut sorted: Vec<_> = buckets.into_iter().collect();
    sorted.sort_by_key(|&(_, w)| Reverse(w));

    Some(
        sorted
            .into_iter()
            .take(count)
            .map(|((r, g, b), w)| DominantColor {
                rgb: [r, g, b],
                hex: format!("#{:02x}{:02x}{:02x}", r, g, b),
                weight: w,
            })
            .collect(),
    )
}

fn relative_luminance(rgb: [u8; 3]) -> f32 {
    let channel = |c: u8| {
        let v = c as f32 / 255.0;
        if v <= 0.03928 {
            v / 12.92
        } else {
            ((v + 0.055) / 1.055).powf(2.4)
        }
    };
    0.2126 * channel(rgb[0]) + 0.7152 * channel(rgb[1]) + 0.0722 * channel(rgb[2])
}

fn mix(a: [u8; 3], b: [u8; 3], t: f32) -> [u8; 3] {
    [
        (a[0] as f32 + (b[0] as f32 - a[0] as f32) * t).round() as u8,
        (a[1] as f32 + (b[1] as f32 - a[1] as f32) * t).round() as u8,
        (a[2] as f32 + (b[2] as f32 - a[2] as f32) * t).round() as u8,
    ]
}

fn to_hex(rgb: [u8; 3]) -> String {
    format!("#{:02x}{:02x}{:02x}", rgb[0], rgb[1], rgb[2])
}

/// WCAG 2.x contrast ratio between two colors, in the range [1, 21].
fn contrast_ratio(a: [u8; 3], b: [u8; 3]) -> f32 {
    let la = relative_luminance(a);
    let lb = relative_luminance(b);
    let (lighter, darker) = if la >= lb { (la, lb) } else { (lb, la) };
    (lighter + 0.05) / (darker + 0.05)
}

/// Pick a foreground color that reaches at least 4.5:1 against `bg` when
/// possible. We try a small ladder of near-white / near-black candidates and
/// return the first that passes; if none do, return the best-scoring one.
fn pick_text_color(bg: [u8; 3]) -> [u8; 3] {
    const CANDIDATES: &[[u8; 3]] = &[
        [230, 230, 234],
        [244, 244, 248],
        [255, 255, 255],
        [32, 34, 40],
        [20, 22, 28],
        [10, 11, 14],
        [0, 0, 0],
    ];
    let mut best = CANDIDATES[0];
    let mut best_ratio = 0.0_f32;
    for &c in CANDIDATES {
        let r = contrast_ratio(c, bg);
        if r >= 4.5 {
            return c;
        }
        if r > best_ratio {
            best_ratio = r;
            best = c;
        }
    }
    best
}

fn derive_roles(dominant: &[DominantColor]) -> (String, String, String, String) {
    if dominant.is_empty() {
        let fallback = "#a78bfa".to_string();
        return (
            fallback.clone(),
            fallback,
            "#1a1b1e".to_string(),
            "#e6e6ea".to_string(),
        );
    }

    let accent = dominant[0].hex.clone();
    let mut bg_rgb = dominant[0].rgb;
    for c in dominant.iter().skip(1) {
        if relative_luminance(c.rgb) < relative_luminance(bg_rgb) {
            bg_rgb = c.rgb;
        }
    }
    let surface_rgb = mix(bg_rgb, [255, 255, 255], 0.06);

    let text_rgb = pick_text_color(bg_rgb);

    (accent, to_hex(surface_rgb), to_hex(bg_rgb), to_hex(text_rgb))
}

struct DerivedPalette {
    source_path: QString,
    dominant_json: QString,
    accent: QString,
    surface: QString,
    background: QString,
    text_color: QString,
    available: bool,
    last_error: QString,
}

fn derive_one(path: &Path, raw: &str) -> DerivedPalette {
    let dominant = extract_dominant(path, 6);

    let (accent, surface, background, text_color) = match dominant.as_ref() {
        Some(list) if !list.is_empty() => derive_roles(list),
        _ => (
            "#a78bfa".to_string(),
            "#1a1b1e".to_string(),
            "#0e0f12".to_string(),
            "#e6e6ea".to_string(),
        ),
    };

    let dominant_json = dominant
        .as_ref()
        .map(|v| serde_json::to_string(v).unwrap_or_else(|_| "[]".to_string()))
        .unwrap_or_else(|| "[]".to_string());

    let available = dominant.is_some();
    let last_error = if available {
        QString::from("")
    } else if path.exists() {
        QString::from(format!("could not decode {}", path.display()))
    } else {
        QString::from(format!("no such file: {}", path.display()))
    };

    DerivedPalette {
        source_path: QString::from(raw),
        dominant_json: QString::from(dominant_json.as_str()),
        accent: QString::from(accent.as_str()),
        surface: QString::from(surface.as_str()),
        background: QString::from(background.as_str()),
        text_color: QString::from(text_color.as_str()),
        available,
        last_error,
    }
}

impl qobject::Palette {
    pub fn set_source(self: Pin<&mut Self>, path: &QString) {
        let raw = path.to_string();
        let pathbuf = PathBuf::from(raw.clone());
        let derived = derive_one(&pathbuf, raw.as_str());
        let mut this = self;
        this.as_mut().set_source_path(derived.source_path);
        this.as_mut().set_dominant_json(derived.dominant_json);
        this.as_mut().set_accent(derived.accent);
        this.as_mut().set_surface(derived.surface);
        this.as_mut().set_background(derived.background);
        this.as_mut().set_text_color(derived.text_color);
        this.as_mut().set_available(derived.available);
        this.as_mut().set_last_error(derived.last_error);
    }

    pub fn refresh(self: Pin<&mut Self>) {
        let raw = self.source_path().to_string();
        let pathbuf = PathBuf::from(raw.clone());
        let derived = derive_one(&pathbuf, raw.as_str());
        let mut this = self;
        this.as_mut().set_source_path(derived.source_path);
        this.as_mut().set_dominant_json(derived.dominant_json);
        this.as_mut().set_accent(derived.accent);
        this.as_mut().set_surface(derived.surface);
        this.as_mut().set_background(derived.background);
        this.as_mut().set_text_color(derived.text_color);
        this.as_mut().set_available(derived.available);
        this.as_mut().set_last_error(derived.last_error);
    }

    pub fn default_source(&self) -> QString {
        QString::from(default_source_path().to_string_lossy().as_ref())
    }
}
