/// Packages -- multi-source package search (Brain_Shell / Hax port).
///
/// The `Packages` QObject runs the user's available package managers
/// (`pacman`, `yay`, `flatpak`, `apt` if present) sequentially with
/// a search query and exposes the combined results as JSON. Each entry:
///
///     { name, source, description, version }
///
/// `source` is one of `pacman | aur | flatpak | apt` so the QML can
/// render a per-source badge. Results are read on a worker thread
/// and pushed into the cxx-qt queued bridge; stale results are
/// discarded via a generation counter.
use core::pin::Pin;
use cxx_qt_lib::QString;
use std::process::Command;
use std::sync::atomic::{AtomicU64, Ordering};
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
        #[qproperty(QString, results_json)]
        #[qproperty(QString, status)]
        #[qproperty(bool, searching)]
        type Packages = super::PackagesRust;

        #[qinvokable]
        fn refresh(self: Pin<&mut Self>);

        #[qinvokable]
        fn search(self: Pin<&mut Self>, query: &QString);

        #[qinvokable]
        fn cancel(self: Pin<&mut Self>);

        #[qinvokable]
        fn available_sources(self: Pin<&mut Self>) -> QString;
    }

    impl cxx_qt::Threading for Packages {}
}

pub struct PackagesRust {
    results_json: QString,
    status: QString,
    searching: bool,
}

impl Default for PackagesRust {
    fn default() -> Self {
        Self {
            results_json: QString::from("[]"),
            status: QString::from(""),
            searching: false,
        }
    }
}

static SEARCH_GEN: AtomicU64 = AtomicU64::new(0);

#[derive(Clone, Debug, serde::Serialize)]
struct Hit {
    name: String,
    source: &'static str,
    description: String,
    version: String,
}

fn has(cmd: &str) -> bool {
    Command::new("which")
        .arg(cmd)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn available() -> Vec<&'static str> {
    let mut v = Vec::new();
    if has("pacman") { v.push("pacman"); }
    if has("yay")    { v.push("aur"); }
    if has("flatpak") { v.push("flatpak"); }
    if has("apt")    { v.push("apt"); }
    v
}

/// Parse `pacman -Ss <query>` output: lines like
///   `core/git 2.40.0-1`
///       Distributed version control system
fn parse_pacman(out: &str, source: &'static str) -> Vec<Hit> {
    let mut hits = Vec::new();
    let mut lines = out.lines().peekable();
    while let Some(name_line) = lines.next() {
        let trimmed = name_line.trim();
        if let Some((_repo, rest)) = trimmed.split_once('/')
            && let Some((name_v, _)) = rest.split_once(' ') {
                let mut parts = name_v.splitn(2, ' ');
                let name = parts.next().unwrap_or("").to_string();
                let version = parts.next().unwrap_or("").to_string();
                let description = lines.peek()
                    .map(|l| l.trim().to_string()).unwrap_or_default();
                if !description.is_empty() { lines.next(); }
                if !name.is_empty() {
                    hits.push(Hit { name, source, description, version });
                }
            }
    }
    hits
}

/// Parse `flatpak search --columns=name,description <query>`: tabular
/// rows separated by blank lines. The first non-empty row's first
/// column is `Name\t...id`; the next row is `Description\t...`.
fn parse_flatpak(out: &str) -> Vec<Hit> {
    let mut hits = Vec::new();
    let mut current: Option<Hit> = None;
    for line in out.lines() {
        let t = line.trim();
        if let Some(rest) = t.strip_prefix("Name\t\t") {
            if let Some(prev) = current.take() { hits.push(prev); }
            current = Some(Hit {
                name: rest.trim().to_string(),
                source: "flatpak",
                description: String::new(),
                version: String::new(),
            });
        } else if let Some(rest) = t.strip_prefix("Description\t")
            && let Some(c) = current.as_mut() {
                c.description = rest.trim().to_string();
            }
    }
    if let Some(c) = current { hits.push(c); }
    hits
}

fn run_search(_query: &str, source: &'static str, prog: &str,
              args: Vec<&str>) -> Vec<Hit> {
    let out = match Command::new(prog).args(&args).output() {
        Ok(o) if o.status.success() =>
            String::from_utf8_lossy(&o.stdout).into_owned(),
        _ => return Vec::new(),
    };
    match source {
        "pacman" | "aur" => parse_pacman(&out, source),
        "flatpak" => parse_flatpak(&out),
        _ => Vec::new(),
    }
}

fn push_results(qt: cxx_qt::CxxQtThread<qobject::Packages>,
                gen_id: u64,
                combined: Vec<Hit>) {
    let json = serde_json::to_string(&combined).unwrap_or_else(|_| "[]".into());
    let _ = qt.queue(move |mut p| {
        if gen_id == SEARCH_GEN.load(Ordering::Relaxed) {
            p.as_mut().set_results_json(QString::from(json.as_str()));
            p.as_mut().set_searching(false);
            p.as_mut().set_status(QString::from(
                format!("{} results", combined.len()).as_str()));
        }
    });
}

impl qobject::Packages {
    pub fn refresh(self: Pin<&mut Self>) {
        self.search(&QString::from(""));
    }

    pub fn search(self: Pin<&mut Self>, query: &QString) {
        let gen_id = SEARCH_GEN.fetch_add(1, Ordering::Relaxed) + 1;
        let q = query.to_string();
        let qt = self.as_ref().qt_thread();
        {
            let mut this = self;
            this.as_mut().set_searching(true);
            this.as_mut().set_status(QString::from("searching..."));
        }

        thread::Builder::new()
            .name("selene-pkg-search".into())
            .spawn(move || {
                let mut combined: Vec<Hit> = Vec::new();
                for src in available() {
                    let hits = match src {
                        "pacman" => {
                            if q.is_empty() { Vec::new() }
                            else { run_search(&q, "pacman", "pacman",
                                              vec!["-Ss", "--nocolor", &q]) }
                        }
                        "aur" => {
                            if q.is_empty() { Vec::new() }
                            else { run_search(&q, "aur", "yay",
                                              vec!["-Ss", "--nocolor", &q]) }
                        }
                        "flatpak" => {
                            if q.is_empty() { Vec::new() }
                            else { run_search(&q, "flatpak", "flatpak",
                                              vec!["search",
                                               "--columns=name,description", &q]) }
                        }
                        "apt" => Vec::new(),
                        _ => Vec::new(),
                    };
                    combined.extend(hits);
                }
                combined.truncate(200);
                push_results(qt, gen_id, combined);
            })
            .expect("selene: failed to spawn package search thread");
    }

    pub fn cancel(self: Pin<&mut Self>) {
        SEARCH_GEN.fetch_add(1, Ordering::Relaxed);
        let mut this = self;
        this.as_mut().set_searching(false);
        this.as_mut().set_status(QString::from("cancelled"));
    }

    pub fn available_sources(self: Pin<&mut Self>) -> QString {
        QString::from(available().join(",").as_str())
    }
}