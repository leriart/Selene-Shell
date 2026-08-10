use core::pin::Pin;
use cxx_qt_lib::QString;
use std::process::{Command, Stdio};
use std::io::Write;

/// Lock screen QObject. Provides `authenticate(username, password)` that
/// validates the password against the local PAM stack via `su`. On success,
/// the full-screen QML overlay closes; on failure, `attempts` increments
/// and the UI can show a shake / error animation.
///
/// Locking itself happens via `loginctl lock-session`, same as the
/// existing `Island.lock()` qinvokable, so this type only deals with the
/// **unlock** flow.
#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(i32, attempts)]
        #[qproperty(bool, locked)]
        #[qproperty(QString, status)]
        #[qproperty(QString, username)]
        type Lock = super::LockRust;

        #[qinvokable]
        fn authenticate(self: Pin<&mut Self>, username: &QString, password: &QString) -> bool;

        #[qinvokable]
        fn lock(self: Pin<&mut Self>);

        #[qinvokable]
        fn unlock(self: Pin<&mut Self>);

        #[qinvokable]
        fn resolve_username(self: Pin<&mut Self>);
    }
}

impl LockRust {
    fn default_with_user() -> Self {
        Self {
            attempts: 0,
            locked: false,
            status: QString::from("locked"),
            username: QString::from(whoami().as_str()),
        }
    }
}

impl Default for LockRust {
    fn default() -> Self {
        Self::default_with_user()
    }
}

#[derive(Clone)]
pub struct LockRust {
    attempts: i32,
    locked: bool,
    status: QString,
    username: QString,
}

fn whoami() -> String {
    std::env::var("USER")
        .unwrap_or_else(|_| String::from("root"))
}

impl qobject::Lock {
    pub fn authenticate(self: Pin<&mut Self>, username: &QString, password: &QString) -> bool {
        let user = if username.to_string().is_empty() {
            whoami()
        } else {
            username.to_string()
        };
        let pass = password.to_string();

        if user.is_empty() || pass.is_empty() {
            let mut this = self;
            this.as_mut().increment_attempts();
            this.as_mut()
                .set_status(QString::from("empty credentials"));
            return false;
        }

        // Validate via `su -c true $user`. If the password matches,
        // `su` exits 0 after running `true`.
        let mut child = match Command::new("su")
            .arg("-c")
            .arg("true")
            .arg(&user)
            .stdin(Stdio::piped())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
        {
            Ok(c) => c,
            Err(err) => {
                let mut this = self;
                this.as_mut().increment_attempts();
                this.as_mut()
                    .set_status(QString::from(format!("su unavailable: {err}")));
                return false;
            }
        };

        if let Some(stdin) = child.stdin.as_mut() {
            let _ = writeln!(stdin, "{pass}");
        }

        let status = child.wait();
        let success = status.map(|s| s.success()).unwrap_or(false);

        let mut this = self;
        if success {
            // Clear state inline to avoid double-borrow of this.
            this.as_mut().set_locked(false);
            this.as_mut().set_attempts(0);
            this.as_mut()
                .set_status(QString::from("unlocked"));
            return true;
        }

        this.as_mut().increment_attempts();
        false
    }

    pub fn lock(self: Pin<&mut Self>) {
        // Use loginctl to lock the session (handled by logind).
        let _ = Command::new("loginctl")
            .arg("lock-session")
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn();
        let mut this = self;
        this.as_mut().set_locked(true);
        this.as_mut()
            .set_status(QString::from("locked"));
    }

    pub fn unlock(self: Pin<&mut Self>) {
        let _ = Command::new("loginctl")
            .arg("unlock-session")
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn();
        let mut this = self;
        this.as_mut().set_locked(false);
        this.as_mut().set_attempts(0);
        this.as_mut()
            .set_status(QString::from("unlocked"));
    }

    pub fn resolve_username(self: Pin<&mut Self>) {
        let user = whoami();
        self.set_username(QString::from(user.as_str()));
    }

    fn increment_attempts(self: Pin<&mut Self>) {
        let current = *self.attempts();
        let next = current + 1;
        let msg = QString::from(format!("incorrect password (attempt {next})").as_str());
        let mut this = self;
        this.as_mut().set_attempts(next);
        this.as_mut().set_status(msg);
    }
}
