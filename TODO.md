# Selene-Shell TODO

Living roadmap tracked in source. Move items to the [done] section when shipped;
keep them there as a release history until they age out.

## Inbox (ideas, not yet scoped)

These are concrete things the project should grow into. Pulled from session
notes, the cava-bg conversation, the NothingLess/Caelestia inspiration surface,
and the existing milestones.

### Visual / compositor surface

- [x] **Live palette engine** -- done. Driven by the wallpaper (PNG) **and**
      video / GIF frames (mp4/webm/gif via ffmpeg pipe). Implemented as a Rust
      `Palette` QObject that holds the dominant N colors and a derived accent /
      surface / background, and pushes them into the `Tokens` singleton via
      QML bindings. Reuses the same kind of dominant-color extraction cava-bg
      already does; embedded in this repo (no external process).
- [ ] **Manual palette override** so users without a matching wallpaper can pin
      the palette to a fixed set of colors. (defaults_used flag in `Config`
      + `Palette` falls back to the accent palette when no wallpaper is
      present, which IS the manual override -- a real picker UI is still TODO.)
- [ ] **Caelestia visual pass 2** -- ShaderEffectSource backdrop blur, screen
      rounded corners overlay, wallpaper-derived accent on the panel/launcher.
- [x] **Theme runtime override** -- `Palette` updates push into `Tokens` via
      `Connections` with `Behavior on color` `ColorAnimation`; every visible
      surface repaints when the wallpaper changes.
- [x] **Smooth color transitions** -- 600ms `ColorAnimation` per color role in
      `Tokens.qml` (added alongside the runtime override).
- [ ] **Wallpaper detection across managers** -- swww, hyprpaper, waypaper,
      swaybg, awww, wpaperd. Today: discover via `Pictures/Wallpapers` and
      `.local/share/selene/wallpapers`; let the user point `Wallpaper.use_directory`
      at whichever manager's backing dir.
- [ ] **Contrast helper** -- pick `text` and `textMuted` colors that maintain a
      4.5:1 ratio against the live `bg`. Reuse WCAG-style luminance math.

### Audio / visualizer integration

- [ ] **CAVA bridge** -- spawn an internal `cava` process, pipe its raw output
      into Selene and feed the magnitudes into the same `Palette` engine so
      whole shell tints to the current music energy.
- [ ] **cava-bg IPC** -- if cava-bg stays external (it is today), add a
      JSON/socket palette export so Selene can consume it without compiling in
      the visualizer.
- [ ] **Hidden image / X-ray mode** behind the bars (port from cava-bg).

### Compositor + IPC

- [ ] **Push real MPRIS data** into `Island.media_title`/`_artist`/`_playing`
      (currently mocked). D-Bus subscription to `org.mpris.MediaPlayer2.Player`.
- [ ] **Wayland layer-shell** for the panels (`Bar`, `Launcher`,
      `NotificationPanel`, `Island`) so they paint under the compositor's
      window-management rules, not as ApplicationWindow children.
- [x] **Hardware-accelerated video wallpaper** -- `WallpaperSurface.qml` uses
      `MediaPlayer + VideoOutput` from QtMultimedia (Qt 6.11); HW decoding
      is delegated to the system's ffmpeg/MediaFoundation/VA-API pipeline.
- [ ] **Real `hyprctl JSON`-driven monitors screen** -- a Settings surface for
      resolution, scale, transform, VRR per output.
- [ ] **CPU% sampler** for `Island.metrics_cpu` instead of load-average only.
      Reads `/proc/stat` twice with deltas; needs a small Rust sampler.
- [ ] **Network / Bluetooth / Audio** QObjects so the Quick Settings surface
      has real data.

### Notifications

- [ ] **D-Bus daemon** -- serve `org.freedesktop.Notifications` with the
      proper reply shape (UINT32 id, GetCapabilities, GetServerInformation,
      CloseNotification). The stub in `notifications.rs` currently only uses
      `dbus` crate for an incoming message handler; full surface pending.
- [ ] **Persistence layer upgrades** -- rotation, cap at N entries, optional
      SQLite or sled backend instead of JSON for cleaner queries.
- [ ] **Action buttons** in the notification body -- `dbus`-spec passes
      actions as ARRAY; need to wire the callback for invoked actions.

### Launcher / Spawner

- [ ] **`.desktop` field-code expansion** (the spec is documented; full URL
      handling, %u/%F replacement, terminal flag).
- [ ] **`TryExec` preflight** -- skip apps where the binary isn't on PATH.
- [ ] **Detached spawn via `setsid`** so children truly outlive the shell
      process rather than inheriting session association.
- [ ] **Hax-style prefixes** beyond `@` and `>` -- `=` calculator, `?` web
      search, `:` emoji picker, `/` bookmark search.
- [ ] **App search ranking by usage** (track launches in
      `~/.local/share/selene/launcher-stats.json`, weight by recency/frequency).

### Config / Settings

- [ ] **Full Settings panel QML** -- every Config/Bridge/Island/Notifier/Spawner
      property as a searchable, filterable list with inline editors.
- [ ] **Per-screen overrides** for panel position, bar layout, accent density.
- [ ] **Hot-reload of `init.lua`** via inotify watcher (currently requires a
      full `selene reload` to re-read).
- [ ] **Vendor-agnostic Settings backend** -- let power users swap the
      `Config` Rust impl with a Lua-only sandboxed one.

### Power / Lifecycle

- [ ] **Snapshot/restore** -- save compositor state (gaps, animations, focused
      workspace, monitor order) on `game mode`/`focus mode` enter, restore on
      exit.
- [ ] **Lockscreen** with `WlSessionLock` + PAM (matches a future `selene-lock`
      daemon) and a QML pin-entry surface.
- [ ] **`binds.json` write-back** -- Settings panel edits writes changes to
      `~/.local/share/selene/hyprland.conf` markers atomically.
- [ ] **Global shortcuts via D-Bus** (`com.github.selene.Shell`) so external
      apps can toggle DND / popup the launcher / lock.

### OS / packaging

- [ ] **AUR package** + **Fedora COPR** + **Nix flake** -- mirrors the Selene
      install policy on each ecosystem.
- [ ] **`selene doctor`** subcommand that prints versions of Qt, Rust, Hyprland,
      CAVA, ffmpeg, liblua, dbus, plus token presence.
- [ ] **Smoke-test under Nix** -- the install script detects Nix but doesn't
      exercise a `nix run` path.

### Documentation

- [ ] **Screenshots in README** -- Bar, Launcher, NotificationPanel, expanded
      Island, the palette gradient driving Tokens.
- [ ] **AGENTS.md** for AI agents describing the file layout, build steps,
      do/don't of the cxx-qt bridge, and how to add a new QObject.
- [ ] **User-facing wiki** (private), or `docs/` folder with:
      - per-surface screenshots
      - layer-shell quirks
      - known-good Hyprland config snippets
- [ ] **Per-file `//!` headers** on every Rust file explaining its place in
      the bridge / QML runtime.

## Done

Shipped in chronological order (newest at top).

- [x] **Notification center** with JSON persistence, DND, mark-read/clear
      (`Notifier` QObject + `NotificationPanel.qml`). 2026-XX-XX.
- [x] **Lua config loader** via `mlua` 0.12 (`Config` QObject + sample
      `init.lua`). 2026-XX-XX.
- [x] **Dynamic Island overlay** (`IslandPill.qml`) morphing between pill and
      expanded card, backed by `Island` QObject reading `/proc/loadavg` and
      `/proc/meminfo`. 2026-XX-XX.
- [x] **Spawner** (`Spawner` QObject) enumerating `/usr/share/applications`
      via `.desktop` parsing, exposing `launch(exec)` / `run_action(label)`
      qinvokables, JSON-encoded list properties. 2026-XX-XX.
- [x] **Launcher overlay** (Hax-inspired) with SUPER toggle, app/action
      prefixes, fuzzy list, Indexed keys for navigation. 2026-XX-XX.
- [x] **Hyprland event listener** push-based via `cxx_qt::CxxQtThread` queued
      calls into the Qt main thread. 2026-XX-XX.
- [x] **Tokens singleton** + mock **Bar** with workspace chips, pill, badge.
      2026-XX-XX.
- [x] **install.sh + cli.sh** (Ambxst-style non-invasive installer,
      `~/.local/bin/selene` symlink, marker-based `hyprland.conf` integration).
- [x] **Hyprland IPC via `hyprland-rs`** -- 1Hz polling + 10 properties.
- [x] **Skeleton** -- cxx-qt + CMake + Corrosion + CMakeLists.txt + QML
      module + cpp/main.cpp.
- [x] **README rewrite** with lineage / philosophy / stack / features /
      milestones sections.

## How to add a new TODO

1. Drop a bullet in the right group. Use `- [ ]` so a future grep can drain
   status.
2. Reference upstream sources inline (cava-bg commit, Hyprland dispatch
   spec, a freedesktop URL) so the next contributor can verify the claim.
3. When shipping, move to `Done` with a short sentence of the API/state and
   the date it shipped -- keeps the docs honest about what existed.
