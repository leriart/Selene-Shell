/// Wallpaper surface -- directory enumeration and rendering.
//
/// The `Wallpaper` QObject walks a directory recursively,
/// classifies files (image / animated / video) by extension, and
/// exposes the current path, kind, and the full list as JSON.
/// The QML side (`WallpaperSurface.qml`) renders the correct type
/// via Image / AnimatedImage / MediaPlayer + VideoOutput.

use core::pin::Pin;
use cxx_qt::Threading;
use cxx_qt_lib::QString;
use image::imageops::FilterType;
use image::ImageReader;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(QString, directory)]
        #[qproperty(QString, current_path)]
        #[qproperty(QString, paths_json)]
        #[qproperty(QString, current_kind)]
        #[qproperty(i32, current_index)]
        #[qproperty(bool, available)]
        #[qproperty(bool, thumbnails_ready)]
        type Wallpaper = super::WallpaperRust;

        #[qinvokable]
        fn refresh(self: Pin<&mut Self>);

        #[qinvokable]
        fn use_directory(self: Pin<&mut Self>, path: &QString);

        #[qinvokable]
        fn next_wall(self: Pin<&mut Self>);

        #[qinvokable]
        fn previous_wall(self: Pin<&mut Self>);

        #[qinvokable]
        fn pick_index(self: Pin<&mut Self>, index: i32);

        #[qinvokable]
        fn load_path(self: Pin<&mut Self>, path: &QString);
    }

    impl cxx_qt::Threading for Wallpaper {}
}

#[derive(Default)]
pub struct WallpaperRust {
    directory: QString,
    current_path: QString,
    paths_json: QString,
    current_kind: QString,
    current_index: i32,
    available: bool,
    thumbnails_ready: bool,
}

#[derive(Serialize, Deserialize, Clone)]
struct Entry {
    path: String,
    name: String,
    kind: String,
    #[serde(default)]
    thumbnail: String,
}

fn thumb_dir() -> PathBuf {
    let home = std::env::var_os("HOME")
        .map(|h| PathBuf::from(h))
        .unwrap_or_else(|| PathBuf::from("/tmp"));
    home.join(".cache/selene/wallpaper-thumbs")
}

fn generate_thumb(source: &Path, kind: &str) -> String {
    let dir = thumb_dir();
    let _ = fs::create_dir_all(&dir);
    let hash = source.to_string_lossy()
        .replace(['/', '\\', ':', '.', ' '], "_");
    let thumb_path = dir.join(format!("{hash}.jpg"));
    let thumb_str = thumb_path.to_string_lossy().to_string();

    if thumb_path.exists() {
        return thumb_str;
    }

    match kind {
        "video" => {
            // Extract a frame via ffmpeg
            let _ = Command::new("ffmpeg")
                .args([
                    "-y", "-ss", "1", "-i",
                    source.to_string_lossy().as_ref(),
                    "-frames:v", "1",
                    "-vf", "scale=280:158",
                    thumb_path.to_string_lossy().as_ref(),
                ])
                .output();
        }
        _ => {
            // Resize with image crate
            if let Some(img) = image::ImageReader::open(source)
                .ok()
                .and_then(|r| r.decode().ok())
            {
                let thumb = img.resize_exact(280, 158, FilterType::Lanczos3);
                let _ = thumb.save(&thumb_path);
            }
        }
    }
    thumb_str
}

fn classify(p: &Path) -> Option<String> {
    let ext = p.extension()?.to_str()?.to_lowercase();
    if matches!(ext.as_str(), "mp4" | "webm" | "mkv" | "mov" | "avi" | "m4v") {
        return Some("video".into());
    }
    if matches!(ext.as_str(), "gif" | "apng") {
        return Some("animated".into());
    }
    if matches!(ext.as_str(), "jpg" | "jpeg" | "png" | "webp" | "bmp" | "tif" | "tiff") {
        return Some("image".into());
    }
    None
}

fn walk(dir: &Path, out: &mut Vec<Entry>) {
    let Ok(rd) = fs::read_dir(dir) else {
        return;
    };
    for entry in rd.flatten() {
        let path = entry.path();
        if path.is_dir() {
            walk(&path, out);
        } else if let Some(kind) = classify(&path) {
            if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                out.push(Entry {
                    path: path.to_string_lossy().to_string(),
                    name: name.to_string(),
                    kind,
                    thumbnail: String::new(),
                });
            }
        }
    }
}

fn default_dir() -> PathBuf {
    if let Ok(p) = std::env::var("SELENE_WALLPAPER_DIR") {
        return PathBuf::from(p);
    }
    let home = std::env::var_os("HOME")
        .map(|h| PathBuf::from(h))
        .unwrap_or_else(|| PathBuf::from("/"));
    let candidates = [
        home.join(".local/share/selene/wallpapers"),
        home.join("Pictures/Wallpapers"),
        home.join("Pictures"),
    ];
    candidates
        .into_iter()
        .find(|p| p.exists() && p.is_dir())
        .unwrap_or_else(|| home.join(".local/share/selene/wallpapers"))
}

fn paths_json_for(entries: &[Entry]) -> QString {
    // Filter to entries that actually exist and have a valid kind
    let filtered: Vec<&Entry> = entries.iter().filter(|e| !e.kind.is_empty()).collect();
    QString::from(serde_json::to_string(&filtered).unwrap_or_else(|_| "[]".to_string()).as_str())
}

impl qobject::Wallpaper {
    pub fn refresh(self: Pin<&mut Self>) {
        let raw = self.directory().to_string();
        let dir = if raw.is_empty() {
            default_dir()
        } else {
            PathBuf::from(raw.clone())
        };

        let mut entries: Vec<Entry> = Vec::new();
        walk(&dir, &mut entries);
        entries.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));

        let first_kind = entries.first().map(|e| e.kind.clone()).unwrap_or_default();
        let first_path = entries.first().map(|e| e.path.clone()).unwrap_or_default();
        let json = paths_json_for(&entries);
        let is_empty = entries.is_empty();

        let mut this = self;
        this.as_mut().set_directory(QString::from(dir.to_string_lossy().as_ref()));
        this.as_mut().set_paths_json(json);
        this.as_mut().set_current_path(QString::from(first_path.as_str()));
        this.as_mut().set_current_kind(QString::from(first_kind.as_str()));
        this.as_mut().set_current_index(if is_empty { -1 } else { 0 });
        this.as_mut().set_available(!is_empty);
        this.as_mut().set_thumbnails_ready(false);

        // Generate thumbnails in a background thread so the UI stays
        // responsive. When done, the thread queues the updated paths_json
        // back to the Qt main thread.
        let qt: cxx_qt::CxxQtThread<qobject::Wallpaper> = this.as_ref().qt_thread();
        std::thread::Builder::new()
            .name("selene-thumbnails".into())
            .spawn(move || {
                for entry in entries.iter_mut() {
                    entry.thumbnail = generate_thumb(
                        Path::new(&entry.path), &entry.kind);
                }
                let json = paths_json_for(&entries);
                let _ = qt.queue(move |mut w| {
                    w.as_mut()
                        .set_paths_json(QString::from(json.to_string().as_str()));
                    w.as_mut().set_thumbnails_ready(true);
                });
            })
            .expect("selene: failed to spawn thumbnail thread");
    }

    pub fn use_directory(self: Pin<&mut Self>, path: &QString) {
        let mut this = self;
        this.as_mut().set_directory(path.clone());
        this.refresh();
    }

    pub fn next_wall(self: Pin<&mut Self>) {
        let raw = self.paths_json().to_string();
        let Ok(entries) = serde_json::from_str::<Vec<Entry>>(&raw) else {
            return;
        };
        if entries.is_empty() {
            return;
        }
        let cur = *self.current_index();
        let next_index = ((cur + 1) as usize) % entries.len();
        let mut this = self;
        this.as_mut().set_current_index(next_index as i32);
        this.as_mut().set_current_path(QString::from(entries[next_index].path.as_str()));
        this.as_mut().set_current_kind(QString::from(entries[next_index].kind.as_str()));
    }

    pub fn previous_wall(self: Pin<&mut Self>) {
        let raw = self.paths_json().to_string();
        let Ok(entries) = serde_json::from_str::<Vec<Entry>>(&raw) else {
            return;
        };
        if entries.is_empty() {
            return;
        }
        let cur = *self.current_index();
        let len = entries.len();
        let prev_index = if cur == 0 { (len - 1) as i32 } else { cur - 1 };
        let i = prev_index as usize;
        let mut this = self;
        this.as_mut().set_current_index(prev_index);
        this.as_mut().set_current_path(QString::from(entries[i].path.as_str()));
        this.as_mut().set_current_kind(QString::from(entries[i].kind.as_str()));
    }

    pub fn pick_index(self: Pin<&mut Self>, index: i32) {
        let raw = self.paths_json().to_string();
        let Ok(entries) = serde_json::from_str::<Vec<Entry>>(&raw) else {
            return;
        };
        if index < 0 || (index as usize) >= entries.len() {
            return;
        }
        let i = index as usize;
        let mut this = self;
        this.as_mut().set_current_index(index);
        this.as_mut().set_current_path(QString::from(entries[i].path.as_str()));
        this.as_mut().set_current_kind(QString::from(entries[i].kind.as_str()));
    }

    pub fn load_path(self: Pin<&mut Self>, path: &QString) {
        let raw = path.to_string();
        let pathbuf = PathBuf::from(raw.clone());

        let kind_str = classify(&pathbuf).unwrap_or_else(|| "image".to_string());

        let json_raw = self.paths_json().to_string();
        let mut entries: Vec<Entry> =
            serde_json::from_str(&json_raw).unwrap_or_default();

        let mut index: i32 = -1;
        for (i, e) in entries.iter().enumerate() {
            if e.path == raw {
                index = i as i32;
                break;
            }
        }
        if index < 0 {
            index = entries.len() as i32;
            let name = pathbuf
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("")
                .to_string();
            entries.push(Entry {
                path: raw.clone(),
                name,
                kind: kind_str.clone(),
                thumbnail: String::new(),
            });
        }
        let new_json = paths_json_for(&entries);

        let mut this = self;
        this.as_mut().set_paths_json(new_json);
        this.as_mut().set_current_path(QString::from(raw.as_str()));
        this.as_mut().set_current_kind(QString::from(kind_str.as_str()));
        if index >= 0 {
            this.as_mut().set_current_index(index);
        }
    }
}

