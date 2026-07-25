use core::pin::Pin;
use cxx_qt_lib::QString;
use image::{ImageReader, imageops::FilterType};
use serde::Serialize;
use std::cmp::Reverse;
use std::collections::HashMap;
use std::path::{Path, PathBuf};

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

/// Extract the top-N dominant colors from an image file.
fn extract_dominant(path: &Path, count: usize) -> Option<Vec<DominantColor>> {
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

    let text_rgb = if relative_luminance(bg_rgb) < 0.4 {
        [230, 230, 234]
    } else {
        [20, 22, 28]
    };

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
