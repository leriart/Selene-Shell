/// User configuration -- Lua-driven settings loaded from ~/.config/selene/init.lua.
//
/// The `Config` QObject embeds Lua 5.4 via mlua, exposes every
/// field as a \#[qproperty], and watches the file for changes via
/// inotify. The QML side (`SettingsPanel.qml`) allows live editing
/// and round-trips through `set_value` / `save`.

use core::pin::Pin;
use cxx_qt::Threading;
use cxx_qt_lib::QString;
use mlua::Lua;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};

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
        #[qproperty(QString, theme_preset)]
        #[qproperty(QString, animation_profile)]
        #[qproperty(bool, palette_follow_wallpaper)]
        // Font
        #[qproperty(QString, font_family)]
        #[qproperty(i32, font_size)]
        // Dashboard
        #[qproperty(bool, dashboard_enabled)]
        #[qproperty(i32, dashboard_width)]
        // Overview
        #[qproperty(bool, overview_enabled)]
        #[qproperty(i32, overview_columns)]
        // Weather
        #[qproperty(bool, weather_enabled)]
        #[qproperty(QString, weather_location)]
        #[qproperty(QString, weather_unit)]
        // Performance modes (JSON blobs consumed by GameFocusMode.qml)
        #[qproperty(QString, game_mode_json)]
        #[qproperty(QString, focus_mode_json)]
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
        fn save(self: Pin<&mut Self>) -> bool;

        #[qinvokable]
        fn set_value(self: Pin<&mut Self>, key: &QString, value: &QString);

        #[qinvokable]
        fn start_watcher(self: Pin<&mut Self>);

        #[qinvokable]
        fn path(&self) -> QString;
    }

    impl cxx_qt::Threading for Config {}
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
    pub theme_preset: String,
    pub animation_profile: String,
    pub palette_follow_wallpaper: bool,
    pub font_family: String,
    pub font_size: i32,
    pub dashboard_enabled: bool,
    pub dashboard_width: i32,
    pub overview_enabled: bool,
    pub overview_columns: i32,
    pub weather_enabled: bool,
    pub weather_location: String,
    pub weather_unit: String,
    pub game_mode: PerformanceMode,
    pub focus_mode: PerformanceMode,
    pub binds: Vec<String>,
}

/// One `performance.game_mode` / `performance.focus_mode` block.
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct PerformanceMode {
    pub zero_gaps: bool,
    pub disable_blur: bool,
    pub disable_shadow: bool,
    pub disable_animations: bool,
    pub dnd: bool,
    pub caffeine: bool,
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
            theme_accent: "#e74c3c".to_string(),
            theme_background: "#0a0a0a".to_string(),
            theme_surface: "#111111".to_string(),
            theme_preset: "new-moon".to_string(),
            animation_profile: "m3".to_string(),
            palette_follow_wallpaper: false,
            font_family: "Inter".to_string(),
            font_size: 13,
            dashboard_enabled: true,
            dashboard_width: 920,
            overview_enabled: true,
            overview_columns: 5,
            weather_enabled: true,
            weather_location: String::new(),
            weather_unit: "C".to_string(),
            game_mode: PerformanceMode {
                zero_gaps: true,
                disable_blur: true,
                disable_shadow: true,
                disable_animations: true,
                dnd: false,
                caffeine: false,
            },
            focus_mode: PerformanceMode {
                zero_gaps: true,
                disable_blur: false,
                disable_shadow: false,
                disable_animations: false,
                dnd: true,
                caffeine: true,
            },
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
    theme_preset: QString,
    animation_profile: QString,
    palette_follow_wallpaper: bool,
    font_family: QString,
    font_size: i32,
    dashboard_enabled: bool,
    dashboard_width: i32,
    overview_enabled: bool,
    overview_columns: i32,
    weather_enabled: bool,
    weather_location: QString,
    weather_unit: QString,
    game_mode_json: QString,
    focus_mode_json: QString,
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
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/"));
    home.join(".config").join("selene").join("init.lua")
}

fn lookup(table: &mlua::Table, key: &str) -> Option<mlua::Value> {
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
            if let Ok((_, val)) = pair
                && let mlua::Value::String(s) = val {
                    out.push(s.to_string_lossy().to_string());
                }
        }
        if !out.is_empty() {
            return out;
        }
    }
    default.iter().map(|s| s.to_string()).collect()
}

fn performance_mode_field(table: &mlua::Table, default: &PerformanceMode) -> PerformanceMode {
    PerformanceMode {
        zero_gaps: bool_field(table, "zero_gaps", default.zero_gaps),
        disable_blur: bool_field(table, "disable_blur", default.disable_blur),
        disable_shadow: bool_field(table, "disable_shadow", default.disable_shadow),
        disable_animations: bool_field(table, "disable_animations", default.disable_animations),
        dnd: bool_field(table, "dnd", default.dnd),
        caffeine: bool_field(table, "caffeine", default.caffeine),
    }
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
        out.theme_preset = string_field(&t, "preset", &out.theme_preset);
        out.animation_profile = string_field(&t, "animation_profile",
                                             &out.animation_profile);
        out.palette_follow_wallpaper = bool_field(
            &t, "follow_wallpaper", out.palette_follow_wallpaper,
        );
    }
    if let Some(f) = table_field(&table, "font") {
        out.font_family = string_field(&f, "family", &out.font_family);
        out.font_size = integer_field(&f, "size", out.font_size as i64) as i32;
    }
    if let Some(d) = table_field(&table, "dashboard") {
        out.dashboard_enabled = bool_field(&d, "enabled", out.dashboard_enabled);
        out.dashboard_width = integer_field(&d, "width", out.dashboard_width as i64) as i32;
    }
    if let Some(o) = table_field(&table, "overview") {
        out.overview_enabled = bool_field(&o, "enabled", out.overview_enabled);
        out.overview_columns = integer_field(&o, "columns", out.overview_columns as i64) as i32;
    }
    if let Some(w) = table_field(&table, "weather") {
        out.weather_enabled = bool_field(&w, "enabled", out.weather_enabled);
        out.weather_location = string_field(&w, "location", &out.weather_location);
        out.weather_unit = string_field(&w, "unit", &out.weather_unit);
    }
    if let Some(perf) = table_field(&table, "performance") {
        if let Some(g) = table_field(&perf, "game_mode") {
            out.game_mode = performance_mode_field(&g, &out.game_mode);
        }
        if let Some(f) = table_field(&perf, "focus_mode") {
            out.focus_mode = performance_mode_field(&f, &out.focus_mode);
        }
    }
    out.binds = string_list_field(
        &table,
        "binds",
        &out.binds.iter().map(|s| s.as_str()).collect::<Vec<_>>(),
    );

    (out, QString::from("ok"), false)
}

fn apply_settings(this: Pin<&mut qobject::Config>, settings: &Settings, status: QString, path: &PathBuf, defaults_used: bool) {
    let mut this = this;
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
    this.as_mut().set_theme_preset(QString::from(settings.theme_preset.as_str()));
    this.as_mut().set_animation_profile(QString::from(
        settings.animation_profile.as_str(),
    ));
    this.as_mut().set_palette_follow_wallpaper(settings.palette_follow_wallpaper);
    this.as_mut().set_font_family(QString::from(settings.font_family.as_str()));
    this.as_mut().set_font_size(settings.font_size);
    this.as_mut().set_dashboard_enabled(settings.dashboard_enabled);
    this.as_mut().set_dashboard_width(settings.dashboard_width);
    this.as_mut().set_overview_enabled(settings.overview_enabled);
    this.as_mut().set_overview_columns(settings.overview_columns);
    this.as_mut().set_weather_enabled(settings.weather_enabled);
    this.as_mut().set_weather_location(QString::from(settings.weather_location.as_str()));
    this.as_mut().set_weather_unit(QString::from(settings.weather_unit.as_str()));
    this.as_mut().set_game_mode_json(QString::from(
        serde_json::to_string(&settings.game_mode)
            .unwrap_or_else(|_| "{}".to_string())
            .as_str(),
    ));
    this.as_mut().set_focus_mode_json(QString::from(
        serde_json::to_string(&settings.focus_mode)
            .unwrap_or_else(|_| "{}".to_string())
            .as_str(),
    ));
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

fn lua_quote(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            other => out.push(other),
        }
    }
    out.push('"');
    out
}

fn lua_string_list(items: &[String]) -> String {
    let body = items
        .iter()
        .map(|s| lua_quote(s))
        .collect::<Vec<_>>()
        .join(", ");
    format!("{{ {body} }}")
}

fn serialize_to_lua(s: &Settings) -> String {
    format!(
        r#"-- Selene configuration.
-- Generated by `Config.save()`; safe to edit by hand.

return {{
    panel = {{
        height = {panel_height},
        position = {panel_position},
        transparent = {panel_transparent},
        modules = {panel_modules},
    }},
    launcher = {{
        width = {launcher_width},
        max_results = {launcher_max_results},
        show_icons = {launcher_show_icons},
    }},
    theme = {{
        accent = {theme_accent},
        background = {theme_background},
        surface = {theme_surface},
        preset = {theme_preset},
        animation_profile = {animation_profile},
        follow_wallpaper = {follow_wallpaper},
    }},
    font = {{
        family = {font_family},
        size = {font_size},
    }},
    dashboard = {{
        enabled = {dashboard_enabled},
        width = {dashboard_width},
    }},
    overview = {{
        enabled = {overview_enabled},
        columns = {overview_columns},
    }},
    weather = {{
        enabled = {weather_enabled},
        location = {weather_location},
        unit = {weather_unit},
    }},
    performance = {{
        game_mode = {game_mode},
        focus_mode = {focus_mode},
    }},
    binds = {binds},
}}
"#,
        panel_height = s.panel_height,
        panel_position = lua_quote(&s.panel_position),
        panel_transparent = s.panel_transparent,
        panel_modules = lua_string_list(&s.panel_modules),
        launcher_width = s.launcher_width,
        launcher_max_results = s.launcher_max_results,
        launcher_show_icons = s.launcher_show_icons,
        theme_accent = lua_quote(&s.theme_accent),
        theme_background = lua_quote(&s.theme_background),
        theme_surface = lua_quote(&s.theme_surface),
        theme_preset = lua_quote(&s.theme_preset),
        animation_profile = lua_quote(&s.animation_profile),
        follow_wallpaper = s.palette_follow_wallpaper,
        font_family = lua_quote(&s.font_family),
        font_size = s.font_size,
        dashboard_enabled = s.dashboard_enabled,
        dashboard_width = s.dashboard_width,
        overview_enabled = s.overview_enabled,
        overview_columns = s.overview_columns,
        weather_enabled = s.weather_enabled,
        weather_location = lua_quote(&s.weather_location),
        weather_unit = lua_quote(&s.weather_unit),
        game_mode = lua_performance_mode(&s.game_mode),
        focus_mode = lua_performance_mode(&s.focus_mode),
        binds = lua_string_list(&s.binds),
    )
}

fn lua_performance_mode(m: &PerformanceMode) -> String {
    format!(
        "{{ zero_gaps = {}, disable_blur = {}, disable_shadow = {}, disable_animations = {}, dnd = {}, caffeine = {} }}",
        m.zero_gaps, m.disable_blur, m.disable_shadow, m.disable_animations, m.dnd, m.caffeine,
    )
}

fn current_settings(cfg: &qobject::Config) -> Settings {
    let modules_json = cfg.panel_modules_json().to_string();
    let binds_json = cfg.binds_json().to_string();
    Settings {
        panel_height: *cfg.panel_height(),
        panel_position: cfg.panel_position().to_string(),
        panel_transparent: *cfg.panel_transparent(),
        panel_modules: serde_json::from_str(&modules_json).unwrap_or_default(),
        launcher_width: *cfg.launcher_width(),
        launcher_max_results: *cfg.launcher_max_results(),
        launcher_show_icons: *cfg.launcher_show_icons(),
        theme_accent: cfg.theme_accent().to_string(),
        theme_background: cfg.theme_background().to_string(),
        theme_surface: cfg.theme_surface().to_string(),
        theme_preset: cfg.theme_preset().to_string(),
        animation_profile: cfg.animation_profile().to_string(),
        palette_follow_wallpaper: *cfg.palette_follow_wallpaper(),
        font_family: cfg.font_family().to_string(),
        font_size: *cfg.font_size(),
        dashboard_enabled: *cfg.dashboard_enabled(),
        dashboard_width: *cfg.dashboard_width(),
        overview_enabled: *cfg.overview_enabled(),
        overview_columns: *cfg.overview_columns(),
        weather_enabled: *cfg.weather_enabled(),
        weather_location: cfg.weather_location().to_string(),
        weather_unit: cfg.weather_unit().to_string(),
        game_mode: serde_json::from_str(&cfg.game_mode_json().to_string())
            .unwrap_or_else(|_| Settings::default().game_mode),
        focus_mode: serde_json::from_str(&cfg.focus_mode_json().to_string())
            .unwrap_or_else(|_| Settings::default().focus_mode),
        binds: serde_json::from_str(&binds_json).unwrap_or_default(),
    }
}

impl qobject::Config {
    pub fn reload(self: Pin<&mut Self>) {
        let path = default_path();
        let (settings, status, defaults_used) = load_from_path(&path);
        apply_settings(self, &settings, status, &path, defaults_used);
    }

    pub fn load_from(self: Pin<&mut Self>, path: &QString) {
        let path_buf = PathBuf::from(path.to_string());
        let (settings, status, defaults_used) = load_from_path(&path_buf);
        apply_settings(self, &settings, status, &path_buf, defaults_used);
    }

    pub fn save(self: Pin<&mut Self>) -> bool {
        let settings = current_settings(&self);
        let raw_path = self.source_path().to_string();
        let path = if raw_path.is_empty() {
            default_path()
        } else {
            PathBuf::from(raw_path)
        };
        if let Some(parent) = path.parent()
            && std::fs::create_dir_all(parent).is_err() {
                let mut this = self;
                this.as_mut()
                    .set_status(QString::from("save: cannot create config dir"));
                return false;
            }
        let body = serialize_to_lua(&settings);
        match std::fs::write(&path, body) {
            Ok(()) => {
                let mut this = self;
                this.as_mut()
                    .set_status(QString::from(format!("saved {}", path.display())));
                this.as_mut().set_defaults_used(false);
                true
            }
            Err(err) => {
                let mut this = self;
                this.as_mut()
                    .set_status(QString::from(format!("save error: {err}")));
                false
            }
        }
    }

    pub fn set_value(self: Pin<&mut Self>, key: &QString, value: &QString) {
        let k = key.to_string();
        let v = value.to_string();
        let mut this = self;
        match k.as_str() {
            "panel.height" => {
                if let Ok(n) = v.parse::<i32>() {
                    this.as_mut().set_panel_height(n);
                }
            }
            "panel.position" => this.as_mut().set_panel_position(QString::from(v.as_str())),
            "panel.transparent" => {
                this.as_mut()
                    .set_panel_transparent(matches!(v.as_str(), "true" | "1" | "yes"))
            }
            "launcher.width" => {
                if let Ok(n) = v.parse::<i32>() {
                    this.as_mut().set_launcher_width(n);
                }
            }
            "launcher.max_results" => {
                if let Ok(n) = v.parse::<i32>() {
                    this.as_mut().set_launcher_max_results(n);
                }
            }
            "launcher.show_icons" => {
                this.as_mut()
                    .set_launcher_show_icons(matches!(v.as_str(), "true" | "1" | "yes"))
            }
            "theme.accent" => this.as_mut().set_theme_accent(QString::from(v.as_str())),
            "theme.background" => this.as_mut().set_theme_background(QString::from(v.as_str())),
            "theme.surface" => this.as_mut().set_theme_surface(QString::from(v.as_str())),
            "theme.preset" => this.as_mut().set_theme_preset(QString::from(v.as_str())),
            "theme.animation_profile" => this
                .as_mut()
                .set_animation_profile(QString::from(v.as_str())),
            "theme.follow_wallpaper" => {
                this.as_mut()
                    .set_palette_follow_wallpaper(matches!(v.as_str(), "true" | "1" | "yes"))
            }
            "dashboard.enabled" => {
                this.as_mut()
                    .set_dashboard_enabled(matches!(v.as_str(), "true" | "1" | "yes"))
            }
            "dashboard.width" => {
                if let Ok(n) = v.parse::<i32>() {
                    this.as_mut().set_dashboard_width(n);
                }
            }
            "overview.enabled" => {
                this.as_mut()
                    .set_overview_enabled(matches!(v.as_str(), "true" | "1" | "yes"))
            }
            "overview.columns" => {
                if let Ok(n) = v.parse::<i32>() {
                    this.as_mut().set_overview_columns(n);
                }
            }
            "weather.enabled" => {
                this.as_mut()
                    .set_weather_enabled(matches!(v.as_str(), "true" | "1" | "yes"))
            }
            "weather.location" => {
                this.as_mut().set_weather_location(QString::from(v.as_str()))
            }
            "weather.unit" => this.as_mut().set_weather_unit(QString::from(v.as_str())),
            "font.family" => this.as_mut().set_font_family(QString::from(v.as_str())),
            "font.size" => {
                if let Ok(n) = v.parse::<i32>() {
                    this.as_mut().set_font_size(n);
                }
            }
            _ => {
                this.as_mut()
                    .set_status(QString::from(format!("set_value: unknown key '{k}'")));
            }
        }
    }

    pub fn path(&self) -> QString {
        QString::from(default_path().to_string_lossy().as_ref())
    }

    pub fn start_watcher(self: Pin<&mut Self>) {
        static STARTED: AtomicBool = AtomicBool::new(false);
        if STARTED.swap(true, Ordering::SeqCst) {
            return;
        }
        let qt: cxx_qt::CxxQtThread<qobject::Config> = self.as_ref().qt_thread();
        let path = default_path();
        std::thread::Builder::new()
            .name("selene-config-watcher".into())
            .spawn(move || watch_config(path, qt))
            .expect("selene: failed to spawn config watcher thread");
    }
}

fn watch_config(path: PathBuf, qt: cxx_qt::CxxQtThread<qobject::Config>) {
    use notify::Watcher;
    use std::sync::mpsc;
    use std::time::Duration;

    let parent = path.parent().unwrap_or(&path).to_path_buf();
    let file_name = path
        .file_name()
        .map(|s| s.to_os_string())
        .unwrap_or_default();

    let (tx, rx) = mpsc::channel::<()>();

    let Ok(mut watcher) = notify::recommended_watcher(move |res: notify::Result<notify::Event>| {
        if let Ok(event) = res
            && event
                .paths
                .iter()
                .any(|p| p.file_name() == Some(&file_name))
            {
                let _ = tx.send(());
            }
    }) else {
        let _ = qt.queue(|mut c| {
            c.as_mut().set_status(QString::from("watcher: cannot create notifier"));
        });
        return;
    };

    if let Err(err) = watcher.watch(&parent, notify::RecursiveMode::NonRecursive) {
        let _ = qt.queue(move |mut c| {
            c.as_mut()
                .set_status(QString::from(format!("watcher: {err}")));
        });
        return;
    }

    let _ = qt.queue(|mut c| {
        c.as_mut()
            .set_status(QString::from("watching init.lua for changes"));
    });

    // Debounce: collect events for 250ms then trigger one reload.
    while rx.recv_timeout(Duration::from_millis(250)).is_ok() {
        // Drain every event that arrives within the debounce window.
        while rx.recv_timeout(Duration::from_millis(50)).is_ok() {}
        let _ = qt.queue(|mut c| {
            c.as_mut().reload();
        });
    }
}
