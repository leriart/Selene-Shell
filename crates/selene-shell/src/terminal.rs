/// Terminal -- embedded PTY for a QML view (Hax terminal port).
///
/// The `Terminal` QObject spawns `$SHELL` (or a custom command) inside
/// a real PTY and exposes:
///
///   * `output_lines`     last N output lines as a JSON array
///   * `output_delta`     buffered increment since last read (JSON array)
///   * `running`          true while the child is alive
///   * `pid`              child process id
///
/// The shell runs on a dedicated thread that drains the PTY master fd
/// and pushes chunks into a ring buffer. QML reads `output_lines` and
/// renders a scrolling view. `write(data)` feeds keystrokes into the
/// PTY master; `resize(cols, rows)` calls TIOCSWINSZ on the master.
use core::pin::Pin;
use cxx_qt_lib::QString;
use std::io::Read;
use std::os::unix::io::{AsRawFd, RawFd};
use std::os::unix::process::CommandExt;
use std::process::Command;
use std::sync::Mutex;
use std::thread;

use cxx_qt::Threading;

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(QString, output_lines)]
        #[qproperty(QString, output_delta)]
        #[qproperty(QString, command)]
        #[qproperty(i32, pid)]
        #[qproperty(bool, running)]
        #[qproperty(i32, exit_code)]
        #[qproperty(QString, status)]
        type Terminal = super::TerminalRust;

        #[qinvokable]
        fn spawn_default(self: Pin<&mut Self>);

        #[qinvokable]
        fn spawn(self: Pin<&mut Self>, cmd: &QString, args: &QString);

        #[qinvokable]
        fn write(self: Pin<&mut Self>, data: &QString);

        #[qinvokable]
        fn write_bytes(self: Pin<&mut Self>, data: &[u8]);

        #[qinvokable]
        fn resize(self: Pin<&mut Self>, cols: i32, rows: i32);

        #[qinvokable]
        fn clear(self: Pin<&mut Self>);

        #[qinvokable]
        fn close(self: Pin<&mut Self>);
    }

    impl cxx_qt::Threading for Terminal {}
}

/// Process-wide state. Only one Terminal instance is registered as a
/// QML type, so a global Mutex avoids the cxx-qt struct assignment
/// problem.
struct ActivePty {
    master_fd: RawFd,
    pid: i32,
    handle: Option<thread::JoinHandle<()>>,
}

impl Drop for ActivePty {
    fn drop(&mut self) {
        // Closing the master fd makes the reader thread see EOF and
        // exit; kill the child in case it's still alive.
        unsafe {
            libc::close(self.master_fd);
            libc::kill(self.pid, libc::SIGTERM);
        }
        if let Some(h) = self.handle.take() {
            let _ = h.join();
        }
    }
}

static PTY: Mutex<Option<ActivePty>> = Mutex::new(None);

pub struct TerminalRust {
    output_lines: QString,
    output_delta: QString,
    command: QString,
    pid: i32,
    running: bool,
    exit_code: i32,
    status: QString,
}

impl Default for TerminalRust {
    fn default() -> Self {
        Self {
            output_lines: QString::from("[]"),
            output_delta: QString::from("[]"),
            command: QString::from(""),
            pid: 0,
            running: false,
            exit_code: -1,
            status: QString::from(""),
        }
    }
}

const MAX_LINES: usize = 2000;

fn ring_lines() -> &'static Mutex<Vec<String>> {
    static SLOT: std::sync::OnceLock<Mutex<Vec<String>>> =
        std::sync::OnceLock::new();
    SLOT.get_or_init(|| Mutex::new(Vec::new()))
}

fn delta_lines() -> &'static Mutex<Vec<String>> {
    static SLOT: std::sync::OnceLock<Mutex<Vec<String>>> =
        std::sync::OnceLock::new();
    SLOT.get_or_init(|| Mutex::new(Vec::new()))
}

fn ring_serialize(v: &[String]) -> String {
    serde_json::to_string(v).unwrap_or_else(|_| "[]".to_string())
}

fn drain_fd(fd: RawFd, qt: cxx_qt::CxxQtThread<qobject::Terminal>) {
    use std::os::unix::io::FromRawFd;
    let mut f = unsafe { std::fs::File::from_raw_fd(fd) };
    let mut buf = [0u8; 4096];
    let mut line_buf: Vec<u8> = Vec::with_capacity(256);
    loop {
        let n = match f.read(&mut buf) {
            Ok(n) => n,
            Err(_) => break,
        };
        if n == 0 { break; }
        line_buf.extend_from_slice(&buf[..n]);
        let mut start = 0usize;
        for i in 0..line_buf.len() {
            if line_buf[i] == b'\n' {
                let mut line = String::from_utf8_lossy(
                    &line_buf[start..i]).into_owned();
                while line.ends_with('\r') { line.pop(); }
                if line.is_empty() { line = String::from("\\u00a0"); }
                push_line(line);
                start = i + 1;
            }
        }
        if start > 0 {
            line_buf.drain(..start);
        }
        let snap = ring_serialize(&ring_lines().lock().unwrap());
        let delta = ring_serialize(&delta_lines().lock().unwrap());
        let _ = qt.queue(move |mut t| {
            t.as_mut().set_output_lines(QString::from(snap.as_str()));
            t.as_mut().set_output_delta(QString::from(delta.as_str()));
        });
    }
    let _ = qt.queue(|mut t| {
        t.as_mut().set_running(false);
        t.as_mut().set_status(QString::from("child exited"));
    });
    if let Ok(mut g) = PTY.lock() {
        g.take();
    }
}

fn push_line(line: String) {
    let mut ring = ring_lines().lock().unwrap();
    if ring.len() >= MAX_LINES {
        ring.remove(0);
    }
    ring.push(line.clone());
    delta_lines().lock().unwrap().push(line);
}

impl qobject::Terminal {
    pub fn spawn_default(self: Pin<&mut Self>) {
        let shell = std::env::var("SHELL").unwrap_or_else(|_| "/bin/bash".into());
        self.spawn(&QString::from(&shell), &QString::from(""));
    }

    pub fn spawn(self: Pin<&mut Self>, cmd: &QString, args: &QString) {
        if let Ok(mut g) = PTY.lock() {
            g.take();
        }
        ring_lines().lock().unwrap().clear();
        delta_lines().lock().unwrap().clear();

        let cmd_str = cmd.to_string();
        let args_str = args.to_string();
        let mut parts: Vec<String> = cmd_str
            .split_whitespace().map(String::from).collect();
        let program = match parts.first().cloned() {
            Some(p) => { parts.remove(0); p }
            None => "/bin/bash".to_string(),
        };
        for a in args_str.split_whitespace() {
            parts.push(a.to_string());
        }

        let fork = match pty::fork::Fork::from_ptmx() {
            Ok(f) => f,
            Err(err) => {
                let mut this = self;
                this.as_mut().set_status(QString::from(
                    format!("fork: {err}").as_str()));
                return;
            }
        };

        let (pid, master_fd) = match fork.is_parent() {
            Ok(master) => {
                let pid = match &fork {
                    pty::fork::Fork::Parent(pid, _) => *pid,
                    _ => 0,
                };
                // We have to dup the master into a non-owned fd for
                // the reader thread. Easier: keep the Fork alive and
                // leak the master — we Drop it on close.
                let raw = master.as_raw_fd();
                (pid, raw)
            }
            Err(_) => {
                // Child branch: execute the target program.
                let err = Command::new(&program).args(&parts).exec();
                // exec failed; bail.
                let _ = err;
                unsafe { libc::_exit(127); }
            }
        };

        // Initial PTY size (QML may resize later).
        unsafe {
            let ws = libc::winsize {
                ws_row: 30, ws_col: 100, ws_xpixel: 0, ws_ypixel: 0,
            };
            libc::ioctl(master_fd, libc::TIOCSWINSZ, &ws);
        }

        // Reader thread.
        let qt = self.as_ref().qt_thread();
        let handle = thread::Builder::new()
            .name("selene-terminal".into())
            .spawn(move || drain_fd(master_fd, qt))
            .expect("selene: failed to spawn terminal reader");

        // Persist globals.
        if let Ok(mut g) = PTY.lock() {
            *g = Some(ActivePty {
                master_fd, pid,
                handle: Some(handle),
            });
        }
        let mut this = self;
        this.as_mut().set_command(QString::from(
            format!("{program} {}", parts.join(" ")).trim()));
        this.as_mut().set_pid(pid);
        this.as_mut().set_running(true);
        this.as_mut().set_status(QString::from("running"));
    }

    pub fn write(self: Pin<&mut Self>, data: &QString) {
        let bytes = data.to_string().into_bytes();
        self.write_bytes(&bytes);
    }

    pub fn write_bytes(self: Pin<&mut Self>, data: &[u8]) {
        let guard = PTY.lock().unwrap();
        if let Some(p) = guard.as_ref() {
            unsafe {
                let mut written = 0;
                while written < data.len() {
                    let n = libc::write(
                        p.master_fd,
                        data[written..].as_ptr().cast(),
                        data.len() - written,
                    );
                    if n <= 0 { break; }
                    written += n as usize;
                }
            }
        }
    }

    pub fn resize(self: Pin<&mut Self>, cols: i32, rows: i32) {
        let guard = PTY.lock().unwrap();
        if let Some(p) = guard.as_ref() {
            unsafe {
                let ws = libc::winsize {
                    ws_row: rows as u16,
                    ws_col: cols as u16,
                    ws_xpixel: 0,
                    ws_ypixel: 0,
                };
                libc::ioctl(p.master_fd, libc::TIOCSWINSZ, &ws);
            }
        }
    }

    pub fn clear(self: Pin<&mut Self>) {
        ring_lines().lock().unwrap().clear();
        delta_lines().lock().unwrap().clear();
        let snap = QString::from("[]");
        let mut this = self;
        this.as_mut().set_output_lines(snap.clone());
        this.as_mut().set_output_delta(snap);
    }

    pub fn close(self: Pin<&mut Self>) {
        if let Ok(mut g) = PTY.lock() {
            g.take();
        }
        let mut this = self;
        this.as_mut().set_running(false);
        this.as_mut().set_pid(0);
        this.as_mut().set_status(QString::from("closed"));
    }
}