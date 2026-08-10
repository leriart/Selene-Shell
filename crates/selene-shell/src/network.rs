/// Network quick-settings -- Wi-Fi scan, connect, and status via nmcli.
//
/// The `Network` QObject parses `nmcli -t` output for active
/// connections, Wi-Fi list (SSID / signal / security), and writes
/// back through `nmcli radio wifi on/off` and `connect_ssid`.
/// The QML side (`NetworkPanel.qml`) renders a toggle, an active-
/// connection card, and a click-to-connect Wi-Fi list.

use core::pin::Pin;
use cxx_qt_lib::QString;
use std::process::Command;

/// Network quick settings via NetworkManager (`nmcli`). Exposes the active
/// connection, a small list of nearby Wi-Fi networks, and a toggle that
/// mirrors the radios when the system administrator hasn't locked them.
#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(bool, available)]
        #[qproperty(bool, wifi_enabled)]
        #[qproperty(bool, connected)]
        #[qproperty(QString, active_name)]
        #[qproperty(QString, active_ssid)]
        #[qproperty(QString, active_signal)]
        #[qproperty(QString, ipv4)]
        #[qproperty(QString, ifaces_json)]
        #[qproperty(QString, wifi_json)]
        #[qproperty(QString, status)]
        type Network = super::NetworkRust;

        #[qinvokable]
        fn refresh(self: Pin<&mut Self>);

        #[qinvokable]
        fn wifi_on(self: Pin<&mut Self>);

        #[qinvokable]
        fn wifi_off(self: Pin<&mut Self>);

        #[qinvokable]
        fn connect_ssid(self: Pin<&mut Self>, ssid: &QString, password: &QString);

        #[qinvokable]
        fn disconnect(self: Pin<&mut Self>);
    }
}

#[derive(Default)]
pub struct NetworkRust {
    available: bool,
    wifi_enabled: bool,
    connected: bool,
    active_name: QString,
    active_ssid: QString,
    active_signal: QString,
    ipv4: QString,
    ifaces_json: QString,
    wifi_json: QString,
    status: QString,
}

#[derive(serde::Serialize, Clone, Debug)]
struct Wifi {
    ssid: String,
    in_use: bool,
    signal: String,
    bars: String,
    security: String,
    band: String,
    rate: String,
    channel: String,
}

#[derive(serde::Serialize, Clone, Debug)]
struct Iface {
    name: String,
    kind: String,
    state: String,
    connection: String,
}

fn run_nmcli(args: &[&str]) -> Option<String> {
    let out = Command::new("nmcli")
        .args(args)
        .output()
        .ok()?;
    if !out.status.success() {
        let stderr = String::from_utf8_lossy(&out.stderr).trim().to_string();
        return Some(stderr);
    }
    let stdout = String::from_utf8_lossy(&out.stdout).to_string();
    Some(stdout)
}

fn parse_active() -> (String, String, String, String, bool, bool) {
    let raw = match run_nmcli(&["-t", "-f", "STATE,CONNECTION,TYPE", "general", "state"]) {
        Some(s) if !s.is_empty() => s,
        _ => return Default::default(),
    };
    let mut connected = false;
    let mut name = String::new();
    let mut kind = String::new();
    for line in raw.lines() {
        let fields: Vec<&str> = line.split(':').collect();
        if fields.len() >= 3 {
            let state = fields[0];
            if state == "connected" || state == "connected (local only)" {
                connected = true;
            }
            name = fields[1].to_string();
            kind = fields[2].to_string();
        }
    }

    let mut ssid = String::new();
    let mut signal = String::new();
    let mut ipv4 = String::new();

    if kind == "wifi" && !name.is_empty() {
        // Active signal / SSID
        if let Some(s) = run_nmcli(&["-t", "-f", "ACTIVE,SSID,SIGNAL", "device", "wifi"]) {
            for line in s.lines() {
                let fields: Vec<&str> = line.split(':').collect();
                if fields.len() >= 3 && fields[0] == "yes" {
                    ssid = fields[1].to_string();
                    signal = fields[2].to_string();
                    break;
                }
            }
        }
    }

    if let Some(s) = run_nmcli(&["-t", "-f", "IP4.ADDRESS", "device", "show"]) {
        for line in s.lines() {
            let fields: Vec<&str> = line.split(':').collect();
            if fields.len() >= 2 && !fields[1].is_empty() {
                ipv4 = fields[1].to_string();
                break;
            }
        }
    }

    let wifi_enabled = if let Some(s) = run_nmcli(&["radio", "wifi"]) {
        s.trim().eq_ignore_ascii_case("enabled")
    } else {
        false
    };

    (name, ssid, signal, ipv4, connected, wifi_enabled)
}

fn parse_wifi_list() -> Vec<Wifi> {
    let raw = match run_nmcli(&["-t", "-f", "IN-USE,BSSID,SSID,MODE,BAND,CHAN,RATE,SIGNAL,BARS,SECURITY", "device", "wifi", "list"]) {
        Some(s) if !s.is_empty() => s,
        _ => return Vec::new(),
    };
    let mut out = Vec::new();
    for line in raw.lines() {
        let f: Vec<&str> = line.split(':').collect();
        if f.len() < 10 {
            continue;
        }
        let ssid = f[2].to_string();
        if ssid.is_empty() {
            continue;
        }
        out.push(Wifi {
            ssid,
            in_use: f[0] == "*",
            signal: f[7].to_string(),
            bars: f[8].to_string(),
            security: f[9].to_string(),
            band: f[4].to_string(),
            rate: f[6].to_string(),
            channel: f[5].to_string(),
        });
    }
    out
}

fn parse_ifaces() -> Vec<Iface> {
    let raw = match run_nmcli(&["-t", "-f", "DEVICE,STATE,CONNECTION,TYPE", "device", "status"]) {
        Some(s) if !s.is_empty() => s,
        _ => return Vec::new(),
    };
    let mut out = Vec::new();
    for line in raw.lines() {
        let f: Vec<&str> = line.split(':').collect();
        if f.len() < 4 {
            continue;
        }
        out.push(Iface {
            name: f[0].to_string(),
            state: f[1].to_string(),
            connection: f[2].to_string(),
            kind: f[3].to_string(),
        });
    }
    out
}

impl qobject::Network {
    pub fn refresh(self: Pin<&mut Self>) {
        let mut this = self;

        // Probe nmcli availability quickly by checking radio wifi first.
        let probe = run_nmcli(&["general"]);
        let available = probe.is_some();

        let (name, ssid, signal, ipv4, connected, wifi_enabled) = if available {
            parse_active()
        } else {
            Default::default()
        };

        let wifi = if available && wifi_enabled {
            parse_wifi_list()
        } else {
            Vec::new()
        };
        let ifaces = if available { parse_ifaces() } else { Vec::new() };

        let wifi_json = serde_json::to_string(&wifi).unwrap_or_else(|_| "[]".to_string());
        let ifaces_json = serde_json::to_string(&ifaces).unwrap_or_else(|_| "[]".to_string());

        let status = if !available {
            "nmcli not reachable".to_string()
        } else if !wifi_enabled {
            "wifi off".to_string()
        } else if connected {
            format!("connected to {}{}", name, if !ipv4.is_empty() { format!(" ({ipv4})") } else { String::new() })
        } else {
            "disconnected".to_string()
        };

        this.as_mut().set_available(available);
        this.as_mut().set_wifi_enabled(wifi_enabled);
        this.as_mut().set_connected(connected);
        this.as_mut().set_active_name(QString::from(name.as_str()));
        this.as_mut().set_active_ssid(QString::from(ssid.as_str()));
        this.as_mut().set_active_signal(QString::from(signal.as_str()));
        this.as_mut().set_ipv4(QString::from(ipv4.as_str()));
        this.as_mut().set_ifaces_json(QString::from(ifaces_json.as_str()));
        this.as_mut().set_wifi_json(QString::from(wifi_json.as_str()));
        this.as_mut().set_status(QString::from(status.as_str()));
    }

    pub fn wifi_on(self: Pin<&mut Self>) {
        let mut this = self;
        if let Some(s) = run_nmcli(&["radio", "wifi", "on"]) {
            if s.is_empty() {
                this.as_mut().set_status(QString::from("wifi on"));
            } else {
                this.as_mut().set_status(QString::from(format!("wifi on: {s}")));
            }
        }
        this.as_mut().refresh();
    }

    pub fn wifi_off(self: Pin<&mut Self>) {
        let mut this = self;
        if let Some(s) = run_nmcli(&["radio", "wifi", "off"]) {
            if s.is_empty() {
                this.as_mut().set_status(QString::from("wifi off"));
            } else {
                this.as_mut().set_status(QString::from(format!("wifi off: {s}")));
            }
        }
        this.as_mut().refresh();
    }

    pub fn connect_ssid(self: Pin<&mut Self>, ssid: &QString, password: &QString) {
        let ssid = ssid.to_string();
        let password = password.to_string();
        if ssid.is_empty() {
            return;
        }
        let mut this = self;
        let result = if password.is_empty() {
            run_nmcli(&["device", "wifi", "connect", ssid.as_str()])
        } else {
            run_nmcli(&[
                "device", "wifi", "connect", ssid.as_str(),
                "password", password.as_str(),
            ])
        };
        match result {
            Some(s) if s.is_empty() => {
                this.as_mut()
                    .set_status(QString::from(format!("connecting to {ssid}")));
            }
            Some(other) => {
                this.as_mut()
                    .set_status(QString::from(format!("connect: {other}")));
            }
            None => {
                this.as_mut()
                    .set_status(QString::from(format!("connect failed: {ssid}")));
            }
        }
        this.as_mut().refresh();
    }

    pub fn disconnect(self: Pin<&mut Self>) {
        let mut this = self;
        let active = this.active_name().to_string();
        if active.is_empty() {
            return;
        }
        if let Some(s) = run_nmcli(&["device", "disconnect", active.as_str()]) {
            let status = if s.is_empty() {
                format!("disconnected {active}")
            } else {
                format!("disconnect: {s}")
            };
            this.as_mut().set_status(QString::from(status.as_str()));
        }
        this.as_mut().refresh();
    }
}
