pragma Singleton

import QtQuick

// Game / focus mode orchestrator (NothingLess GameModeService +
// FocusModeService port). This singleton owns no compositor plumbing
// of its own -- it drives the existing backends that Main.qml injects
// at startup:
//
//   * state    (State)    -- hyprctl snapshot / game_mode() / restore()
//   * notifier (Notifier) -- DND flag + user-facing notifications
//   * config   (Config)   -- performance.game_mode / focus_mode blocks
//   * spawner  (Spawner)  -- caffeine (systemd-inhibit) for focus mode
//
// Game mode: snapshot the compositor options, apply the reduced set
// (zero gaps, no blur, no shadow, no animations), mute the shell's
// own animations via Tokens.animationsEnabled, restore on disable.
//
// Focus mode: zero gaps + DND + caffeine (idle inhibit via
// loginctl/systemd-inhibit), snapshot/restore the same way.
QtObject {
    id: root

    // Backend references, injected by Main.qml on startup.
    property var state: null
    property var notifier: null
    property var config: null
    property var spawner: null

    property bool gameModeActive: false
    property bool focusModeActive: false
    property bool caffeineActive: false

    // performance.* blocks from init.lua; refreshed lazily on toggle.
    function _modeConfig(json, fallback) {
        try {
            return JSON.parse(json);
        } catch (e) {
            return fallback;
        }
    }

    function _notify(title, body) {
        if (root.notifier)
            root.notifier.notify("selene", title, body, 1, "");
    }

    // -- Game mode ------------------------------------------------------
    function enableGameMode() {
        if (gameModeActive || !root.state)
            return;
        const conf = _modeConfig(root.config ? root.config.game_mode_json : "{}",
                                 { disable_animations: true });
        // State.game_mode() snapshots the current hyprctl options first,
        // then applies zero gaps / no animations / VRR.
        root.state.game_mode();
        if (conf.disable_animations !== false)
            Tokens.animationsEnabled = false;
        if (root.notifier)
            root.notifier.apply_game_mode(true);
        gameModeActive = true;
        _notify("Game mode on", "Compositor effects reduced; snapshot saved.");
    }

    function disableGameMode() {
        if (!gameModeActive || !root.state)
            return;
        root.state.restore();
        Tokens.animationsEnabled = true;
        if (root.notifier)
            root.notifier.apply_game_mode(false);
        gameModeActive = false;
        _notify("Game mode off", "Compositor settings restored.");
    }

    function toggleGameMode() {
        if (gameModeActive)
            disableGameMode();
        else
            enableGameMode();
    }

    // -- Focus mode -----------------------------------------------------
    function enableFocusMode() {
        if (focusModeActive || !root.state)
            return;
        const conf = _modeConfig(root.config ? root.config.focus_mode_json : "{}",
                                 { dnd: true, caffeine: true });
        // State.focus_mode() snapshots, then quiets the compositor.
        root.state.focus_mode();
        if (conf.dnd !== false && root.notifier && !root.notifier.dnd_enabled)
            root.notifier.toggle_dnd();
        if (conf.caffeine !== false && root.spawner) {
            // Idle inhibit for the whole session; released on disable by
            // killing the inhibitor we spawned.
            root.spawner.launch(
                "systemd-inhibit --what=idle --who=selene-focus "
                + "--why='Selene focus mode' sleep infinity");
        }
        focusModeActive = true;
        _notify("Focus mode on", "Notifications muted, idle inhibited.");
    }

    function disableFocusMode() {
        if (!focusModeActive || !root.state)
            return;
        root.state.restore();
        if (root.notifier && root.notifier.dnd_enabled)
            root.notifier.toggle_dnd();
        if (root.spawner)
            root.spawner.launch("pkill -f 'selene-focus'");
        focusModeActive = false;
        _notify("Focus mode off", "Notifications and idle behaviour restored.");
    }

    function toggleFocusMode() {
        if (focusModeActive)
            disableFocusMode();
        else
            enableFocusMode();
    }

    // -- Caffeine (standalone idle inhibit) ------------------------------
    // NothingLess `run caffeine` port. Independent from focus mode's
    // inhibitor via a distinct --who tag so pkill never kills the wrong
    // one.
    function toggleCaffeine() {
        if (!root.spawner)
            return;
        if (caffeineActive) {
            root.spawner.launch("pkill -f 'selene-caffeine'");
            caffeineActive = false;
            _notify("Caffeine off", "Idle behaviour restored.");
        } else {
            root.spawner.launch(
                "systemd-inhibit --what=idle --who=selene-caffeine "
                + "--why='Selene caffeine' sleep infinity");
            caffeineActive = true;
            _notify("Caffeine on", "Screen will stay awake.");
        }
    }
}
