# Selene-Shell

> A QML shell for Hyprland. Light as moonlight, solid as Rust.

Selene is a modern, visually refined shell built on top of Hyprland. Its user interface is crafted in QML, backed by a high-performance Rust core, and scriptable in Lua. The name draws from Selene, the Greek titaness of the moon -- a nod to Lua (moon in Portuguese) as the scripting language, riding on a foundation of Rust.

---

## Philosophy

Selene exists at the intersection of two ideas:

- **Visual ambition** -- the polished, minimalist language of NothingLess/Ambxst: clean typography, translucent overlays, deliberate whitespace, subtle motion.
- **Resource discipline** -- the lightness of Caelestia: no unnecessary allocations, no heavy frameworks in the hot path, a shell that stays out of your way and your RAM.

The UI layer (QML) is free to be expressive and animated. The backend (Rust) is free to be ruthless about performance. Lua scripts bridge the two with minimal overhead.

---

## Architecture

```
                               QML Layer
  ┌─────────────────────────────────────────────────────┐
  │  Panel      Launcher      Notification Center       │
  │  OSD        App Switcher  Quick Settings            │
  └─────────────────────┬───────────────────────────────┘
                        │
                        │ QtQuick / QQmlApplicationEngine
                        │
  ┌─────────────────────┴───────────────────────────────┐
  │                   Rust Backend                       │
  │                                                      │
  │  ┌────────────┐  ┌──────────────┐  ┌─────────────┐  │
  │  │ hyprland-rs│  │  mlua (Lua)  │  │ cxx-qt /    │  │
  │  │ IPC socket │  │  engine      │  │ qmetaobject │  │
  │  └────────────┘  └──────────────┘  └─────────────┘  │
  │                                                      │
  │  Workspace Manager -- Window Tracker -- Config       │
  └──────────────────────────────────────────────────────┘
```

### Components

| Layer | Technology | Responsibility |
|-------|-----------|----------------|
| UI | QML / QtQuick 6 | Panels, overlays, animations, input |
| Bridge | Rust (cxx-qt) | Expose backend data to QML as properties/models |
| Compositor IPC | hyprland-rs | Socket communication with Hyprland |
| Scripting | mlua (Lua 5.4) | User config, keybindings, rules, theming |
| Core | Rust | Workspace tracking, event dispatch, resource management |

---

## Why Rust + QML + Lua

### Rust

- Zero-cost abstractions and strict compile-time safety for a process that runs 24/7.
- `hyprland-rs` provides a typed, async API over the Hyprland Unix socket.
- `mlua` embeds Lua 5.4 with sandboxing and minimal overhead (~20 KB per state).
- `cxx-qt` or `qmetaobject-rs` bridges the Rust backend to the QML engine without an intermediate C++ layer.

### QML

- Declarative UI that separates visual design from logic.
- Hardware-accelerated rendering via Qt Quick scene graph.
- Live reloading during development for rapid iteration.
- Mature enough for complex overlays, animations, and multi-surface shells.

### Lua

- The lightest practical scripting language (~20 KB runtime footprint).
- Proven in the window manager space (AwesomeWM, Qtile).
- Flat learning curve for users writing config files.
- Sandboxable -- user scripts cannot crash the shell.

---

## Getting Started

### Prerequisites

- Hyprland (running session)
- Qt 6.5+ (qt6-qtquick, qt6-qtwayland, qt6-declarative)
- Rust toolchain (edition 2024+)
- CMake (for Qt integration modules)

### Build

```bash
git clone https://github.com/your-user/selene-shell
cd selene-shell
cargo build --release
```

### Run

```bash
# From within a Hyprland session
./target/release/selene-shell
```

Configuration is read from `~/.config/selene/init.lua`.

---

## Configuration

Selene is configured entirely through Lua scripts in `~/.config/selene/`. An example `init.lua`:

```lua
return {
  panel = {
    height = 36,
    position = "top",
    transparent = true,
    modules = { "workspaces", "clock", "tray" },
  },
  launcher = {
    width = 640,
    max_results = 8,
    show_icons = true,
  },
  theme = {
    accent = "#a78bfa",
    background = "#1a1b1e",
    surface = "#2a2b2e",
    font = {
      family = "Inter",
      size = 13,
    },
  },
}
```

Keybindings, window rules, and custom modules follow the same pattern -- plain Lua tables returned from their respective files.

---

## Project Status

Selene is in early design and prototyping. The architecture and toolchain decisions are being validated through a minimal proof-of-concept before full development begins.

Current milestones:
- [ ] Rust project skeleton with cxx-qt bridge
- [ ] Hyprland IPC connection (workspace events, window events)
- [ ] QML panel displaying active workspaces
- [ ] Lua config loader exposing values to QML
- [ ] Launcher overlay with fuzzy finder
- [ ] Notification daemon integration
- [ ] Theming engine

---

## License

Apache 2.0 -- see [LICENSE](LICENSE).

---

## Inspiration

- **Ambxst / NothingLess** -- visual direction, glyph-based interaction, minimalist design language.
- **Caelestia** -- lightweight philosophy, resource-conscious architecture.
- **AwesomeWM** -- proven Lua-driven window manager configuration model.
- **Waybar / Eww** -- QML-based bars and widgets that demonstrated the viability of this stack on Wayland.
