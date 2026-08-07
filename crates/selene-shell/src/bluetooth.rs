use core::pin::Pin;
use cxx_qt_lib::QString;
use std::process::Command;

/// Bluetooth quick settings. Talks to `bluetoothctl` via subprocess; the
/// daemon itself is short-lived enough that we don't keep a child around.
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
        #[qproperty(bool, powered)]
        #[qproperty(bool, discoverable)]
        #[qproperty(QString, adapter_name)]
        #[qproperty(QString, adapter_mac)]
        #[qproperty(QString, devices_json)]
        #[qproperty(QString, status)]
        type Bluetooth = super::BluetoothRust;

        #[qinvokable]
        fn refresh(self: Pin<&mut Self>);

        #[qinvokable]
        fn power_on(self: Pin<&mut Self>);

        #[qinvokable]
        fn power_off(self: Pin<&mut Self>);

        #[qinvokable]
        fn toggle(self: Pin<&mut Self>);

        #[qinvokable]
        fn connect_device(self: Pin<&mut Self>, mac: &QString);

        #[qinvokable]
        fn disconnect_device(self: Pin<&mut Self>, mac: &QString);

        #[qinvokable]
        fn pair_device(self: Pin<&mut Self>, mac: &QString);
    }
}

#[derive(Default)]
pub struct BluetoothRust {
    available: bool,
    powered: bool,
    discoverable: bool,
    adapter_name: QString,
    adapter_mac: QString,
    devices_json: QString,
    status: QString,
}

#[derive(serde::Serialize, Clone, Debug)]
struct BtDevice {
    mac: String,
    name: String,
    paired: bool,
    connected: bool,
    trusted: bool,
    rssi: String,
    device_type: String,
}

fn run_bt(args: &[&str]) -> Option<String> {
    let out = Command::new("bluetoothctl")
        .args(args)
        .output()
        .ok()?;
    if !out.status.success() {
        let stderr = String::from_utf8_lossy(&out.stderr).trim().to_string();
        if !stderr.is_empty() {
            return Some(stderr);
        }
    }
    Some(String::from_utf8_lossy(&out.stdout).to_string())
}

fn parse_show() -> (bool, bool, bool, String, String) {
    let raw = match run_bt(&["show"]) {
        Some(s) if !s.is_empty() => s,
        _ => return (false, false, false, String::new(), String::new()),
    };

    let mut powered = false;
    let mut discoverable = false;
    let mut name = String::new();
    let mut mac = String::new();

    for line in raw.lines() {
        let line = line.trim();
        if let Some(v) = line.strip_prefix("Powered: ") {
            powered = v.trim().eq_ignore_ascii_case("yes");
        } else if let Some(v) = line.strip_prefix("Discoverable: ") {
            discoverable = v.trim().eq_ignore_ascii_case("yes");
        } else if let Some(v) = line.strip_prefix("Name: ") {
            name = v.trim().to_string();
        } else if let Some(v) = line.strip_prefix("Alias: ") {
            if name.is_empty() {
                name = v.trim().to_string();
            }
        }
        // The MAC is implied by the controller name; we parse it from the
        // first non-empty "Controller ..." line instead.
    }

    // Pull the MAC from `list` or the first "Controller" line of `show`.
    if let Some(s) = run_bt(&["list"]) {
        for line in s.lines() {
            if let Some(rest) = line.trim().strip_prefix("Controller ") {
                let mut parts = rest.split_whitespace();
                if let Some(m) = parts.next() {
                    mac = m.to_string();
                    if name.is_empty() {
                        // Alias is the second token, e.g. "10:91:... HUAWEI"
                        if let Some(n) = parts.next() {
                            name = n.to_string();
                        }
                    }
                }
                break;
            }
        }
    }

    (true, powered, discoverable, name, mac)
}

fn parse_devices() -> Vec<BtDevice> {
    let raw = match run_bt(&["devices", "-v"]) {
        Some(s) if !s.is_empty() => s,
        _ => return Vec::new(),
    };

    let mut out: Vec<BtDevice> = Vec::new();
    let mut current: Option<BtDevice> = None;

    for raw_line in raw.lines() {
        let line = raw_line.trim();
        if let Some(rest) = line.strip_prefix("Device ") {
            // Flush previous
            if let Some(c) = current.take() {
                out.push(c);
            }
            let mac = rest.split_whitespace().next().unwrap_or("").to_string();
            current = Some(BtDevice {
                mac,
                name: String::new(),
                paired: false,
                connected: false,
                trusted: false,
                rssi: String::new(),
                device_type: String::new(),
            });
        } else if let Some(c) = current.as_mut() {
            if let Some(v) = line.strip_prefix("Name: ") {
                c.name = v.trim().to_string();
            } else if let Some(v) = line.strip_prefix("Alias: ") {
                if c.name.is_empty() {
                    c.name = v.trim().to_string();
                }
            } else if let Some(v) = line.strip_prefix("Paired: ") {
                c.paired = v.trim().eq_ignore_ascii_case("yes");
            } else if let Some(v) = line.strip_prefix("Connected: ") {
                c.connected = v.trim().eq_ignore_ascii_case("yes");
            } else if let Some(v) = line.strip_prefix("Trusted: ") {
                c.trusted = v.trim().eq_ignore_ascii_case("yes");
            } else if let Some(v) = line.strip_prefix("RSSI: ") {
                c.rssi = v.trim().to_string();
            } else if let Some(v) = line.strip_prefix("Icon: ") {
                c.device_type = v.trim().to_string();
            }
        }
    }
    if let Some(c) = current.take() {
        out.push(c);
    }
    out
}

impl qobject::Bluetooth {
    pub fn refresh(self: Pin<&mut Self>) {
        let mut this = self;
        let (available, powered, discoverable, name, mac) = parse_show();
        let devices = if available && powered {
            parse_devices()
        } else {
            Vec::new()
        };
        let json = serde_json::to_string(&devices).unwrap_or_else(|_| "[]".to_string());

        let status = if !available {
            "bluetoothctl not reachable".to_string()
        } else if !powered {
            "off".to_string()
        } else {
            let connected = devices.iter().filter(|d| d.connected).count();
            format!("on; {} paired, {} connected", devices.len(), connected)
        };

        this.as_mut().set_available(available);
        this.as_mut().set_powered(powered);
        this.as_mut().set_discoverable(discoverable);
        this.as_mut().set_adapter_name(QString::from(name.as_str()));
        this.as_mut().set_adapter_mac(QString::from(mac.as_str()));
        this.as_mut().set_devices_json(QString::from(json.as_str()));
        this.as_mut().set_status(QString::from(status.as_str()));
    }

    pub fn power_on(self: Pin<&mut Self>) {
        let _ = run_bt(&["power", "on"]);
        self.refresh();
    }

    pub fn power_off(self: Pin<&mut Self>) {
        let _ = run_bt(&["power", "off"]);
        self.refresh();
    }

    pub fn toggle(self: Pin<&mut Self>) {
        if *self.powered() {
            self.power_off();
        } else {
            self.power_on();
        }
    }

    pub fn connect_device(self: Pin<&mut Self>, mac: &QString) {
        let mac = mac.to_string();
        if mac.is_empty() {
            return;
        }
        let mut this = self;
        let _ = run_bt(&["connect", &mac]);
        this.as_mut()
            .set_status(QString::from(format!("connect -> {mac}")));
        this.as_mut().refresh();
    }

    pub fn disconnect_device(self: Pin<&mut Self>, mac: &QString) {
        let mac = mac.to_string();
        if mac.is_empty() {
            return;
        }
        let mut this = self;
        let _ = run_bt(&["disconnect", &mac]);
        this.as_mut()
            .set_status(QString::from(format!("disconnect -> {mac}")));
        this.as_mut().refresh();
    }

    pub fn pair_device(self: Pin<&mut Self>, mac: &QString) {
        let mac = mac.to_string();
        if mac.is_empty() {
            return;
        }
        let mut this = self;
        let _ = run_bt(&["pair", &mac]);
        let _ = run_bt(&["trust", &mac]);
        this.as_mut()
            .set_status(QString::from(format!("pair -> {mac}")));
        this.as_mut().refresh();
    }
}
