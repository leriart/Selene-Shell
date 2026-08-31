# AGENTS.md

Quick guide for AI agents (and humans) working on Selene. If you change
something that invalidates a section here, update this file in the same
commit.

## Project at a glance

A QML shell for Hyprland, written in Rust with `cxx-qt` bindings. The UI
layer is co-located with the crate that registers it, and the rest of
the project is a thin shell around it.

```
selene-shell/
├── Cargo.toml                workspace root
├── CMakeLists.txt            links crates/selene-shell into the C++ executable
├── src/main.cpp              QGuiApplication + QQmlApplicationEngine entry
│                             (+ QLocalServer IPC: show/reload/quit, --send client)
├── crates/selene-shell/
│   ├── Cargo.toml            the only workspace member today
│   ├── build.rs              registers QML files + assets into the qrc
│   ├── src/                  23 QObject bridges (see "Adding a QObject")
│   └── qml/                  33 QML components (Tokens, Bar, ...)
├── assets/
│   ├── logo-dark.png         trimmed to content, bundled into the qrc
│   ├── logo-white.png
│   └── screenshot-shell.png   captured by `selene-shell --screenshot`
├── wallpapers/               user wallpapers (images + videos); empty by
│                             default, picked up by the wallpaper engine
├── scripts/
│   ├── install.sh            one-shot curl|sh installer
│   └── cli.sh                `selene` command dispatcher
├── docs/                     per-surface notes / architecture (currently empty)
├── README.md
└── TODO.md
```

## Build

The workspace is split into two build systems that share the `crates/selene-shell`
directory. CMake drives the `staticlib` link; Cargo drives the source compile.

```bash
# configure (creates build/)
cmake -B build -S . -G Ninja -DCMAKE_BUILD_TYPE=Release

# build everything
cmake --build build

# or, equivalently, just the Rust side
cd crates/selene-shell && cargo build
```

Because Corrosion re-runs Cargo from CMake, any change to a Rust source file
forces the qrc to be regenerated. Rebuilding the executable picks up new
QML automatically; you only need `cmake --build build` after editing QML.

Headless smoke test (no Wayland session required):

```bash
QT_QPA_PLATFORM=offscreen build/selene-shell
```

Take a screenshot of the shell at rest (useful for docs / CI):

```bash
QT_QPA_PLATFORM=offscreen build/selene-shell \
    --screenshot assets/screenshot-shell.png --delay 4000
```

`selene doctor` is the canonical environment check:

```bash
bash scripts/cli.sh doctor
```

## Adding a QObject

1. Pick a Rust source filename -- `crates/selene-shell/src/<name>.rs`.
2. Use the `#[cxx_qt::bridge]` macro with a `qobject` module:

   ```rust
   #[cxx_qt::bridge]
   pub mod qobject {
       unsafe extern "C++" {
           include!("cxx-qt-lib/qstring.h");
           type QString = cxx_qt_lib::QString;
       }
       extern "RustQt" {
           #[qobject]
           #[qml_element]
           #[qproperty(QString, foo)]
           #[qinvokable]
           fn bar(self: Pin<&mut Self>);
           impl cxx_qt::Threading for Foo {}
       }
   }
   ```
3. Add the module to `crates/selene-shell/src/lib.rs`.
4. Add the file to `crates/selene-shell/build.rs` under `.files([...])`.
5. Recompile. The QObject is now visible to QML as `Foo { id: foo }` after
   `import io.github.selene.shell`.

### Signal/changes handler caveat

QML `var` properties **do not** auto-generate `onXChanged` handlers. To
react to a `var` property in another QML file, use a separate
`Connections { target: ...; function onXChanged() { ... } }` block.

### Threading

If the QObject needs to push updates from a non-`QObject` thread (subprocess
reader, D-Bus, etc.):

1. `impl cxx_qt::Threading for Foo {}` in the bridge.
2. In the qinvokable that starts the worker, take `self.as_ref().qt_thread()`.
3. Clone it into the worker thread.
4. From the worker, call `qt.queue(|mut foo| foo.set_fancy(...))`.

`CxxQtThread` is a `Send` handle; the closure receives a `Pin<&mut Foo>` and
mutates it directly. The queue runs the closure on the Qt main thread.

### Naming collisions

`foo.rs` defines `Foo` QObject -- `qml/Foo.qml` will be shadowed by the
Rust type. Either rename the QML file (e.g. `FooCard.qml`) or move the
QObject to a different module name. The shell uses `crates/selene-shell/qml/IslandPill.qml`
because `Island` is the QObject name.

## Adding a QML component

1. Drop the file in `crates/selene-shell/qml/`.
2. Add it to the `files` array in `build.rs` (or use
   `QmlFile::from(...).singleton(true)` for a `pragma Singleton`).
3. If the component needs to be addressable by name from elsewhere, add it
   to the `qml_resources` list too. The `Main.qml` does not need explicit
   registration -- it loads the whole module by URL.
4. Reference it in QML as `Foo { id: ... }` after
   `import io.github.selene.shell`.

## Adding an asset

1. Drop the file in `assets/`.
2. Add a `QResourceFile::new("../../assets/<name>").alias("<name>")` entry
   to `build.rs`'s `qml_resources` chain.
3. Reference it from QML as `qrc:/qt/qml/io/github/selene/shell/<name>`.
   Aliases are honoured, so the `assets/` prefix is preserved.

The `assets/badge.png` reference then becomes
`qrc:/qt/qml/io/github/selene/shell/assets/badge.png`.

## Script conventions

- `scripts/install.sh` is the only entry point that touches the user's
  filesystem outside `~/.local/`. It installs dependencies, clones the
  repo, builds with CMake, and symlinks `scripts/cli.sh` to
  `~/.local/bin/selene`.
- `scripts/cli.sh` derives `SELENE_SRC` from its own location
  (`dirname $(dirname $0)`) so it works whether invoked from the source
  tree or from the symlink. Update both shell scripts together when
  paths change.

## Do / don't

- **Do** wrap blocking work in `std::thread::spawn` and bridge back through
  `CxxQtThread`. Don't block the Qt main thread.
- **Do** use `qrc:` URIs for assets that ship with the binary. Don't
  depend on the runtime CWD.
- **Do** keep Rust constants (radius, spacing, palette defaults) in sync
  with `qml/Tokens.qml`.
- **Don't** rename `crates/selene-shell/Cargo.toml`'s `name` field. The
  Qt module URI is derived from `io.github.selene.shell` -> the crate is
  named `selene_shell`, and `cxx-qt-build` derives the link symbol from it.
- **Don't** add a `qproperty` whose setter collides with a qinvokable
  auto-generated name (`set_<property>` for each property). If you want
  a method that reads/writes the property, rename the qinvokable
  (e.g. `apply_height` instead of `set_height`).
- **Don't** make the QObject cxx-qt methods take `&mut Self`; they take
  `Pin<&mut Self>` (cxx-qt generates that signature for you).
- **Don't** panic inside a subprocess poll. Convert to `Vec<u8>` errors
  and surface via `status` qproperty.

## Testing

There is no automated test suite. The `selene doctor` subcommand is the
primary smoke test:

```bash
bash scripts/cli.sh doctor
```

The headless visual test (no Wayland required):

```bash
QT_QPA_PLATFORM=offscreen build/selene-shell --screenshot /tmp/x.png --delay 4000
```

For Rust changes, `cargo check` from the workspace root is the cheapest
gate; `cargo clippy` is not run in CI yet.

## Where to look

| Need | File |
|---|---|
| Hyprland IPC | `crates/selene-shell/src/bridge.rs` |
| Wallpaper surface | `crates/selene-shell/src/wallpaper.rs` + `qml/WallpaperSurface.qml` |
| Live palette | `crates/selene-shell/src/palette.rs` |
| Notifications | `crates/selene-shell/src/notifications.rs` + `qml/NotificationPanel.qml` |
| Launcher | `crates/selene-shell/src/spawner.rs` + `qml/Launcher.qml` |
| Config | `crates/selene-shell/src/config.rs` + `qml/SettingsPanel.qml` |
| Island overlay / Dashboard | `crates/selene-shell/src/island.rs` + `qml/IslandPill.qml` |
| Audio | `crates/selene-shell/src/audio.rs` + `qml/AudioPanel.qml` |
| Network | `crates/selene-shell/src/network.rs` + `qml/NetworkPanel.qml` |
| Bluetooth | `crates/selene-shell/src/bluetooth.rs` + `qml/BluetoothPanel.qml` |
| Cava visualizer | `crates/selene-shell/src/visualizer.rs` |
| Clipboard | `crates/selene-shell/src/clipboard.rs` + `qml/ClipboardPanel.qml` |
| Color picker | `crates/selene-shell/src/picker.rs` + `qml/ColorPickerPanel.qml` |
| Sidebar | `crates/selene-shell/qml/Sidebar.qml` + `SidebarButton.qml` + `SidebarBadge.qml` |
| State (snapshot/restore) | `crates/selene-shell/src/state.rs` |
| Lock screen | `crates/selene-shell/src/lock.rs` + `qml/LockScreen.qml` |
| cava-bg IPC | `crates/selene-shell/src/ipc.rs` |
| Night light | `crates/selene-shell/src/night_light.rs` (wlsunset) |
| Power menu | `crates/selene-shell/qml/PowerMenu.qml` (SUPER+ESC) |
| Keybind cheatsheet | `crates/selene-shell/qml/KeybindsPanel.qml` (reads `binds` from init.lua) |
| Notes | `crates/selene-shell/src/notes.rs` + `qml/NotesPanel.qml` |
| Todo board | `crates/selene-shell/src/todo.rs` + `qml/TodoPanel.qml` |
| Embedded terminal | `crates/selene-shell/src/terminal.rs` + `qml/TerminalPanel.qml` (SUPER+Return) |
| Package search | `crates/selene-shell/src/packages.rs` (used via Launcher `install <query>`) |
| Screen recording | `crates/selene-shell/src/screenshot.rs` (wf-recorder, `record_*` invokables) |
| Wallpaper engine | `crates/selene-shell/src/wallpaper_engine.rs` (hw video decode, downscale cache, pause mask) |
| Notes | `crates/selene-shell/src/notes.rs` + `qml/NotesPanel.qml` |
| Todo board | `crates/selene-shell/src/todo.rs` + `qml/TodoPanel.qml` |
| OSD popup | `crates/selene-shell/qml/OsdPopup.qml` (volume/brightness/record flash) |
| Orbital primitives | `crates/selene-shell/qml/Orbit.qml` + `Moon.qml` + `MoonPulse.qml` |
| Hax-style launcher | `crates/selene-shell/qml/Launcher.qml` (timers, stats, weather, help) |
| Tokens (shared design system) | `crates/selene-shell/qml/Tokens.qml` (theme presets, animation profiles) |

## Live IPC

The shell owns a QLocalServer at `$XDG_RUNTIME_DIR/selene-shell.sock`.
One line per connection:

- `show <panel>` -- runs `Main.qml`'s `applyScreenshotPanel(<panel>)`
  (launcher, dashboard, overview, powermenu, binds, notes, todo, dnd,
  caffeine, nightlight, record, lock, suspend, ...).
- `apply-preset <name>` -- applies a Tokens theme preset (new-moon,
  waxing-crescent, first-quarter, full-moon, sunset, midnight,
  monochrome, default).
- `animation-profile <name>` -- switches the animation profile
  (m3 | subtle | bouncy | off).
- `osd <kind> <value>` -- flashes the OSD popup.
- `reload` -- deletes the root objects, clears the component cache and
  re-loads `Main.qml`. `SIGUSR1` flips the same path (cli.sh fallback).
- `quit` -- clean `QCoreApplication::quit()`.

Clients should use `build/selene-shell --send "<cmd>"` (client mode in
`main.cpp`); `scripts/cli.sh` wraps it in `selene_send()` and every
`selene run <panel>`/lock/suspend/record command tries IPC first and
falls back to direct execution when no instance is alive.
