use core::pin::Pin;
use cxx_qt_lib::QString;
use mlua::Lua;
use serde::Serialize;
use std::fs;
use std::path::PathBuf;

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        // Panel
        #[qproperty(i32, panel_height)]
        #[qproperty(QString, panel_position)]
        #[qproperty(bool, panel_transparent)]
        #[qproperty(QString, panel_modules_json)]
        // Launcher
        #[qproperty(i32, launcher_width)]
        #[qproperty(i32, launcher_max_results)]
        #[qproperty(bool, launcher_show_icons)]
        // Theme
        #[qproperty(QString, theme_accent)]
        #[qproperty(QString, theme_background)]
        #[qproperty(QString, theme_surface)]
        // Font
        #[qproperty(QString, font_family)]
        #[qproperty(i32, font_size)]
        // Binds + diagnostics
        #[qproperty(QString, binds_json)]
        #[qproperty(QString, status)]
        #[qproperty(QString, source_path)]
        #[qproperty(bool, defaults_used)]
        type Config = super::ConfigRust;

        #[qinvokable]
        fn reload(self: Pin<&mut Self>);

        #[qinvokable]
        fn load_from(self: Pin<&mut Self>, path: &QString);

        #[qinvokable]
        fn path(&self) -> QString;
    }
}

#[derive(Serialize, Clone, Debug)]
pub struct Settings {
    pub panel_height: i32,
    pub panel_position: String,
    pub panel_transparent: bool,
    pub panel_modules: Vec<String>,
    pub launcher_width: i32,
    pub launcher_max_results: i32,
    pub launcher_show_icons: bool,
    pub theme_accent: String,
    pub theme_background: String,
    pub theme_surface: String,
    pub font_family: String,
    pub font_size: i32,
    pub binds: Vec<String>,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            panel_height: 36,
            panel_position: "top".to_string(),
            panel_transparent: true,
            panel_modules: vec![
                "workspaces".to_string(),
                "clock".to_string(),
                "tray".to_string(),
            ],
            launcher_width: 640,
            launcher_max_results: 8,
            launcher_show_icons: true,
            theme_accent: "#a78bfa".to_string(),
            theme_background: "#1a1b1e".to_string(),
            theme_surface: "#2a2b2e".to_string(),
            font_family: "Inter".to_string(),
            font_size: 13,
            binds: vec![
                "SUPER -> launcher".to_string(),
                "SUPER + D -> dashboard".to_string(),
                "SUPER + L -> lock".to_string(),
                "SUPER + ESC -> power".to_string(),
            ],
        }
    }
}

#[derive(Default)]
pub struct ConfigRust {
    panel_height: i32,
    panel_position: QString,
    panel_transparent: bool,
    panel_modules_json: QString,
    launcher_width: i32,
    launcher_max_results: i32,
    launcher_show_icons: bool,
    theme_accent: QString,
    theme_background: QString,
    theme_surface: QString,
    font_family: QString,
    font_size: i32,
    binds_json: QString,
    status: QString,
    source_path: QString,
    defaults_used: bool,
}

fn default_path() -> PathBuf {
    if let Ok(p) = std::env::var("SELENE_CONFIG") {
        return PathBuf::from(p);
    }
    let home = std::env::var_os("HOME")
        .map(|h| PathBuf::from(h))
        .unwrap_or_else(|| PathBuf::from("/"));
    home.join(".config").join("selene").join("init.lua")
}

fn lookup<'a>(table: &'a mlua::Table, key: &str) -> Option<mlua::Value> {
    table.get::<mlua::Value>(key).ok()
}

fn string_field(table: &mlua::Table, key: &str, default: &str) -> String {
    if let Some(mlua::Value::String(s)) = lookup(table, key) {
        s.to_string_lossy().to_string()
    } else {
        default.to_string()
    }
}

fn integer_field(table: &mlua::Table, key: &str, default: i64) -> i64 {
    if let Some(v) = lookup(table, key) {
        if let Some(n) = v.as_i64() {
            n
        } else if let Some(n) = v.as_f64() {
            n as i64
        } else {
            default
        }
    } else {
        default
    }
}

fn bool_field(table: &mlua::Table, key: &str, default: bool) -> bool {
    if let Some(v) = lookup(table, key) {
        if let Some(b) = v.as_boolean() {
            b
        } else {
            default
        }
    } else {
        default
    }
}

fn table_field(table: &mlua::Table, key: &str) -> Option<mlua::Table> {
    if let Some(v) = lookup(table, key) {
        if let mlua::Value::Table(t) = v {
            Some(t.clone())
        } else {
            None
        }
    } else {
        None
    }
}

fn string_list_field(table: &mlua::Table, key: &str, default: &[&str]) -> Vec<String> {
    if let Some(t) = table_field(table, key) {
        let mut out = Vec::new();
        for pair in t.pairs::<mlua::Value, mlua::Value>() {
            if let Ok((_, val)) = pair {
                if let mlua::Value::String(s) = val {
                    out.push(s.to_string_lossy().to_string());
                }
            }
        }
        if !out.is_empty() {
            return out;
        }
    }
    default.iter().map(|s| s.to_string()).collect()
}

fn load_from_path(path: &PathBuf) -> (Settings, QString, bool) {
    let defaults = Settings::default();

    let content = match fs::read_to_string(path) {
        Ok(s) => s,
        Err(err) => {
            return (
                defaults,
                QString::from(format!("missing: {} (using defaults)", err)),
                true,
            );
        }
    };

    let lua = unsafe { Lua::unsafe_new() };

    let loaded: mlua::Result<mlua::Value> = lua.load(&content).eval();
    let table = match loaded {
        Ok(v) => match v {
            mlua::Value::Table(t) => t,
            _ => {
                return (
                    defaults,
                    QString::from("init.lua must return a table; using defaults"),
                    true,
                );
            }
        },
        Err(err) => {
            return (
                defaults,
                QString::from(format!("lua error: {} (using defaults)", err)),
                true,
            );
        }
    };

    let mut out = defaults;
    if let Some(p) = table_field(&table, "panel") {
        out.panel_height = integer_field(&p, "height", out.panel_height as i64) as i32;
        out.panel_position = string_field(&p, "position", &out.panel_position);
        out.panel_transparent = bool_field(&p, "transparent", out.panel_transparent);
        out.panel_modules = string_list_field(
            &p,
            "modules",
            &out.panel_modules.iter().map(|s| s.as_str()).collect::<Vec<_>>(),
        );
    }
    if let Some(l) = table_field(&table, "launcher") {
        out.launcher_width = integer_field(&l, "width", out.launcher_width as i64) as i32;
        out.launcher_max_results =
            integer_field(&l, "max_results", out.launcher_max_results as i64) as i32;
        out.launcher_show_icons = bool_field(&l, "show_icons", out.launcher_show_icons);
    }
    if let Some(t) = table_field(&table, "theme") {
        out.theme_accent = string_field(&t, "accent", &out.theme_accent);
        out.theme_background = string_field(&t, "background", &out.theme_background);
        out.theme_surface = string_field(&t, "surface", &out.theme_surface);
    }
    if let Some(f) = table_field(&table, "font") {
        out.font_family = string_field(&f, "family", &out.font_family);
        out.font_size = integer_field(&f, "size", out.font_size as i64) as i32;
    }
    out.binds = string_list_field(
        &table,
        "binds",
        &out.binds.iter().map(|s| s.as_str()).collect::<Vec<_>>(),
    );

    (out, QString::from("ok"), false)
}

impl qobject::Config {
    pub fn reload(self: Pin<&mut Self>) {
        let path = default_path();
        let (settings, status, defaults_used) = load_from_path(&path);
        let mut this = self;
        this.as_mut().set_panel_height(settings.panel_height);
        this.as_mut().set_panel_position(QString::from(settings.panel_position.as_str()));
        this.as_mut().set_panel_transparent(settings.panel_transparent);
        this.as_mut().set_panel_modules_json(QString::from(
            serde_json::to_string(&settings.panel_modules)
                .unwrap_or_else(|_| "[]".to_string())
                .as_str(),
        ));
        this.as_mut().set_launcher_width(settings.launcher_width);
        this.as_mut().set_launcher_max_results(settings.launcher_max_results);
        this.as_mut().set_launcher_show_icons(settings.launcher_show_icons);
        this.as_mut().set_theme_accent(QString::from(settings.theme_accent.as_str()));
        this.as_mut().set_theme_background(QString::from(settings.theme_background.as_str()));
        this.as_mut().set_theme_surface(QString::from(settings.theme_surface.as_str()));
        this.as_mut().set_font_family(QString::from(settings.font_family.as_str()));
        this.as_mut().set_font_size(settings.font_size);
        this.as_mut().set_binds_json(QString::from(
            serde_json::to_string(&settings.binds)
                .unwrap_or_else(|_| "[]".to_string())
                .as_str(),
        ));
        this.as_mut().set_status(status);
        this.as_mut()
            .set_source_path(QString::from(path.to_string_lossy().as_ref()));
        this.as_mut().set_defaults_used(defaults_used);
    }

    pub fn load_from(self: Pin<&mut Self>, path: &QString) {
        let path_buf = PathBuf::from(path.to_string());
        let (settings, status, defaults_used) = load_from_path(&path_buf);
        let mut this = self;
        this.as_mut().set_panel_height(settings.panel_height);
        this.as_mut().set_panel_position(QString::from(settings.panel_position.as_str()));
        this.as_mut().set_panel_transparent(settings.panel_transparent);
        this.as_mut().set_panel_modules_json(QString::from(
            serde_json::to_string(&settings.panel_modules)
                .unwrap_or_else(|_| "[]".to_string())
                .as_str(),
        ));
        this.as_mut().set_launcher_width(settings.launcher_width);
        this.as_mut().set_launcher_max_results(settings.launcher_max_results);
        this.as_mut().set_launcher_show_icons(settings.launcher_show_icons);
        this.as_mut().set_theme_accent(QString::from(settings.theme_accent.as_str()));
        this.as_mut().set_theme_background(QString::from(settings.theme_background.as_str()));
        this.as_mut().set_theme_surface(QString::from(settings.theme_surface.as_str()));
        this.as_mut().set_font_family(QString::from(settings.font_family.as_str()));
        this.as_mut().set_font_size(settings.font_size);
        this.as_mut().set_binds_json(QString::from(
            serde_json::to_string(&settings.binds)
                .unwrap_or_else(|_| "[]".to_string())
                .as_str(),
        ));
        this.as_mut().set_status(status);
        this.as_mut()
            .set_source_path(QString::from(path_buf.to_string_lossy().as_ref()));
        this.as_mut().set_defaults_used(defaults_used);
    }

    pub fn path(&self) -> QString {
        QString::from(default_path().to_string_lossy().as_ref())
    }
}
