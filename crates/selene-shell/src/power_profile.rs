/// Power profiles -- powerprofilesctl wrapper.
//
/// The `PowerProfile` QObject mirrors power-profiles-daemon through
/// `powerprofilesctl get/list/set`. `cycle()` walks the available
/// profile list so a single button can rotate power-saver ->
/// balanced -> performance. The QML side (Dashboard controls tab +
/// Bar indicator dot) renders the current profile.

use core::pin::Pin;
use cxx_qt_lib::QString;
use std::process::Command;

/// power-profiles-daemon mirror.
#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(QString, current_profile)]
        #[qproperty(bool, available)]
        #[qproperty(QString, profiles_json)]
        #[qproperty(QString, status)]
        type PowerProfile = super::PowerProfileRust;

        #[qinvokable]
        fn refresh(self: Pin<&mut Self>);

        #[qinvokable]
        fn apply_profile(self: Pin<&mut Self>, name: &QString);

        #[qinvokable]
        fn cycle(self: Pin<&mut Self>);
    }
}

#[derive(Default)]
pub struct PowerProfileRust {
    current_profile: QString,
    available: bool,
    profiles_json: QString,
    status: QString,
}

fn run_ppctl(args: &[&str]) -> Option<String> {
    let out = Command::new("powerprofilesctl").args(args).output().ok()?;
    if !out.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

/// Profile names from `powerprofilesctl list`; entries look like
/// "* performance:" / "  balanced:" -- the active one is starred.
fn list_profiles() -> Vec<String> {
    let Some(text) = run_ppctl(&["list"]) else {
        return Vec::new();
    };
    let mut names = Vec::new();
    for line in text.lines() {
        let stripped = line.trim().trim_start_matches('*').trim();
        if let Some(name) = stripped.strip_suffix(':') {
            if !name.is_empty() && !name.contains(' ') {
                names.push(name.to_string());
            }
        }
    }
    names
}

impl qobject::PowerProfile {
    pub fn refresh(self: Pin<&mut Self>) {
        let mut this = self;
        let Some(current) = run_ppctl(&["get"]) else {
            this.as_mut().set_available(false);
            this.as_mut()
                .set_status(QString::from("powerprofilesctl unavailable"));
            return;
        };
        let profiles = list_profiles();
        this.as_mut().set_available(true);
        this.as_mut()
            .set_current_profile(QString::from(current.as_str()));
        this.as_mut().set_profiles_json(QString::from(
            serde_json::to_string(&profiles)
                .unwrap_or_else(|_| "[]".to_string())
                .as_str(),
        ));
        this.as_mut().set_status(QString::from("ok"));
    }

    pub fn apply_profile(self: Pin<&mut Self>, name: &QString) {
        let name = name.to_string();
        let mut this = self;
        if run_ppctl(&["set", &name]).is_none() {
            this.as_mut()
                .set_status(QString::from(format!("cannot set profile '{name}'")));
        }
        this.as_mut().refresh();
    }

    pub fn cycle(self: Pin<&mut Self>) {
        let profiles = list_profiles();
        if profiles.is_empty() {
            let mut this = self;
            this.as_mut()
                .set_status(QString::from("no profiles to cycle"));
            return;
        }
        let current = self.current_profile().to_string();
        let idx = profiles.iter().position(|p| *p == current).unwrap_or(0);
        let next = &profiles[(idx + 1) % profiles.len()];
        let qnext = QString::from(next.as_str());
        self.apply_profile(&qnext);
    }
}
