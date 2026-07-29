# Selene-Shell

A QML shell for Hyprland. Light as moonlight, solid as Rust.

Selene is a modern, visually refined shell for [Hyprland](https://hyprland.org) and the
spiritual successor to [NothingLess](https://github.com/leriart/NothingLess). Its user
interface is crafted in QML, backed by a high-performance Rust core, and scriptable in
Lua. The name draws from Selene, the Greek titaness of the moon -- a nod to Lua (Lua
means moon in Portuguese) riding on a foundation of Rust.

---

## Lineage

Selene fuses the best parts of three projects into one coherent whole:

- **[Ambxst](https://github.com/Axenide/Ambxst)** -- non-intrusive installer philosophy,
  the `cli` command surface, the dot-Material design language and the "the shell
  never edits your config" promise.
- **[Caelestia Shell](https://github.com/caelestia-dots/shell)** -- the translucid bar
  and launcher aesthetic, the token-based theming system, fluid overlays and the
  discipline of a single config the user owns.
- **[NothingLess](https://github.com/leriart/NothingLess)** -- the axctl compositing
  bridge, the Dynamic Island, the Ndot visual language, the FPS pipeline, the Mirai
  screen-sharing integration, and every lessons-learned shipped during its lifetime.

Visually Selene tips its hat to both -- Caelestia's glassy overlay shell with
NothingLess's Ndot accent (dot-matrix monospace, monochrome with a single accent
pop) and tight material curves.

---

## Aesthetic

Two principles steer every design decision:

1. **Visual ambition** -- the polished, minimalist language of Ambxst and Caelestia:
   clean typography, translucent overlays, deliberate whitespace, motion with intent.
2. **Resource discipline** -- the lightness of Caelestia: zero unnecessary allocations,
   no heavy framework on the hot path, a shell that stays out of your way and your RAM.

The UI layer (QML) is free to be expressive. The backend (Rust) is free to be ruthless
about performance. Lua scripts bridge the two with minimal overhead and a low floor for
users writing their own config.

---

## Architecture

```
                               QML Layer
   +-----------------------------------------------------+
   |   Panel      Launcher       Notification Center     |
   |   OSD        Overview       Quick Settings          |
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
   |   Workspace Manager  *  Window Tracker  *  Config   |
   +-------------------------------------------------------+
```

### Stack

| Layer            | Technology              | Responsibility                                       |
|------------------|-------------------------|------------------------------------------------------|
| UI               | QML / QtQuick 6         | Panels, overlays, animations, input                  |
| Build glue       | CMake + Corrosion       | Orchestrates Rust (cargo) and C++ (Ninja)            |
| Bridge           | Rust (cxx-qt)           | Expose backend data to QML as properties and models  |
| Compositor IPC   | hyprland-rs             | Push-based event listener + sync queries            |
| Scripting        | mlua (Lua 5.4)          | User config, keybindings, rules, theming             |
| Core             | Rust                    | Workspace tracking, event dispatch, resource mgmt    |

---

## Compositor features

Selene is, at its core, a compositor surface for Hyprland. The Rust side consumes
the IPC stream and exposes live state to QML through cxx-qt `Q_PROPERTY` bindings.

### Live IPC

The Rust core spawns a dedicated event-listener thread that owns a
`hyprland-rs::EventListener`. On every workspace, monitor, window, fullscreen or
focus change, the listener queues a `refresh()` call onto the Qt main thread via
`cxx_qt::CxxQtThread`, which re-reads the relevant state from the Hyprland socket
and updates the QObject properties in one pass. QML bindings then propagate to
every visible surface without polling.

Handled events:

- `workspace >> changed / added / deleted / moved / renamed`
- `activeWindow >> changed`, `activeMonitor >> changed`
- `window >> titleChanged / opened / closed / moved`

The QML side also keeps a 10 s safety-net `Timer` that calls `refresh()` for the
case where Hyprland is not running.

Exposed bindings on the `Bridge` QObject (consumed by `Bar.qml`, `Main.qml`, etc.):

| Property              | Type    | Source                                  |
|-----------------------|---------|-----------------------------------------|
| `connected`           | `bool`  | whether the IPC socket is reachable     |
| `hyprland_status`     | `string`| last status / error from the bridge     |
| `listener_started`    | `bool`  | whether the event thread is running     |
| `active_workspace_id` | `int`   | `Workspace::get_active().id`             |
| `active_workspace_name` | `string` | `Workspace::get_active().name`        |
| `workspace_count`     | `int`   | `Workspaces::get().len()`                |
| `active_window_class` | `string`| `Client::get_active().class`            |
| `active_window_title` | `string`| `Client::get_active().title`            |

QInvokables: `increment()`, `greet(name)`, `refresh()`, `start_listener()`.

---

## Adjustments & settings

Selene ships the surfaces that NothingLess and Caelestia proved users actually
touch on a daily basis. Each becomes a QML surface that reads/writes through a
dedicated Rust QObject.

- **Status bar** -- translucent top bar with workspace chips, active-window pill,
  connection badge, future media + tray extension.
- **Notification Center** -- QML-hosted D-Bus notification daemon with persistence,
  history and DND.
- **Launcher** -- fuzzy search over apps / files / shell actions with prefix
  triggers (`@app`, `>action`), modeled after Hax.
- **Clipboard** -- searchable, categorized, favorites + QR/URL previews.
- **Quick Settings** -- network, bluetooth, audio and battery toggles that
  write through to `NetworkManager` / `bluetoothctl` / `wpctl` via small Rust
  commands.
- **Settings panel** -- searchable visual config split into 11 sections
  (bar, dock, notch, theme, AI, compositor, binds, monitors, wallpapers...).
- **Overview** -- Mission Control-style workspace manager with live window
  previews and drag-and-drop moving.

Each surface is a regular QML file in the `io.github.selene.shell` module, so
themes can opt in or out of any of them.

---

## Why Rust + QML + Lua

### Rust

- Zero-cost abstractions and strict compile-time safety for a process that runs 24/7.
- `hyprland-rs` gives us a typed, async-capable client over the Hyprland Unix socket.
- `mlua` embeds Lua 5.4 with sandboxing and a ~20 KB state footprint.
- `cxx-qt` bridges Rust to the QML engine without an intermediate C++ layer or
  per-frame marshalling, and exposes a `CxxQtThread` helper for safe queued
  updates from background threads.

### QML

- Declarative UI that separates visual design from logic.
- Hardware-accelerated rendering through the Qt Quick scene graph.
- Live reloading during development for rapid iteration.
- Mature enough for complex overlays, animations and multi-surface shells.

### Lua

- The lightest practical scripting language (~20 KB runtime footprint).
- Proven in the window manager space (AwesomeWM, Qtile).
- Flat learning curve for users writing their own config.
- Sandboxable -- user scripts can crash their session, never the shell.

---

## Getting Started

### Prerequisites

- A running Hyprland session.
- Qt 6.5+ (`qt6-base`, `qt6-declarative`, `qt6-quick`, `qt6-quickcontrols2`).
- A Rust toolchain (edition 2024+).
- CMake 3.24+ and a C++17 compiler (GCC or Clang).
- Ninja (recommended).
- Git (CMake fetches `cxx-qt-cmake` if it is not installed locally).

### Build

```bash
git clone https://github.com/leriart/selene-shell
cd selene-shell

# One-time: pin the Rust dependency graph
cargo generate-lockfile --manifest-path rust/Cargo.toml

cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

### Run

```bash
# From within a Hyprland session
./build/selene-shell
```

On first run, Selene registers itself in your `hyprland.conf` with a single `source`
line, mirroring the [Ambxst install philosophy](https://github.com/Axenide/Ambxst):

```ini
# Selene
source = ~/.local/share/selene/hyprland.conf

# OVERRIDES
# Down here you can write or source anything that you want to override from Selene's settings.
```

Your existing Hyprland config is never modified.

### One-shot installer

```bash
curl -sL https://github.com/leriart/selene-shell/raw/main/install.sh | sh
```

The installer mirrors Ambxst's "no sudo, lives in your home" model:

1. Detects the distro (Arch, Fedora, Debian/Ubuntu, NixOS) and installs the
   build dependencies needed for the cxx-qt + CMake + Rust toolchain.
2. Clones the repo into `~/.local/src/selene-shell` (or pulls if present).
3. Configures CMake and builds in Release.
4. Symlinks `cli.sh` as `~/.local/bin/selene`.
5. Stages `~/.local/share/selene` for generated Hyprland config and future
   state files.
6. Optionally runs `selene install hyprland` to add the `source =` line.

`selene <command>` exposes:

| Command               | What it does                                         |
|-----------------------|------------------------------------------------------|
| `selene`              | Launch the shell (alias of `run`).                   |
| `selene run`          | Launch the shell.                                    |
| `selene reload`       | `pkill -USR1 -x selene-shell`.                       |
| `selene quit`         | `pkill -x selene-shell`.                             |
| `selene update`       | `git pull` + rebuild + relink.                       |
| `selene status`       | Print install paths and binary state.                |
| `selene install hyprland` | Append a `source =` line with markers; never edits the rest of the config. |
| `selene remove hyprland`  | Strip the markers and source line cleanly.       |

Override paths with `SELENE_SRC`, `SELENE_BUILD`, `SELENE_SHARE`, `SELENE_BIN_DIR`
or `HYPRLAND_CONFIG` when needed.

---

## Configuration

Selene is configured through Lua scripts in `~/.config/selene/`. An example
`init.lua`:

```lua
return {
  panel = {
    height     = 36,
    position   = "top",
    transparent = true,
    modules    = { "workspaces", "clock", "tray", "island" },
  },
  launcher = {
    width        = 640,
    max_results  = 8,
    show_icons   = true,
    placeholder  = "Search apps, files, actions...",
  },
  theme = {
    accent     = "#a78bfa",
    background = "#1a1b1e",
    surface    = "#2a2b2e",
    font = {
      family = "Inter",
      size   = 13,
    },
  },
  binds = {
    ["SUPER"]        = "launcher",
    ["SUPER + D"]    = "dashboard",
    ["SUPER + L"]    = "lock",
    ["SUPER + ESC"]  = "power",
  },
}
```

Window rules, custom modules and per-monitor overrides follow the same pattern --
plain Lua tables returned from their respective files.

---

## Project Status

Selene is actively prototyping the compositor bridge and core surfaces. The
event-driven pipeline is live; the rest of the HUD is being ported.

### Milestones

- [x] Rust project skeleton with `cxx-qt` bridge
- [x] Hyprland IPC connection (`hyprland-rs`, push-based via event listener +
      `cxx_qt::CxxQtThread` queued calls back to the Qt main thread)
- [x] Ambxst-style non-invasive installer + `selene` CLI surface
- [x] Design tokens (`rust/qml/Tokens.qml` singleton) + mock `Bar.qml` driven by
      live `Bridge` properties
- [x] Launcher overlay (Hax-style) backed by a `Spawner` QObject that enumerates
      `/usr/share/applications` and exposes `launch(exec)` / `run_action(label)`
      qinvokables
- [x] Dynamic Island overlay (`IslandPill`) with `/proc`-backed metrics and
      mocked media, morphing between collapsed pill and expanded card via
      implicit width/height `Behavior` animations
- [x] Notification center + persistence (`Notifier` QObject with JSON file
      storage at `~/.local/share/selene/notifications.json`, DND toggle,
      `mark_read/clear/refresh_from_disk` qinvokables, and `NotificationPanel.qml`
      panel rendering)
- [x] Lua config loader (`mlua` 0.12 embedded in Rust; the `Config` QObject
      loads `~/.config/selene/init.lua` on startup, exposes every value as
      `#[qproperty]`, and falls back to defaults when the file is absent or
      invalid)
- [x] **Live palette engine** -- `Palette` QObject reads the wallpaper at
      `~/.local/share/selene/wallpaper.png` (or swww/`Pictures/Wallpapers`),
      extracts the dominant 6 colors via 5-bit bucketing, derives an
      accent + surface + background palette, and exposes it as properties
      (`accent`, `surface`, `background`, `text_color`, `dominant_json`).
      Inspired by [cava-bg](https://github.com/leriart/cava-bg)'s adaptive
      color feature; embedded here to keep the theme-update pipeline in-process.
      **Also handles video wallpapers**: when the source has a video
      extension, ffmpeg is invoked through `pipe:1` to extract a single
      64x64 RGB24 frame which is then quantized with the same algorithm.
- [x] **Theme runtime override** -- `Palette` color updates push into the
      `Tokens` singleton via `Connections` with `Behavior on color` smooth
      `ColorAnimation` transitions; every visible surface repaints when the
      wallpaper changes
- [x] **Wallpaper surface** -- `Wallpaper` QObject enumerates a directory of
      images / GIFs / videos (`jpg`, `png`, `webp`, `gif`, `apng`, `mp4`,
      `webm`, `mkv`, `mov`, `avi`, `m4v`) and `WallpaperSurface.qml` renders
      the right one via `Image` / `AnimatedImage` / `MediaPlayer + VideoOutput`.
      `Palette` follows `Wallpaper.current_path` automatically. Foreground
      mimics [NothingLess](https://github.com/leriart/NothingLess)'s
      `Wallpaper.qml` + `VideoWallpaperService.qml` pattern; rendered inside
      the `ApplicationWindow` because cxx-qt's `QQuickView` doesn't yet push
      a `WlrLayershell` Background layer.
- [ ] D-Bus daemon -- serve `org.freedesktop.Notifications` on the session bus
      so any `notify-send` lands in the `Notifier` queue (architecture in place,
      `dbus`-crate binding held back until we wire a response message that matches
      the spec)
- [ ] Wire `Palette` colors into more Tokens (font, borders, danger/success) so
      every chrome surface paints with the wallpaper-derived palette
- [ ] **Wayland layer-shell rendering** -- paint the wallpaper at the
      `WlrLayer.Background` compositor layer so it shows when the shell window
      is unfocused. Requires switching from `QGuiApplication` + `QQmlApplicationEngine`
      to a `Quickshell`-like layer-shell host (or hand-rolling
      `zwlr-layer-shell-v1` bindings).
- [ ] Theme engine with `matugen` integration (DPI scaling, Material You extras)
- [ ] Settings panel + per-screen overrides
- [ ] Snapshot/restore for game and focus modes
- [ ] Lockscreen with PAM and `WlSessionLock`

### Non-Goals

- Replacing Hyprland. Selene is a shell on top, never against.
- Becoming a desktop environment. Widget scope stops at the overlay surface.
- Shipping a configuration GUI on day one. The Lua config is the interface.

---

## Contributing

Issues and pull requests are welcome. Before opening a PR, please read `AGENTS.md` (if
present) and skim the structure of the `modules/` and `services/` directories so your
change lands in the right place.

For larger changes (new modules, IPC backends, theming primitives), open an issue first
to discuss the design.

---

## License

Apache 2.0 -- see [LICENSE](LICENSE).

---

## Inspiration

- **[Ambxst](https://github.com/Axenide/Ambxst)** -- installer philosophy, command
  surface, glyph-based interaction.
- **[Caelestia Shell](https://github.com/caelestia-dots/shell)** -- lightweight
  philosophy, token-based theming, fluid overlay language.
- **[NothingLess](https://github.com/leriart/NothingLess)** -- axctl bridge, Dynamic
  Island, Ndot visual language, FPS pipeline, the entire predecessor codebase.
- **[Hax](https://github.com/fabiolopezperez-hue/ambxst-Hax)** -- spotlight/launcher
  with calculator and plugin system.
- **[AwesomeWM](https://github.com/awesomeWM/awesome)** -- proven Lua-driven window
  manager configuration model.
- **[Waybar / Eww](https://github.com/Alexays/Waybar)** -- QML-based overlays that
  proved this stack viable on Wayland.
