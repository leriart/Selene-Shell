/// Weather -- wttr.in scraper via a curl subprocess.
//
/// The `Weather` QObject shells out to `curl "wttr.in/?format=j1"`
/// on a dedicated thread (no network deps in Rust), parses the JSON
/// with serde_json and pushes the current conditions + a 3-day
/// forecast to QML through the cxx-qt queued bridge. Refreshes every
/// 10 minutes. The QML side (`WeatherPanel.qml`) renders the card.

use core::pin::Pin;
use cxx_qt::Threading;
use cxx_qt_lib::QString;
use std::process::Command;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

/// wttr.in weather mirror (dashboard weather tab + bar widget).
#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        // Current conditions
        #[qproperty(f64, temp)]
        #[qproperty(f64, temp_max)]
        #[qproperty(f64, temp_min)]
        #[qproperty(f64, feels_like)]
        #[qproperty(i32, weather_code)]
        #[qproperty(QString, weather_desc)]
        #[qproperty(f64, wind_speed)]
        #[qproperty(i32, humidity)]
        // Astronomy + day/night flag
        #[qproperty(QString, sunrise)]
        #[qproperty(QString, sunset)]
        #[qproperty(bool, is_day)]
        // 3-day forecast: [{date, max, min, code, desc}]
        #[qproperty(QString, forecast_json)]
        #[qproperty(QString, location)]
        // Diagnostics
        #[qproperty(bool, available)]
        #[qproperty(QString, status)]
        type Weather = super::WeatherRust;

        #[qinvokable]
        fn start_polling(self: Pin<&mut Self>);

        #[qinvokable]
        fn refresh_now(self: Pin<&mut Self>);

        #[qinvokable]
        fn apply_location(self: Pin<&mut Self>, location: &QString);
    }

    impl cxx_qt::Threading for Weather {}
}

#[derive(Default)]
pub struct WeatherRust {
    temp: f64,
    temp_max: f64,
    temp_min: f64,
    feels_like: f64,
    weather_code: i32,
    weather_desc: QString,
    wind_speed: f64,
    humidity: i32,
    sunrise: QString,
    sunset: QString,
    is_day: bool,
    forecast_json: QString,
    location: QString,
    available: bool,
    status: QString,
}

/// One parsed wttr.in report.
#[derive(Default, Clone)]
struct Report {
    temp: f64,
    temp_max: f64,
    temp_min: f64,
    feels_like: f64,
    weather_code: i32,
    weather_desc: String,
    wind_speed: f64,
    humidity: i32,
    sunrise: String,
    sunset: String,
    is_day: bool,
    forecast_json: String,
}

fn poll_started() -> &'static AtomicBool {
    static FLAG: AtomicBool = AtomicBool::new(false);
    &FLAG
}

/// Bumped by refresh_now() / apply_location() so the poll thread
/// re-fetches immediately instead of waiting out the 10 min window.
fn refresh_generation() -> &'static AtomicU64 {
    static GEN: AtomicU64 = AtomicU64::new(0);
    &GEN
}

fn location_slot() -> &'static Mutex<String> {
    static LOC: OnceLock<Mutex<String>> = OnceLock::new();
    LOC.get_or_init(|| Mutex::new(String::new()))
}

fn fetch_json(location: &str) -> Result<serde_json::Value, String> {
    // wttr.in geolocates by IP when the location segment is empty.
    let url = format!("wttr.in/{}?format=j1", location.trim());
    let out = Command::new("curl")
        .args(["-sf", "--max-time", "15", &url])
        .output()
        .map_err(|e| format!("curl: {e}"))?;
    if !out.status.success() {
        return Err(format!("curl exit {}", out.status));
    }
    serde_json::from_slice(&out.stdout).map_err(|e| format!("json: {e}"))
}

fn str_at(v: &serde_json::Value, key: &str) -> String {
    v.get(key)
        .and_then(|x| x.as_str())
        .unwrap_or("")
        .to_string()
}

fn f64_at(v: &serde_json::Value, key: &str) -> f64 {
    v.get(key)
        .and_then(|x| x.as_str())
        .and_then(|s| s.parse::<f64>().ok())
        .unwrap_or(0.0)
}

fn i32_at(v: &serde_json::Value, key: &str) -> i32 {
    v.get(key)
        .and_then(|x| x.as_str())
        .and_then(|s| s.parse::<i32>().ok())
        .unwrap_or(0)
}

/// First `.value` of a wttr.in `[{value: ...}]` wrapper array.
fn value_at(v: &serde_json::Value, key: &str) -> String {
    v.get(key)
        .and_then(|x| x.as_array())
        .and_then(|a| a.first())
        .map(|e| str_at(e, "value"))
        .unwrap_or_default()
}

/// "06:12 AM" -> minutes since midnight; None on parse failure.
fn parse_12h(s: &str) -> Option<u32> {
    let s = s.trim();
    let (time, ampm) = s.split_once(' ')?;
    let (h, m) = time.split_once(':')?;
    let mut h: u32 = h.parse().ok()?;
    let m: u32 = m.parse().ok()?;
    let ampm = ampm.trim().to_uppercase();
    if ampm == "PM" && h != 12 {
        h += 12;
    } else if ampm == "AM" && h == 12 {
        h = 0;
    }
    Some(h * 60 + m)
}

/// Local minutes-since-midnight, via `date` (matches island.rs: no
/// chrono dependency, one cheap subprocess per refresh).
fn local_minutes() -> Option<u32> {
    let out = Command::new("date").arg("+%H:%M").output().ok()?;
    if !out.status.success() {
        return None;
    }
    let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
    let (h, m) = s.split_once(':')?;
    Some(h.parse::<u32>().ok()? * 60 + m.parse::<u32>().ok()?)
}

fn parse_report(root: &serde_json::Value) -> Result<Report, String> {
    let current = root
        .get("current_condition")
        .and_then(|x| x.as_array())
        .and_then(|a| a.first())
        .ok_or("missing current_condition")?;

    let mut report = Report {
        temp: f64_at(current, "temp_C"),
        feels_like: f64_at(current, "FeelsLikeC"),
        weather_code: i32_at(current, "weatherCode"),
        weather_desc: value_at(current, "weatherDesc"),
        wind_speed: f64_at(current, "windspeedKmph"),
        humidity: i32_at(current, "humidity"),
        ..Report::default()
    };

    let days = root
        .get("weather")
        .and_then(|x| x.as_array())
        .cloned()
        .unwrap_or_default();

    let mut forecast: Vec<serde_json::Value> = Vec::new();
    for (i, day) in days.iter().enumerate() {
        let max = f64_at(day, "maxtempC");
        let min = f64_at(day, "mintempC");
        // Midday hourly slot carries the day's representative code/desc.
        let (code, desc) = day
            .get("hourly")
            .and_then(|x| x.as_array())
            .and_then(|a| a.get(a.len() / 2))
            .map(|h| (i32_at(h, "weatherCode"), value_at(h, "weatherDesc")))
            .unwrap_or((0, String::new()));
        if i == 0 {
            report.temp_max = max;
            report.temp_min = min;
            if let Some(astro) = day
                .get("astronomy")
                .and_then(|x| x.as_array())
                .and_then(|a| a.first())
            {
                report.sunrise = str_at(astro, "sunrise");
                report.sunset = str_at(astro, "sunset");
            }
        }
        forecast.push(serde_json::json!({
            "date": str_at(day, "date"),
            "max": max,
            "min": min,
            "code": code,
            "desc": desc,
        }));
    }
    report.forecast_json =
        serde_json::to_string(&forecast).unwrap_or_else(|_| "[]".to_string());

    // Day/night from the sunrise/sunset window; default to day when
    // any of the three times fails to parse.
    report.is_day = match (
        parse_12h(&report.sunrise),
        parse_12h(&report.sunset),
        local_minutes(),
    ) {
        (Some(rise), Some(set), Some(now)) => now >= rise && now < set,
        _ => true,
    };

    Ok(report)
}

fn push_report(qt: &cxx_qt::CxxQtThread<qobject::Weather>, report: Report) -> bool {
    let desc = QString::from(report.weather_desc.as_str());
    let sunrise = QString::from(report.sunrise.as_str());
    let sunset = QString::from(report.sunset.as_str());
    let forecast = QString::from(report.forecast_json.as_str());
    qt.queue(move |mut this| {
        this.as_mut().set_temp(report.temp);
        this.as_mut().set_temp_max(report.temp_max);
        this.as_mut().set_temp_min(report.temp_min);
        this.as_mut().set_feels_like(report.feels_like);
        this.as_mut().set_weather_code(report.weather_code);
        this.as_mut().set_weather_desc(desc);
        this.as_mut().set_wind_speed(report.wind_speed);
        this.as_mut().set_humidity(report.humidity);
        this.as_mut().set_sunrise(sunrise);
        this.as_mut().set_sunset(sunset);
        this.as_mut().set_is_day(report.is_day);
        this.as_mut().set_forecast_json(forecast);
        this.as_mut().set_available(true);
        this.as_mut().set_status(QString::from("ok"));
    })
    .is_ok()
}

fn poll_main(qt: cxx_qt::CxxQtThread<qobject::Weather>) {
    // Refresh every 10 minutes; wake up every second so refresh_now()
    // and location changes take effect promptly.
    const REFRESH_SECS: u64 = 600;
    let mut last_gen = u64::MAX; // force an immediate first fetch
    let mut countdown: u64 = 0;

    loop {
        let generation = refresh_generation().load(Ordering::SeqCst);
        if generation != last_gen || countdown == 0 {
            last_gen = generation;
            countdown = REFRESH_SECS;
            let location = location_slot()
                .lock()
                .map(|l| l.clone())
                .unwrap_or_default();
            match fetch_json(&location).and_then(|root| parse_report(&root)) {
                Ok(report) => {
                    if !push_report(&qt, report) {
                        return;
                    }
                }
                Err(err) => {
                    let msg = QString::from(format!("weather: {err}"));
                    if qt
                        .queue(move |mut this| {
                            this.as_mut().set_available(false);
                            this.as_mut().set_status(msg);
                        })
                        .is_err()
                    {
                        return;
                    }
                }
            }
        }
        countdown = countdown.saturating_sub(1);
        std::thread::sleep(Duration::from_secs(1));
    }
}

impl qobject::Weather {
    pub fn start_polling(self: Pin<&mut Self>) {
        if poll_started().swap(true, Ordering::SeqCst) {
            return; // already polling
        }
        let qt: cxx_qt::CxxQtThread<qobject::Weather> = self.as_ref().qt_thread();
        std::thread::Builder::new()
            .name("selene-weather".into())
            .spawn(move || poll_main(qt))
            .expect("selene: failed to spawn weather poll thread");
        let mut this = self;
        this.as_mut()
            .set_status(QString::from("fetching wttr.in"));
    }

    pub fn refresh_now(self: Pin<&mut Self>) {
        refresh_generation().fetch_add(1, Ordering::SeqCst);
        let mut this = self;
        this.as_mut().set_status(QString::from("refreshing"));
    }

    pub fn apply_location(self: Pin<&mut Self>, location: &QString) {
        let loc = location.to_string();
        if let Ok(mut slot) = location_slot().lock() {
            if *slot == loc {
                return;
            }
            *slot = loc.clone();
        }
        refresh_generation().fetch_add(1, Ordering::SeqCst);
        let mut this = self;
        this.as_mut().set_location(QString::from(loc.as_str()));
    }
}
