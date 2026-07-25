# Selene-Shell

> A QML shell for Hyprland. Light as moonlight, solid as Rust.

Selene is a modern, visually refined shell for [Hyprland](https://hyprland.org) and the
spiritual successor to [NothingLess](https://github.com/leriart/NothingLess). Its user
interface is crafted in QML, backed by a high-performance Rust core, and scriptable in
Lua. The name draws from Selene, the Greek titaness of the moon -- a nod to Lua (Lua
means moon in Portuguese) riding on a foundation of Rust.

---

## Lineage

Selene stands on the shoulders of three projects:

- **[Ambxst](https://github.com/Axenide/Ambxst)** -- non-intrusive installer philosophy,
  the `cli` command surface, the dot-Material design language and the "the shell
  never edits your config" promise.
- **[Caelestia Shell](https://github.com/caelestia-dots/shell)** -- the bar/launcher
  visual identity, the token-based theming system, fluid overlays and the discipline of
  a single JSON config the user owns.
- **[NothingLess](https://github.com/leriart/NothingLess)** -- the axctl compositing
  bridge, the Dynamic Island, the Ndot visual language, the FPS pipeline, the Mirai
  screen-sharing integration, and every lessons-learned shipped during its lifetime.

Selene keeps what worked, ditches what proved fragile, and finishes the migration to a
type-safe Rust backend that NothingLess only started.

---

## Philosophy

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
  ┌──────────────────────────────────────────────────────┐
  │   Panel      Launcher       Notification Center      │
  │   OSD        Overview       Quick Settings           │
  └─────────────────────┬────────────────────────────────┘
                        │
                        │ QtQuick / QQmlApplicationEngine
                        │
  ┌─────────────────────┴────────────────────────────────┐
  │                      Rust Backend                     │
  │                                                       │
  │   ┌──────────────┐  ┌──────────────┐  ┌────────────┐  │
  │   │  hyprland-rs │  │  mlua (Lua)  │  │ cxx-qt /   │  │
  │   │  IPC client  │  │  engine      │  │ qmetaobject│  │
  │   └──────────────┘  └──────────────┘  └────────────┘  │
  │                                                       │
  │   Workspace Manager  •  Window Tracker  •  Config   │
  └───────────────────────────────────────────────────────┘
```

### Stack

| Layer            | Technology              | Responsibility                                       |
|------------------|-------------------------|------------------------------------------------------|
| UI               | QML / QtQuick 6         | Panels, overlays, animations, input                  |
| Build glue       | CMake + Corrosion       | Orchestrates Rust (cargo) and C++ (Ninja)            |
| Bridge           | Rust (cxx-qt)           | Expose backend data to QML as properties and models  |
| Compositor IPC   | hyprland-rs             | Typed async client over the Hyprland Unix socket     |
| Scripting        | mlua (Lua 5.4)          | User config, keybindings, rules, theming             |
| Core             | Rust                    | Workspace tracking, event dispatch, resource mgmt    |

---

## Why Rust + QML + Lua

### Rust

- Zero-cost abstractions and strict compile-time safety for a process that runs 24/7.
- `hyprland-rs` provides a typed, async API over the Hyprland Unix socket.
- `mlua` embeds Lua 5.4 with sandboxing and a ~20 KB state footprint.
- `cxx-qt` (or `qmetaobject-rs`) bridges the Rust backend to the QML engine without an
  intermediate C++ layer or per-frame marshalling.

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

## Features

### Desktop and Layout

- **Dynamic Island** -- a unified notch and bar that hosts the launcher, dashboard,
  notifications, media controls, system metrics and the power menu.
- **Dynamic Bar** -- static, extended or island modes with per-monitor position, size
  and widget groups.
- **Free Layout** -- a floating, Windows-like mode with intelligent edge snap and
  keyboard-driven tiling helpers.
- **Overview** -- a Mission Control-style workspace manager with live window previews
  and drag-and-drop moving.

### Configuration

- **Lua-First Config** -- `~/.config/selene/init.lua` is the single source of truth.
- **Reactive JSON Overrides** -- ad-hoc tweaks live in `~/.local/state/selene/` and
  are consumed by the Lua engine, never the other way around.
- **Token Theming** -- rounding, spacing, fonts, animations and transparency derive from
  a central token map, modeled after Caelestia's `shell-tokens.json`.
- **Material You** -- wallpaper-driven palette generation via `matugen`, propagated to
  GTK, Qt, Kitty and Discord.

### Compositor Integration

- **Hyprland Bridge** -- a typed Rust client that hydrates QML models from the IPC
  stream with zero allocations on the hot path.
- **Snapshot/Restore** -- instant rollback for game mode, focus mode and any config
  experiment.
- **Lockscreen** -- secure `WlSessionLock` plus PAM authentication.

### System and Productivity

- **App Launcher** -- fuzzy search with multi-tab categories.
- **Clipboard Manager** -- searchable history with categories and favorites.
- **FPS Monitoring** -- MangoHud + `libambfps.so` pipeline ported from NothingLess,
  reading from shared memory and rendered in the island.
- **Notifications** -- D-Bus notification server with persistence, history and DND.
- **Audio, Network and Bluetooth** -- Wi-Fi scan/connect, Bluetooth pairing and a
  PulseAudio/PipeWire mixer.

### Media and AI

- **MPRIS Controller** -- media controls across the bar, island and dashboard.
- **AI Sidebar** -- multi-provider chat (OpenAI, Anthropic, Gemini, Ollama and more)
  with tool calling and MCP-style agents.

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

The first configure auto-fetches the
[`cxx-qt-cmake`](https://github.com/KDAB/cxx-qt-cmake) integration layer (pinned to
the tag that matches the in-tree `cxx-qt` Rust crate) and compiles the Rust static
library, the C++ glue generated by `cxx-qt-gen`, and the `selene-shell` executable
in one pass.

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

Selene is in early design and prototyping. The architecture and toolchain decisions are
being validated through a minimal proof of concept before full development begins.

### Milestones

- [x] Rust project skeleton with `cxx-qt` bridge
- [x] Hyprland IPC connection (`hyprland-rs`, 1 Hz polling -- push-based event
      listener queued behind the async/tokio bridge)
- [x] Ambxst-style non-invasive installer + `selene` CLI surface
- [ ] QML panel displaying active workspaces
- [ ] Lua config loader exposing values to QML
- [ ] Launcher overlay with fuzzy finder
- [ ] Dynamic Island with media, metrics and notifications
- [ ] Theme engine with `matugen` integration
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
- **[AwesomeWM](https://github.com/awesomeWM/awesome)** -- proven Lua-driven window
  manager configuration model.
- **[Waybar / Eww](https://github.com/Alexays/Waybar)** -- QML-based overlays that
  proved this stack viable on Wayland.
