/// Audio visualizer -- live bar graph via cava subprocess.
//
/// The `Visualizer` QObject spawns `cava -p` with a generated
/// raw ASCII config, parses each v;v;...; frame on a reader thread,
/// and pushes bars_json + peak to QML through the cxx-qt queue at
/// ~15fps. The QML side (`IslandPill.qml`) renders the bars while
/// media_playing is true.

use core::pin::Pin;
use cxx_qt::Threading;
use cxx_qt_lib::QString;
use std::io::{BufRead, BufReader};
use std::process::{Child, ChildStdout, Command, Stdio};
use std::sync::{Mutex, OnceLock};

/// Audio visualizer bridge: spawns `cava` with a raw ASCII output config and
/// forwards every magnitude frame to QML. The reader lives on its own thread
/// and pushes updates through the cxx-qt queued bridge at a capped rate.
#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(QString, bars_json)]
        #[qproperty(i32, peak)]
        #[qproperty(i32, bar_count)]
        #[qproperty(bool, running)]
        #[qproperty(QString, status)]
        type Visualizer = super::VisualizerRust;

        #[qinvokable]
        fn start(self: Pin<&mut Self>);

        #[qinvokable]
        fn stop(self: Pin<&mut Self>);

        #[qinvokable]
        fn apply_bar_count(self: Pin<&mut Self>, count: i32);
    }

    impl cxx_qt::Threading for Visualizer {}
}

#[derive(Default)]
pub struct VisualizerRust {
    bars_json: QString,
    peak: i32,
    bar_count: i32,
    running: bool,
    status: QString,
}

fn child_slot() -> &'static Mutex<Option<Child>> {
    static CHILD: OnceLock<Mutex<Option<Child>>> = OnceLock::new();
    CHILD.get_or_init(|| Mutex::new(None))
}

fn write_config(path: &std::path::Path, bars: i32) -> std::io::Result<()> {
    let bars = bars.clamp(4, 128);
    let body = format!(
        "[general]\nbars = {bars}\nframerate = 30\nautosens = 1\nsensitivity = 100\n\
         [output]\nmethod = raw\ndata_format = ascii\nascii_max_range = 100\nchannels = mono\n"
    );
    std::fs::write(path, body)
}

fn config_path() -> std::path::PathBuf {
    let home = std::env::var_os("HOME")
        .map(|h| h.to_string_lossy().to_string())
        .unwrap_or_else(|| "/tmp".to_string());
    std::path::PathBuf::from(format!("{home}/.local/share/selene/cava.conf"))
}

fn parse_frame(line: &str) -> Vec<u32> {
    line.trim_end_matches(';')
        .split(';')
        .filter_map(|tok| tok.trim().parse::<u32>().ok())
        .collect()
}

fn reader_main(
    stdout: ChildStdout,
    qt: cxx_qt::CxxQtThread<qobject::Visualizer>,
) {
    let reader = BufReader::new(stdout);
    let mut frame_no: u64 = 0;
    for line in reader.lines() {
        let Ok(line) = line else { break; };
        frame_no += 1;
        // Cap at ~15fps: skip every other frame of cava's 30fps stream.
        if frame_no.is_multiple_of(2) {
            continue;
        }
        let bars = parse_frame(&line);
        if bars.is_empty() {
            continue;
        }
        let peak = bars.iter().copied().max().unwrap_or(0) as i32;
        let json = QString::from(
            serde_json::to_string(&bars)
                .unwrap_or_else(|_| "[]".to_string())
                .as_str(),
        );
        if qt
            .queue(move |mut vis| {
                vis.as_mut().set_bars_json(json);
                vis.as_mut().set_peak(peak);
            })
            .is_err()
        {
            break;
        }
    }
    // Child exited (killed or died): reflect it in the UI.
    let _ = qt.queue(|mut vis| {
        vis.as_mut().set_running(false);
        vis.as_mut()
            .set_status(QString::from("cava stopped"));
    });
}

impl qobject::Visualizer {
    pub fn start(self: Pin<&mut Self>) {
        if *self.running() {
            return;
        }
        if Command::new("cava").arg("-v").output().is_err() {
            let mut this = self;
            this.as_mut()
                .set_status(QString::from("cava not on PATH"));
            return;
        }

        let bars = if *self.bar_count() > 0 {
            *self.bar_count()
        } else {
            24
        };
        let cfg = config_path();
        if let Some(parent) = cfg.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        if write_config(&cfg, bars).is_err() {
            let mut this = self;
            this.as_mut()
                .set_status(QString::from("cannot write cava.conf"));
            return;
        }

        let child = Command::new("cava")
            .arg("-p")
            .arg(&cfg)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn();

        let mut child = match child {
            Ok(c) => c,
            Err(err) => {
                let mut this = self;
                this.as_mut()
                    .set_status(QString::from(format!("spawn: {err}")));
                return;
            }
        };

        let Some(stdout) = child.stdout.take() else {
            let mut this = self;
            this.as_mut()
                .set_status(QString::from("no stdout pipe"));
            return;
        };

        if let Ok(mut slot) = child_slot().lock() {
            *slot = Some(child);
        }

        let qt: cxx_qt::CxxQtThread<qobject::Visualizer> = self.as_ref().qt_thread();
        std::thread::Builder::new()
            .name("selene-cava".into())
            .spawn(move || reader_main(stdout, qt))
            .expect("selene: failed to spawn cava reader thread");

        let mut this = self;
        this.as_mut().set_running(true);
        this.as_mut().set_bar_count(bars);
        this.as_mut()
            .set_status(QString::from(format!("cava running, {bars} bars")));
    }

    pub fn stop(self: Pin<&mut Self>) {
        if let Ok(mut slot) = child_slot().lock()
            && let Some(mut child) = slot.take() {
                let _ = child.kill();
                let _ = child.wait();
            }
        let mut this = self;
        this.as_mut().set_running(false);
        this.as_mut()
            .set_status(QString::from("stopped"));
    }

    pub fn apply_bar_count(self: Pin<&mut Self>, count: i32) {
        let clamped = count.clamp(4, 128);
        let was_running = *self.running();
        let mut this = self;
        this.as_mut().set_bar_count(clamped);
        if was_running {
            this.as_mut().stop();
            this.as_mut().start();
        }
    }
}
