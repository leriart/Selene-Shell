# Selene-Shell

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo-white.png" />
    <source media="(prefers-color-scheme: light)" srcset="assets/logo-dark.png" />
    <img alt="Selene shell" src="assets/logo-dark.png" width="220" />
  </picture>
</p>

<p align="center">
  <em>A QML shell for Hyprland. Translucent overlays, live theming, zero edits to your config.</em>
</p>

<p align="center">
  <a href="#what-it-is">Overview</a> &middot;
  <a href="#screens">Screens</a> &middot;
  <a href="#install">Install</a> &middot;
  <a href="#usage">Usage</a> &middot;
  <a href="#surfaces">Surfaces</a> &middot;
  <a href="#configuration">Configuration</a> &middot;
  <a href="#internals">Internals</a> &middot;
  <a href="#contributing">Contributing</a>
</p>

---

## What it is

Selene is a Hyprland shell that lives on top of your compositor without
touching its config. The Rust core consumes the Hyprland IPC stream and
exposes live state to a QML frontend through cxx-qt `Q_PROPERTY` bindings;
the visible chrome (bar, launcher, quick-settings, panels, wallpaper
picker, notification daemon) is then plain QML, scripted in Lua.

It fuses three inspirations:

- **[Ambxst](https://github.com/Axenide/Ambxst)** -- the non-intrusive
  installer philosophy and a single `selene` command surface that never
  edits your Hyprland config.
- **[Caelestia Shell](https://github.com/caelestia-dots/shell)** -- a
  translucent, token-based overlay language with a live palette engine.
- **[NothingLess](https://github.com/leriart/NothingLess)** -- the
  Dynamic Island pattern, the wallpaper-driven theming, and every
  lesson from the predecessor codebase.

The name draws from Selene, the Greek titaness of the moon -- a nod to
Lua ("moon" in Portuguese) riding on a foundation of Rust.

---

## Install

```bash
curl -sL https://github.com/leriart/selene-shell/raw/main/scripts/install.sh | sh
```

The installer mirrors Ambxst's "lives in your home, never touches sudo"
model:

1. Detects the distro (Arch, Fedora, Debian/Ubuntu, NixOS) and pulls the
   build deps for the cxx-qt + CMake + Rust toolchain.
2. Clones the repo into `~/.local/src/selene-shell` (or pulls if
   present).
3. Configures CMake and builds in Release.
4. Symlinks `scripts/cli.sh` as `~/.local/bin/selene`.
5. Stages `~/.local/share/selene/` for generated Hyprland config and
   runtime state.
6. Optionally runs `selene install hyprland` to add a single `source =`
   line with markers; the rest of your config is left alone.

Manual install is straightforward too:

```bash
git clone https://github.com/leriart/selene-shell
cd selene-shell
cargo generate-lockfile --manifest-path crates/selene-shell/Cargo.toml
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build
./build/selene-shell
```

### Prerequisites

- A running Hyprland session
- Qt 6.5+ (`qt6-base`, `qt6-declarative`, `qt6-quick`,
  `qt6-quickcontrols2`, `qt6-multimedia`)
- Rust toolchain (edition 2024+)
- CMake 3.24+, a C++17 compiler (GCC or Clang), Ninja
- ffmpeg, libqalculate (optional, for `=` and `:q` prefixes)
- `playerctl` (media metadata), `cava` (audio visualizer),
  `pactl`, `nmcli`, `bluetoothctl`, `loginctl` (panel backends)

`selene doctor` runs an environment check and reports any missing
binary; the installer also runs it before building.

---

## Usage

Inside a Hyprland session:

```bash
selene
```

That runs the compiled binary via the symlinked `cli.sh`. All commands:

| Command                  | Effect                                          |
|--------------------------|-------------------------------------------------|
| `selene`                 | Launch the shell (alias of `run`).              |
| `selene run`             | Launch the shell.                               |
| `selene reload`          | `pkill -USR1 -x selene-shell`.                  |
| `selene quit`            | `pkill -x selene-shell`.                        |
| `selene update`          | `git pull` + rebuild + relink.                  |
| `selene status`          | Print install paths and binary state.           |
| `selene doctor`          | Environment diagnostic.                         |
| `selene install hyprland`| Append a marked `source =` line; never edits the rest of the config. |
| `selene remove hyprland` | Strip the markers and source line cleanly.      |

Override paths with `SELENE_SRC`, `SELENE_BUILD`, `SELENE_SHARE`,
`SELENE_BIN_DIR`, `HYPRLAND_CONFIG` when needed.

### Keybinds

Selene registers the following via `hyprctl` global shortcuts; rebind any
of them in `~/.local/share/selene/hyprland.conf`:

| Keybind           | Action                                       |
|-------------------|----------------------------------------------|
| `SUPER`           | Toggle the launcher.                          |
| `SUPER + D`       | Toggle the dashboard / quick-settings.        |
| `SUPER + L`       | Lock the session.                             |
| `SUPER + ESC`     | Open the power menu.                          |
| `Ctrl+Alt+Left`   | Previous wallpaper.                           |
| `Ctrl+Alt+Right`  | Next wallpaper.                               |
| `Escape`          | Close any open panel.                         |

---

## Surfaces

The shell shows a small, wallpaper-first layout by default and exposes
panels on demand. Everything reads/writes through a dedicated Rust
QObject so the UI layer stays declarative.

### Always-visible

- **Floating top bar** -- `logo | workspaces | active window title |
  media title | status dots | clock | battery | power`. Status dots
  reflect live audio / network / bluetooth state; the power button
  opens a session menu (lock / suspend / logout / reboot / poweroff).
  Wallpaper-derived accent applied via tokens; backdrop blur over the
  wallpaper via Qt Quick `MultiEffect`.
- **IslandPill** (bottom-right) -- a compact pill that morphs into a
  card showing media, CPU%, RAM, battery, and a live `cava` audio
  visualiser while music is playing. Hover-tap to expand; click to lock /
  suspend / reboot / logout.

### On demand

- **Launcher** (`SUPER`) -- Hax-style fuzzy search over apps and shell
  actions. Prefix triggers:
  - `@app` -- fuzzy app search
  - `>action` -- shell actions (lock / suspend / restart etc.)
  - `=expression` -- calculator (sanitised JS, supports `+ - * / ( ) % ^`)
  - `?query` -- DuckDuckGo search via `Spawner.open_url` (http/https only)
  - `:emoji` -- emoji picker, click-to-copy via `wl-copy` (xclip / xsel
    fallback chain)
- **Notification center** -- D-Bus daemon over `zbus` blocking
  connection serving `org.freedesktop.Notifications` with the full
  `Notify` / `CloseNotification` / `GetCapabilities` /
  `GetServerInformation` surface, plus `NotificationClosed` and
  `ActionInvoked` signals. FIFO history cap (default 200, configurable
  via `apply_history_max`). Action buttons render and emit on click.
- **Wallpaper picker** -- thumbnail grid of the configured wallpaper
  directory. PNG/JPG/WebP via `Image`, GIF/APNG via `AnimatedImage`,
  MP4/WebM/MKV/MOV via `MediaPlayer` + `VideoOutput`. Click-to-pick
  drives the live Palette engine that re-tints the chrome.
- **Settings panel** -- every scalar `Config` property editable through
  `Config.set_value(key, val)`. `Save` writes the live state back to
  `init.lua` so the scriptable surface and the GUI stay in sync.
- **Quick Settings** -- three right-side panels:
  - **Audio** (pactl) -- sink selector, volume slider, mute toggle,
    +/- 5/15 % nudge
  - **Network** (nmcli) -- wifi on/off, nearby SSIs with signal bars
    and lock indicators, click-to-connect with optional password
  - **Bluetooth** (bluetoothctl) -- power toggle, paired devices, click to
    pair / connect / disconnect
- **Sidebar** (left edge) -- Caelestia-style thin trigger strip that
  slides open on hover to expose quick toggles (clipboard, picker,
  launcher, wallpapers) plus a small cluster of status badges.

### Always-visible chrome details

- Wallpaper is sampled through `MultiEffect` so every chrome surface
  reads like frosted glass over the user's desktop.
- Logo is luminance-aware: the silhouette flips between `logo-white.png`
  and `logo-dark.png` based on the live surface WCAG luminance, so it
  stays visible on any palette.
- Workspace dots are accent-tinted when active.
- Click-to-pick wallpapers; click-to-launch apps; click-to-toggle any
  quick setting; all backed by real subprocesses (`pactl`, `nmcli`,
  `bluetoothctl`, `xdg-open`, `ffmpeg`).
- The launcher's input is `forceActiveFocus`'d; the user can press
  arrow keys to navigate results and Enter to launch.

---

## Screens

The `assets/` folder is reserved for the canonical screenshot and
the per-panel captures. The intended layout (subject to replacement):
a banner for the floating shell + a 3x2 grid of the most representative
panels. The `assets/README.md` documents the regen batch script.

---

## Configuration

Selene is configured through Lua scripts in `~/.config/selene/`. An
example `init.lua`:

```lua
return {
    panel = {
        height      = 36,
        position    = "top",
        transparent = true,
        modules     = { "workspaces", "clock", "tray", "island" },
    },
    launcher = {
        width       = 640,
        max_results = 8,
        show_icons  = true,
    },
    theme = {
        accent     = "#a78bfa",
        background = "#1a1b1e",
        surface    = "#2a2b2e",
        -- when `follow_wallpaper = false`, the wallpaper-derived
        -- palette no longer overrides theme_* on the chrome.
        follow_wallpaper = true,
        font = {
            family = "Inter",
            size   = 13,
        },
    },
    binds = {
        ["SUPER"]       = "launcher",
        ["SUPER + D"]   = "dashboard",
        ["SUPER + L"]   = "lock",
        ["SUPER + ESC"] = "power",
    },
}
```

The `Config` QObject loads the file via `mlua 0.12`, exposes every
field as `#[qproperty]`, and watches it with `notify` for live
hot-reload via `notify` (inotify). Edits through the Settings panel
round-trip: `Config.set_value("theme.accent", "#a78bfa")` mutates the
in-memory state, `Config.save()` writes the entire table back to
`init.lua`, and the watcher's debounce re-loads the file so the script
and GUI never drift.

Settings hot-keys:
- `panel.height` (24..96 px)
- `panel.position` (top / bottom)
- `panel.transparent` (bool)
- `launcher.width` (320..1280 px)
- `launcher.max_results` (4..32)
- `launcher.show_icons` (bool)
- `theme.accent`, `theme.background`, `theme.surface`
- `theme.follow_wallpaper` (default true; turn off for fully manual palette)
- `font.family`, `font.size`

---

## Internals

### Project layout

```
selene-shell/
├── Cargo.toml                workspace root
├── CMakeLists.txt            links crates/selene-shell into the C++ executable
├── src/
│   └── main.cpp              QGuiApplication + QQmlApplicationEngine entry
├── crates/
│   └── selene-shell/         the Rust crate
│       ├── Cargo.toml
│       ├── build.rs          qml/ + asset registration
│       ├── src/              11 QObject bridges
│       └── qml/              13 QML components
├── assets/                   logos (light + dark variants), screenshots
├── scripts/
│   ├── install.sh            one-shot installer
│   └── cli.sh                `selene` command dispatcher
├── docs/                     per-surface notes
├── README.md
├── TODO.md
└── LICENSE
```

### Architecture

```
                            QML Layer
   +-----------------------------------------------------+
   |   Bar  Launcher  Notifications  WallpaperPicker  ...|
   +---------------------+--------------------------------+
                          |
                          | QtQuick / QQmlApplicationEngine
                          |
   +---------------------+--------------------------------+
   |                      Rust Backend                     |
   |                                                       |
   |   +--------------+  +--------------+  +------------+   |
   |   |  hyprland-rs |  |  mlua (Lua)  |  | cxx-qt     |   |
   |   |  IPC client  |  |  engine      |  | generated  |   |
   |   |  + listener  |  |              |  | QObjects   |   |
   |   +--------------+  +--------------+  +------------+   |
   |                                                       |
   |   Palette   Spawner   Config   Visualizer   ...      |
   +-------------------------------------------------------+
                          |
                          | subprocesses (pactl, nmcli, ...)
                          v
```

The Rust crate lives at `crates/selene-shell/` and produces a single
`staticlib`. CMake links it into the `selene-shell` executable via
`cxx-qt`'s CMake helpers. The QML files are co-located with the Rust
sources so the build system has one place to look. Logos are bundled
into the binary via `qrc` so the shell runs without a filesystem
dependency on its assets.

### Stack

| Layer            | Technology              | Responsibility                                       |
|------------------|-------------------------|------------------------------------------------------|
| UI               | QML / QtQuick 6         | Panels, overlays, animations, input                  |
| Build glue       | CMake + Corrosion       | Orchestrates Rust (cargo) and C++ (Ninja)            |
| Bridge           | Rust (cxx-qt)           | Expose backend data to QML as properties and models  |
| Compositor IPC   | hyprland-rs             | Push-based event listener + sync queries            |
| Scripting        | mlua (Lua 5.4)          | User config, keybindings, rules, theming             |
| Core             | Rust                    | Workspace tracking, event dispatch, resource mgmt    |

### QObject backends

| QObject    | Source                                                      |
|------------|-------------------------------------------------------------|
| Bridge     | `hyprland-rs` IPC + dedicated event listener thread         |
| Island     | `/proc/stat`, `/sys/class/power_supply`, `date`, `playerctl` |
| Spawner    | `.desktop` enumeration + `xdg-open` + `setsid --fork`     |
| Notifier   | `zbus` blocking connection on `org.freedesktop.Notifications`|
| Config     | `mlua` over `~/.config/selene/init.lua` + inotify watcher   |
| Palette    | ImageReader + `ffmpeg` pipe for image / video wallpapers   |
| Wallpaper  | Directory enumeration + image / GIF / video rendering      |
| Audio      | `pactl` over the default sink + sinks list                 |
| Network    | `nmcli` for wifi + connections                              |
| Bluetooth  | `bluetoothctl` for devices + power                         |
| Visualizer | `cava -p` subprocess pipe, ASCII frames @ ~15fps           |

### Threading model

- The Hyprland event listener and the CAVA reader live on dedicated
  `std::thread`s and push updates onto the Qt main thread via
  `cxx_qt::CxxQtThread::queue(move || { ... })`.
- The D-Bus notification daemon runs a `zbus::blocking::Connection`
  on its own thread; emits `NotificationClosed` / `ActionInvoked`
  through the same queue.
- The `Config` notifier watcher uses `notify` with a 250 ms debounce;
  hot-reload triggers a `Config.reload()` on the Qt main thread.

### Token system

`Tokens.qml` is a `pragma Singleton` with Caelestia-style scales:
`roundingScale`, `spacingScale`, `paddingScale`, `fontScale`,
`animScale` (multipliers); plus `surfaceAlpha` (0.55), `layerAlpha`
(0.92), `backdropBlur` (0.7), `hairlineAlpha` (0.08), `monoFamily`,
`fontFamily`, `radiusXs/Sm/Md/Lg`, and `barHeight/MaxWidth/Padding/
Spacing/WorkspaceSize/LogoSize/StatusSize/BatteryHeight/Width`.

The Palette engine re-tints `bg`, `surface`, `accent`, `text` whenever
the wallpaper changes (or when Config overrides them). Animations on
`Behavior on color` give a smooth 600 ms transition.

### Headless capture

```bash
selene-shell --screenshot assets/screenshot-shell.png \
             --delay 4000 --size 1280x720
```

Works under `QT_QPA_PLATFORM=offscreen` so docs / CI can regenerate
panels without a live Hyprland session. `--show <panel>` opens a
specific surface first (`launcher`, `notif`, `walls`, `settings`,
`audio`, `net`, `bt`, `sidebar`). `--launcher-query "<text>"` pre-fills
the launcher input.

---

## Contributing

Issues and pull requests are welcome. Before opening a PR, please read
`AGENTS.md` for the project guide (file layout, build flow, do/don't
of the cxx-qt bridge, how to add a new QObject). For larger changes
(new modules, IPC backends, theming primitives) open an issue first
so we can discuss the design.

### Add a QObject

1. Pick a Rust source filename -- `crates/selene-shell/src/<name>.rs`.
2. Use the `#[cxx_qt::bridge]` macro with a `qobject` module.
3. Add the module to `crates/selene-shell/src/lib.rs`.
4. Add the file to `crates/selene-shell/build.rs` under `.files([...])`.
5. Recompile. The QObject is now visible to QML as `Foo { id: foo }`
   after `import io.github.selene.shell`.

The full set of do's and don'ts (threading, signal handlers, naming
collisions) is in `AGENTS.md`.

---

## License

Apache 2.0 -- see [LICENSE](LICENSE).

---

## Inspiration

- **[Ambxst](https://github.com/Axenide/Ambxst)** -- installer philosophy,
  command surface, glyph-based interaction.
- **[Caelestia Shell](https://github.com/caelestia-dots/shell)** --
  lightweight philosophy, token-based theming, fluid overlay language.
- **[NothingLess](https://github.com/leriart/NothingLess)** -- axctl
  bridge, Dynamic Island, Ndot visual language, the entire predecessor
  codebase.
- **[Hax](https://github.com/fabiolopezperez-hue/ambxst-Hax)** --
  spotlight / launcher with calculator and plugin system.
- **[AwesomeWM](https://github.com/awesomeWM/awesome)** -- proven
  Lua-driven window manager configuration model.
- **[cava-bg](https://github.com/leriart/cava-bg)** -- the dominant-color
  extraction algorithm reused in the Palette engine.