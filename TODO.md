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
- [x] **Manual palette override** -- done. `Config.palette_follow_wallpaper`
      (default true) gates the palette->Tokens wiring in Main.qml. When
      false, the palette still runs but doesn't paint Tokens; only the
      theme_* values do. The Settings panel grows a Switch next to the
      color editors.
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
- [x] **Contrast helper** -- done. `Palette` picks `text_color` from a
      candidate ladder using WCAG 2.x `contrast_ratio` (relative luminance,
      target >= 4.5:1); falls back to the best-scoring candidate when the
      background is mid-luminance.

### Audio / visualizer integration

- [x] **CAVA bridge** -- done. `Visualizer` QObject spawns `cava -p` with
      a generated raw ASCII config, parses each `v;v;...;` frame on a
      reader thread, and pushes `bars_json` + `peak` into the QML via
      the cxx-qt queue at ~15fps. The IslandPill collapsed view renders
      the bars while `media_playing == true`.
- [ ] **cava-bg IPC** -- if cava-bg stays external (it is today), add a
      JSON/socket palette export so Selene can consume it without compiling in
      the visualizer.
- [ ] **Hidden image / X-ray mode** behind the bars (port from cava-bg).

### Compositor + IPC

- [x] **Push real MPRIS data** into `Island.media_title`/`_artist`/`_playing`
      -- done via `playerctl metadata --format` subprocess polling on the 2s
      Island tick (no zbus dep). Degrades to "Nothing playing" when no player
      or playerctl is absent.
- [ ] **Wayland layer-shell** for the panels (`Bar`, `Launcher`,
      `NotificationPanel`, `Island`) so they paint under the compositor's
      window-management rules, not as ApplicationWindow children.
- [x] **Hardware-accelerated video wallpaper** -- `WallpaperSurface.qml` uses
      `MediaPlayer + VideoOutput` from QtMultimedia (Qt 6.11); HW decoding
      is delegated to the system's ffmpeg/MediaFoundation/VA-API pipeline.
- [ ] **Real `hyprctl JSON`-driven monitors screen** -- a Settings surface for
      resolution, scale, transform, VRR per output.
- [x] **CPU% sampler** for `Island.cpu_percent` -- done. Reads `/proc/stat`
      on each 2s tick and diffs against the previous sample (classic
      (totald - idled) / totald). Also battery via
      `/sys/class/power_supply/*/capacity` and a clock property.
- [x] **Audio QObject** -- `Audio.refresh()` lists sinks via `pactl list sinks`,
      `Audio.set_volume` / `toggle_mute` / `set_default_sink` /
      `bump(±%)` write back to pactl. `AudioPanel.qml` is the Quick
      Settings surface: slider, mute toggle, +/- buttons, sink list.
      Refreshes every 5s via a QML Timer.
- [x] **Network QObject** -- `Network` exposes wifi state + nearby
      networks, active connection + IPv4, and `wifi_on / wifi_off /
      connect_ssid / disconnect` qinvokables. `NetworkPanel.qml` is the
      Quick Settings surface with a toggle, an active-connection card,
      and a click-to-connect wifi list.
- [x] **Bluetooth QObject** -- `Bluetooth` parses `bluetoothctl show /
      list / devices -v`, exposes `powered / discoverable / adapter_name /
      adapter_mac / devices_json`, and `power_on / power_off / toggle /
      connect_device / disconnect_device / pair_device` qinvokables.
      `BluetoothPanel.qml` is the Quick Settings surface with a switch
      and a click-to-(pair|connect|disconnect) device list.

### Notifications

- [x] **D-Bus daemon** -- done. `Notifier.start_dbus()` spawns a `zbus`
      blocking connection serving `org.freedesktop.Notifications` on
      `/org/freedesktop/Notifications`: `Notify` / `CloseNotification` /
      `GetCapabilities` / `GetServerInformation`, emits `NotificationClosed`
      and `ActionInvoked`, honors `replaces_id` / `urgency` hint /
      `image-path` hint / actions / DND, and queues every store mutation back
      to QML via `CxxQtThread`. DoNotQueue: fails loudly when another daemon
      owns the name.
- [ ] **Persistence layer upgrades** -- rotation, cap at N entries, optional
      SQLite or sled backend instead of JSON for cleaner queries.
- [x] **Action buttons** -- done. `actions` array is stored per entry
      (key/label pairs), `NotificationPanel.qml` renders a button row, and
      `Notifier.invoke_action(id, key)` emits `ActionInvoked` over the bus.

### Launcher / Spawner

- [x] **`.desktop` field-code expansion** -- done per freedesktop spec:
      `%f/%F/%u/%U` (files/URLs) drop out, `%i/%c/%k` (icon/name/location)
      drop out, `%%` becomes a literal percent, whitespace collapses.
- [x] **`TryExec` preflight** -- entries whose `TryExec` binary isn't on PATH
      are skipped during enumeration, per the desktop-entry spec.
- [x] **Detached spawn via `setsid --fork`** -- children land in their own
      session and outlive the shell process; falls back to plain spawn when
      `setsid` is absent.
- [x] **Hax-style prefixes** -- `=` calculator (sanitized JS expression via
      `new Function`) and `?` web search (DuckDuckGo URL via
      `Spawner.open_url`, dispatched to `xdg-open`) shipped. `:` emoji
      picker and `/` bookmark search still pending.
- [x] **App search ranking by usage** -- `Spawner.record_launch(label)` writes
      to `~/.local/share/selene/launcher-stats.json`; on `refresh()` the
      `apps_json` is sorted by frequency (desc) then alphabetical; the
      `weight` field is exposed in each entry for QML re-ranking.

### Config / Settings

- [x] **Settings panel QML (v1)** -- `SettingsPanel.qml` edits every scalar
      Config property (SpinBox / Switch / ComboBox / TextField) via
      `Config.set_value(key, val)` and persists with `Config.save()`, which
      serializes the live state back to `init.lua`.
- [ ] **Per-screen overrides** for panel position, bar layout, accent density.
- [x] **Hot-reload of `init.lua`** via inotify watcher -- `Config.start_watcher()`
      spawns a thread that watches the parent directory with `notify`, debounces
      250ms, then calls `Config.reload()` on the Qt main thread via the cxx-qt
      queue.
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
- [x] **`selene doctor`** subcommand that prints versions of Qt, Rust,
      Hyprland, CAVA, ffmpeg, liblua, dbus, plus token presence.
- [ ] **Smoke-test under Nix** -- the install script detects Nix but doesn't
      exercise a `nix run` path.

### Documentation

- [x] **Screenshots in README** -- `selene-shell --screenshot <path>` grabs
      the QQuickWindow to PNG and exits; assets/screenshot-shell.png shows
      the live shell (Bar, IslandPill, debug grid, logo) and is regenerated
      via `QT_QPA_PLATFORM=offscreen`. Per-panel screenshots are still TODO.
- [x] **AGENTS.md** -- shipped. Captures the post-reorganize layout, the
      dual CMake/Corrosion build flow, the cxx-qt bridge do/don't, the
      qrc asset convention, and the signal/threading patterns.
- [ ] **User-facing wiki** (private), or `docs/` folder with:
      - per-surface screenshots
      - layer-shell quirks
      - known-good Hyprland config snippets
- [ ] **Per-file `//!` headers** on every Rust file explaining its place in
      the bridge / QML runtime.

## Done

Shipped in chronological order (newest at top).

- [x] **Real Island metrics** -- CPU% (`/proc/stat` deltas), battery
      (`/sys/class/power_supply`), clock (`time_hhmm`/`date_ymd`), MPRIS via
      `playerctl` (replaces mocked media). 2026-08-07.
- [x] **Power menu actions** -- `Island.lock/suspend/reboot/poweroff/logout`
      qinvokables dispatching to `loginctl`; surfaced as buttons in the
      expanded `IslandPill` card. 2026-08-07.
- [x] **Launcher ranking by usage** -- `Spawner.record_launch(label)` writes
      to `~/.local/share/selene/launcher-stats.json`; `apps_json` is sorted
      by frequency. 2026-08-07.
- [x] **Inotify hot-reload of init.lua** via `notify` + cxx_qt queue. 2026-08-07.
- [x] **`selene doctor`** -- new subcommand printing a per-binary /
      per-config diagnostic. 2026-08-07.
- [x] **Audio QObject + AudioPanel** -- pactl-backed volume/mute/sinks
      listing with a slider and the default sink selector. 2026-08-07.
- [x] **Network QObject + NetworkPanel** -- nmcli-backed wifi + connection
      manager with toggle, active connection card, and click-to-connect
      wifi list. 2026-08-07.
- [x] **Theme runtime override** (extended) -- font_family / theme_accent /
      theme_background / theme_surface from Config now flow into Tokens
      live, so a Settings panel edit or a reloaded init.lua immediately
      re-themes the whole shell. 2026-08-07.
- [x] **Launcher spec compliance** -- field-code expansion, `TryExec`
      preflight, `setsid --fork` detached spawn, icon/terminal in apps_json.
      2026-08-07.
- [x] **WCAG contrast text** in `Palette` (4.5:1 ladder). 2026-08-07.
- [x] **`Config.save()` + `set_value()`** -- writes live state back to
      `init.lua`; `SettingsPanel.qml` is the editor UI. 2026-08-07.
- [x] **`WallpaperPicker.qml`** -- thumbnail grid over
      `Wallpaper.paths_json`, prev/next/rescan, click-to-pick. 2026-08-07.
- [x] **Bar clock + battery chip** fed by `Island`. 2026-08-07.
- [x] **Cava visualizer** -- `Visualizer` QObject spawns `cava -p` with a
      generated raw ASCII config, parses each `v;v;...;` frame on a
      reader thread, and pushes `bars_json` + `peak` into the QML via
      the cxx-qt queue at ~15fps. The IslandPill collapsed view shows
      the bars while `media_playing == true`. 2026-08-08.
- [x] **Launcher prefixes (Hax-style)** -- `=` calculator (sanitized JS
      expression via `new Function`) and `?` web search (DuckDuckGo URL
      via `Spawner.open_url`, dispatched to `xdg-open`). 2026-08-08.
- [x] **Manual palette override** -- `Config.palette_follow_wallpaper`
      (default true) gates the palette->Tokens wiring in Main.qml so a
      user who picks custom theme_* values can stop the wallpaper from
      overriding them. 2026-08-08.
- [x] **`--screenshot` / `--delay` flags** -- `selene-shell --screenshot
      <path>` graba `QQuickWindow::grabWindow()` después de N ms y sale.
      Habilita screenshots en CI / docs sin sesión Wayland. 2026-08-08.
- [x] **`AGENTS.md`** -- project guide for AI agents covering the
      post-reorganize layout, build flow, do/don't, where to look. 2026-08-08.
- [x] **`selene-shell` reorganized** -- Cargo workspace at the repo root,
      single member at `crates/selene-shell/`, `src/main.cpp` for the
      executable, `scripts/{install,cli}.sh`, `assets/` for the brand
      logos (bundled into the binary via qrc), `docs/` placeholder. 2026-08-07.

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
      module + src/main.cpp.
- [x] **README rewrite** with lineage / philosophy / stack / features /
      milestones sections.

## How to add a new TODO

1. Drop a bullet in the right group. Use `- [ ]` so a future grep can drain
   status.
2. Reference upstream sources inline (cava-bg commit, Hyprland dispatch
   spec, a freedesktop URL) so the next contributor can verify the claim.
3. When shipping, move to `Done` with a short sentence of the API/state and
   the date it shipped -- keeps the docs honest about what existed.
