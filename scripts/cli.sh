#!/usr/bin/env bash
# Selene command-line entry point.
#
# Invoked as `selene <subcommand>`. Resolves the repo from this script's location
# so it works whether invoked from the source tree or from ~/.local/bin/selene.

set -euo pipefail

if [[ -z "${SELENE_SRC:-}" ]]; then
  SCRIPT_PATH="$(realpath -e "$0" 2>/dev/null || python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$0")"
  # `cli.sh` lives in <repo>/scripts/, so the repo root is one directory up.
  SELENE_SRC="$(dirname "$(dirname "$SCRIPT_PATH")")"
fi
SELENE_BUILD="${SELENE_BUILD:-$SELENE_SRC/build}"
SELENE_SHARE="${SELENE_SHARE:-$HOME/.local/share/selene}"
SELENE_BIN="$SELENE_BUILD/selene-shell"

usage() {
  cat <<EOF
selene <command> [args]

Commands:
  run [panel]         Launch the shell (default if no command is given).
                      With a running instance, opens/toggles <panel> live:
                      launcher | dashboard | overview | powermenu | binds |
                      clipboard | notif | walls | settings | audio | net | bt |
                      picker | island | metrics | weather | gamemode |
                      focusmode | dnd | caffeine | nightlight | record | lock
  reload              Reload the running shell instance.
  quit                Stop the running shell instance.
  lock                Lock the session (via the running shell, else loginctl).
  suspend             Suspend the system.
  record [region]     Toggle screen recording (wf-recorder; default full
                      screen, "region" selects an area with slurp).
  nightlight          Toggle the night light (wlsunset).
  dnd                 Toggle do-not-disturb.
  caffeine            Toggle idle inhibit (stay awake).
  update              Pull, rebuild, and re-stage.
  status              Show install paths and binary state.
  doctor              Diagnose the environment Selene runs against.
  profile <name>      Switch the power profile (powerprofilesctl set <name>).
  brightness <0-100>  Set the backlight percentage (brightnessctl).
  screenshot [mode]   Take a screenshot: screen (default) | region | window.
  install hyprland    Add the Selene source line to ~/.config/hypr/hyprland.conf.
  remove  hyprland    Remove the Selene source line.

Environment:
  SELENE_SRC    Source tree (default: derived from this script's path).
  SELENE_BUILD  Build directory (default: \$SELENE_SRC/build).
  SELENE_SHARE  Generated config/state directory (default: \$HOME/.local/share/selene).
EOF
}

# Panels / actions understood by Main.qml's applyScreenshotPanel().
SELENE_PANELS="launcher|notif|walls|settings|audio|net|bt|sidebar|clipboard|picker|island|dashboard|overview|powermenu|binds|notes|todo|terminal|metrics|weather|gamemode|focusmode|dnd|caffeine|nightlight|record|record-screen|record-stop|lock|suspend"

# Send a command to the running instance; returns non-zero when no
# instance is listening so callers can fall back to direct execution.
selene_send() {
  "$SELENE_BIN" --send "$1" 2>/dev/null
}

cmd_run() {
  local panel="${1:-}"
  if [[ ! -x "$SELENE_BIN" ]]; then
    echo "selene-shell not found at $SELENE_BIN" >&2
    echo "Run: selene update   (or curl|sh the installer again)" >&2
    exit 1
  fi
  case "$panel" in
    "")
      exec "$SELENE_BIN" ;;
    launcher|notif|walls|settings|audio|net|bt|sidebar|clipboard|picker|island|dashboard|overview|powermenu|binds|notes|todo|terminal|metrics|weather|gamemode|focusmode|dnd|caffeine|nightlight|record|record-screen|record-stop|lock|suspend)
      # Live instance first; otherwise start the shell with the panel.
      if selene_send "show $panel"; then
        exit 0
      fi
      exec "$SELENE_BIN" "--show=$panel" ;;
    *)
      echo "unknown panel: $panel (expected one of: ${SELENE_PANELS//|/, })" >&2
      exit 1
      ;;
  esac
}

cmd_lock() {
  if selene_send "show lock"; then
    exit 0
  fi
  loginctl lock-session
}

cmd_suspend() {
  if selene_send "show suspend"; then
    exit 0
  fi
  systemctl suspend
}

cmd_record() {
  local mode="${1:-screen}"
  case "$mode" in
    screen)        selene_send "show record-screen" || cmd_record_fallback "" ;;
    region)        selene_send "show record"        || cmd_record_fallback "region" ;;
    stop)          selene_send "show record-stop"   || pkill -INT -x wf-recorder ;;
    *)
      echo "usage: selene record [screen|region|stop]" >&2
      exit 1
      ;;
  esac
}

# Fallback when the shell isn't running: drive wf-recorder directly.
cmd_record_fallback() {
  local region="$1"
  if ! command -v wf-recorder >/dev/null 2>&1; then
    echo "wf-recorder not found (install wf-recorder)" >&2
    exit 1
  fi
  if pgrep -x wf-recorder >/dev/null; then
    pkill -INT -x wf-recorder
    echo "recording saved"
    exit 0
  fi
  local dir="$HOME/Videos/Recordings"
  mkdir -p "$dir"
  local out="$dir/recording-$(date +%Y%m%d-%H%M%S).mp4"
  if [[ -n "$region" ]]; then
    command -v slurp >/dev/null 2>&1 || { echo "slurp not found" >&2; exit 1; }
    wf-recorder -g "$(slurp)" -f "$out" &
  else
    wf-recorder -f "$out" &
  fi
  echo "recording -> $out (run again or 'selene record stop' to stop)"
}

cmd_profile() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    echo "usage: selene profile <performance|balanced|power-saver>" >&2
    exit 1
  fi
  if ! command -v powerprofilesctl >/dev/null 2>&1; then
    echo "powerprofilesctl not found (install power-profiles-daemon)" >&2
    exit 1
  fi
  powerprofilesctl set "$name"
  echo "power profile -> $name"
}

cmd_brightness() {
  local value="${1:-}"
  if [[ ! "$value" =~ ^[0-9]+$ ]] || (( value > 100 )); then
    echo "usage: selene brightness <0-100>" >&2
    exit 1
  fi
  if ! command -v brightnessctl >/dev/null 2>&1; then
    echo "brightnessctl not found (install brightnessctl)" >&2
    exit 1
  fi
  brightnessctl set "${value}%" >/dev/null
  echo "brightness -> ${value}%"
}

cmd_screenshot() {
  local mode="${1:-screen}"
  local dir="$HOME/Pictures/Screenshots"
  local out="$dir/selene-$(date +%Y%m%d-%H%M%S).png"
  if ! command -v grim >/dev/null 2>&1; then
    echo "grim not found (install grim; region mode also needs slurp)" >&2
    exit 1
  fi
  mkdir -p "$dir"
  case "$mode" in
    screen)
      grim "$out"
      ;;
    region)
      if ! command -v slurp >/dev/null 2>&1; then
        echo "slurp not found (needed for region capture)" >&2
        exit 1
      fi
      local geom
      geom="$(slurp)" || { echo "selection cancelled" >&2; exit 1; }
      grim -g "$geom" "$out"
      ;;
    window)
      if ! command -v hyprctl >/dev/null 2>&1; then
        echo "hyprctl not found (needed for window capture)" >&2
        exit 1
      fi
      local geom
      geom="$(hyprctl activewindow -j | python3 -c 'import json,sys; w=json.load(sys.stdin); print(f"{w[\"at\"][0]},{w[\"at\"][1]} {w[\"size\"][0]}x{w[\"size\"][1]}")')" \
        || { echo "no active window" >&2; exit 1; }
      grim -g "$geom" "$out"
      ;;
    *)
      echo "usage: selene screenshot [screen|region|window]" >&2
      exit 1
      ;;
  esac
  echo "saved: $out"
  command -v notify-send >/dev/null 2>&1 && notify-send "Screenshot" "$out" || true
}

cmd_reload() {
  # Prefer the live IPC socket; SIGUSR1 is handled in-process as a
  # fallback (see main.cpp). Both paths reload QML without dropping
  # the Wayland connection.
  if selene_send "reload"; then
    echo "reload sent"
  elif pkill -USR1 -x selene-shell; then
    echo "reload signal sent"
  else
    echo "no running selene-shell instance" >&2
    exit 1
  fi
}

cmd_quit() {
  if selene_send "quit"; then
    echo "selene-shell stopped"
  elif pkill -x selene-shell; then
    echo "selene-shell stopped"
  else
    echo "no running selene-shell instance" >&2
    exit 1
  fi
}

cmd_update() {
  cd "$SELENE_SRC"
  git pull --ff-only
  cargo generate-lockfile --manifest-path crates/selene-shell/Cargo.toml || true
  cmake --build build
}

cmd_status() {
  printf "source      : %s\n" "$SELENE_SRC"
  printf "build       : %s (%s)\n" "$SELENE_BUILD" "$([[ -x $SELENE_BIN ]] && echo built || echo missing)"
  printf "share       : %s (%s)\n" "$SELENE_SHARE" "$([[ -d $SELENE_SHARE ]] && echo ready || echo missing)"
  printf "binary      : %s\n" "$SELENE_BIN"
  printf "running pid : %s\n" "$(pgrep -x selene-shell || echo none)"
}

cmd_doctor() {
  local ok=0 format_line='%-16s %s\n'
  printf "$format_line" "selene" "selene-shell found"
  [[ -x $SELENE_BIN ]] && printf "$format_line" "" "($SELENE_BIN)" || { ok=1; printf "$format_line" "" "MISSING - run: selene update"; }
  printf "$format_line" "share" "${SELENE_SHARE}$([[ -d $SELENE_SHARE ]] && echo " (ready)" || echo " (missing; will be created on first run)")"

  local bins=("qmake6" "ffmpeg" "playerctl" "busctl" "hyprctl" "cava" "nmcli" "bluetoothctl" "pactl" "grim" "slurp" "wf-recorder" "wlsunset" "powerprofilesctl" "brightnessctl")
  for b in "${bins[@]}"; do
    local found
    if found="$(command -v "$b" 2>/dev/null)"; then
      printf "$format_line" "$b" "$found"
    else
      printf "$format_line" "$b" "MISSING"
      case "$b" in
        qmake6|ffmpeg) ok=1 ;;
      esac
    fi
  done

  local lib qtver
  if [[ -r /usr/lib/qt6/libexec/qformatinfo ]]; then
    lib="(qt6 libexec)"
  else
    lib=""
  fi
  if qtver="$(qmake6 -query QT_VERSION 2>/dev/null)"; then
    printf "$format_line" "qt6-version" "${qtver}${lib}"
  else
    printf "$format_line" "qt6-version" "unknown"
  fi

  if rustver="$(rustc --version 2>/dev/null)"; then
    printf "$format_line" "rust" "${rustver}"
  fi

  if [[ -S /run/user/$(id -u)/bus ]]; then
    printf "$format_line" "session-bus" "present"
  else
    printf "$format_line" "session-bus" "MISSING (notifications will be inert)"
    ok=1
  fi

  local own
  if own="$(busctl --user list 2>/dev/null | awk '$1 == "org.freedesktop.Notifications" { for (i = 3; i <= NF; i++) { if ($i != "" && $i !~ ":") { print $i; next } } }' | head -1)"; then
    [[ -n "$own" ]] && printf "$format_line" "notif-daemon" "$own" || printf "$format_line" "notif-daemon" "none"
  else
    printf "$format_line" "notif-daemon" "busctl unable to query"
  fi

  if compgen -G "$HOME/.config/selene/init.lua" > /dev/null 2>&1; then
    printf "$format_line" "init.lua" "loaded"
  else
    printf "$format_line" "init.lua" "missing (using defaults)"
  fi

  if [[ -d "$HOME/.local/share/selene/wallpapers" ]]; then
    local count
    count=$(find "$HOME/.local/share/selene/wallpapers" -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.mp4' -o -iname '*.webm' -o -iname '*.mkv' -o -iname '*.mov' \) 2>/dev/null | wc -l)
    printf "$format_line" "wallpapers" "${count} files"
  else
    printf "$format_line" "wallpapers" "(no ~/.local/share/selene/wallpapers)"
  fi

  if [[ $ok -eq 0 ]]; then
    printf "\n[doctor] green light.\n"
  else
    printf "\n[doctor] issues found -- resolve the MISSING items above.\n"
    exit 1
  fi
}

cmd_install_hyprland() {
  local lua_conf="$HOME/.config/hypr/hyprland.lua"
  local old_conf="${HYPRLAND_CONFIG:-$HOME/.config/hypr/hyprland.conf}"
  mkdir -p "$(dirname "$lua_conf")" "$SELENE_SHARE"

  # Auto-detect: if hyprland.lua already exists (Hyprland 0.40+),
  # generate a .lua snippet; otherwise fall back to the legacy
  # source= line in hyprland.conf.
  local use_lua=false
  if [[ -f "$lua_conf" ]]; then
    use_lua=true
    local selene_lua="$SELENE_SHARE/hyprland.lua"
    local marker="-- selene-shell --"
    local require_line="require(\"selene.hyprland\")"

    if [[ -f "$selene_lua" ]]; then
      echo "Already installed: $selene_lua exists."
      return 0
    fi

    mkdir -p "$(dirname "$selene_lua")"
    cat > "$selene_lua" <<'LUAEOF'
-- Generated by 'selene install hyprland'. Edit the overrides block
-- if you need to change settings shipped by Selene.

-- Launch Selene on login.
exec_once = function()
    return hyprctl("dispatch", "exec", selene_bin())
end

-- Layer rules so the shell windows render with compositor-side blur.
layerrule = blur, namespace:selene-shell
layerrule = ignorealpha 0.4, namespace:selene-shell

-- OVERRIDES -----------------------------------------------------------
-- Put your own bindings or rules below this line.
LUAEOF

    # Inject the actual binary path
    sed -i "s|selene_bin()|'$SELENE_BIN'|" "$selene_lua"

    echo "$marker" >> "$lua_conf"
    echo "$require_line" >> "$lua_conf"
    echo "$marker" >> "$lua_conf"

    echo "Installed: appended $require_line to $lua_conf"
    echo "Generated: $selene_lua"
  else
    # Legacy hyprland.conf path
    local conf="$old_conf"
    local marker="# -- selene-shell --"
    local source_line="source = $SELENE_SHARE/hyprland.conf"

    if [[ -f "$conf" ]] && grep -qF "$source_line" "$conf"; then
      echo "Already installed: $source_line present in $conf"
      return 0
    fi

    cat > "$SELENE_SHARE/hyprland.conf" <<EOF
# Generated by 'selene install hyprland'. Edit the user overrides block
# if you need to change settings shipped by Selene.

# exec-once launches Selene on login.
exec-once = $SELENE_BIN

# Default appearance keybinds (Ambxst / NothingLess standard). Each
# bind calls `selene --send ...` which is intercepted by the running
# shell instance (or launched directly if no instance is alive).
# Hyprland consumes the keypress before any focused client sees it.
\$mainMod = SUPER
bind = \$mainMod,         space, exec, $SELENE_BIN --send show launcher
bind = \$mainMod,         D, exec, $SELENE_BIN --send show dashboard
bind = \$mainMod,         A, exec, $SELENE_BIN --send show settings
bind = \$mainMod,         V, exec, $SELENE_BIN --send show clipboard
bind = \$mainMod,         period, exec, $SELENE_BIN --send show picker
bind = \$mainMod,         N, exec, $SELENE_BIN --send show notes
bind = \$mainMod,         T, exec, $SELENE_BIN --send show todo
bind = \$mainMod,         Return, exec, $SELENE_BIN --send show terminal
bind = \$mainMod,         K, exec, $SELENE_BIN --send show binds
bind = \$mainMod,         grave, exec, $SELENE_BIN --send show overview
bind = \$mainMod,         tab, exec, $SELENE_BIN --send show overview
bind = \$mainMod,         L, exec, $SELENE_BIN --send show lock
bind = \$mainMod,         escape, exec, $SELENE_BIN --send show powermenu
bind = \$mainMod SHIFT,    C, exec, $SELENE_BIN --send show settings
bind = \$mainMod SHIFT,    V, exec, $SELENE_BIN --send show clipboard
bind = \$mainMod SHIFT,    B, exec, $SELENE_BIN --send cycle-profile
bind = \$mainMod SHIFT,    N, exec, $SELENE_BIN --send dnd
bind = \$mainMod SHIFT,    P, exec, $SELENE_BIN --send caffeine
bind = \$mainMod SHIFT,    R, exec, $SELENE_BIN --send reload
bind = \$mainMod SHIFT,    escape, exec, $SELENE_BIN --send quit
bind = \$mainMod,          Pause, exec, $SELENE_BIN --send caffeine
bind = Ctrl Alt,         Left, exec, $SELENE_BIN --send wp-prev
bind = Ctrl Alt,         Right, exec, $SELENE_BIN --send wp-next

# Layer rules for compositor-side blur.
layerrule = blur, namespace:selene-shell
layerrule = ignorealpha 0.4, namespace:selene-shell

# OVERRIDES -----------------------------------------------------------
EOF

    {
      echo
      echo "$marker"
      echo "$source_line"
      echo "$marker"
    } >> "$conf"

    echo "Installed: appended $source_line to $conf"
    echo "Generated: $SELENE_SHARE/hyprland.conf"
  fi
}

cmd_remove_hyprland() {
  local lua_conf="$HOME/.config/hypr/hyprland.lua"
  local old_conf="${HYPRLAND_CONFIG:-$HOME/.config/hypr/hyprland.conf}"

  # Remove Lua integration
  if [[ -f "$lua_conf" ]]; then
    local require_line='require("selene.hyprland")'
    local marker="-- selene-shell --"
    if grep -qF "$require_line" "$lua_conf"; then
      python3 - "$lua_conf" "$require_line" "$marker" <<'PYEOF'
import sys, pathlib, re
path = pathlib.Path(sys.argv[1])
needle = sys.argv[2]
marker = sys.argv[3]
text = path.read_text()
pattern = re.compile(rf"{re.escape(marker)}\n{re.escape(needle)}\n{re.escape(marker)}\n?")
path.write_text(pattern.sub("", text))
PYEOF
      echo "Removed: $require_line from $lua_conf"
    fi
    rm -f "$SELENE_SHARE/hyprland.lua"
  fi

  # Remove legacy .conf integration
  if [[ -f "$old_conf" ]]; then
    local source_line="source = $SELENE_SHARE/hyprland.conf"
    if grep -qF "$source_line" "$old_conf"; then
      python3 - "$old_conf" "$source_line" <<'PYEOF'
import sys, pathlib, re
path = pathlib.Path(sys.argv[1])
needle = sys.argv[2]
text = path.read_text()
pattern = re.compile(rf"\n# -- selene-shell --\n{re.escape(needle)}\n# -- selene-shell --\n")
path.write_text(pattern.sub("\n", text))
PYEOF
      echo "Removed: $source_line from $old_conf"
    fi
    rm -f "$SELENE_SHARE/hyprland.conf"
  fi

  echo "Selene Hyprland integration removed."
}

cmd="${1:-run}"
shift || true

case "$cmd" in
  wp-prev)        selene_send "wp-prev" ;;
  wp-next)        selene_send "wp-next" ;;
  run|"")         cmd_run "${1:-}" ;;
  reload)         cmd_reload ;;
  quit)           cmd_quit ;;
  lock)           cmd_lock ;;
  suspend)        cmd_suspend ;;
  record)         cmd_record "${1:-screen}" ;;
  nightlight)     cmd_run nightlight ;;
  dnd)            cmd_run dnd ;;
  caffeine)       cmd_run caffeine ;;
  notes)          cmd_run notes ;;
  todo)           cmd_run todo ;;
  update)         cmd_update ;;
  status)         cmd_status ;;
  doctor)         cmd_doctor ;;
  profile)        cmd_profile "${1:-}" ;;
  brightness)     cmd_brightness "${1:-}" ;;
  screenshot)     cmd_screenshot "${1:-screen}" ;;
  install)
    sub="${1:-}"; shift || true
    case "$sub" in
      hyprland)   cmd_install_hyprland ;;
      "")         echo "usage: selene install hyprland" >&2; exit 1 ;;
      *)          echo "unknown install target: $sub" >&2; exit 1 ;;
    esac
    ;;
  remove)
    sub="${1:-}"; shift || true
    case "$sub" in
      hyprland)   cmd_remove_hyprland ;;
      "")         echo "usage: selene remove hyprland" >&2; exit 1 ;;
      *)          echo "unknown remove target: $sub" >&2; exit 1 ;;
    esac
    ;;
  help|-h|--help) usage ;;
  *)              usage; exit 1 ;;
esac
