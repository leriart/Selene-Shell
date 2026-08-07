#!/usr/bin/env bash
# Selene command-line entry point.
#
# Invoked as `selene <subcommand>`. Resolves the repo from this script's location
# so it works whether invoked from the source tree or from ~/.local/bin/selene.

set -euo pipefail

if [[ -z "${SELENE_SRC:-}" ]]; then
  SCRIPT_PATH="$(realpath -e "$0" 2>/dev/null || python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$0")"
  SELENE_SRC="$(dirname "$SCRIPT_PATH")"
fi
SELENE_BUILD="${SELENE_BUILD:-$SELENE_SRC/build}"
SELENE_SHARE="${SELENE_SHARE:-$HOME/.local/share/selene}"
SELENE_BIN="$SELENE_BUILD/selene-shell"

usage() {
  cat <<EOF
selene <command> [args]

Commands:
  run                 Launch the shell (default if no command is given).
  reload              Reload the running shell instance.
  quit                Stop the running shell instance.
  update              Pull, rebuild, and re-stage.
  status              Show install paths and binary state.
  doctor              Diagnose the environment Selene runs against.
  install hyprland    Add the Selene source line to ~/.config/hypr/hyprland.conf.
  remove  hyprland    Remove the Selene source line.

Environment:
  SELENE_SRC    Source tree (default: derived from this script's path).
  SELENE_BUILD  Build directory (default: \$SELENE_SRC/build).
  SELENE_SHARE  Generated config/state directory (default: \$HOME/.local/share/selene).
EOF
}

cmd_run() {
  if [[ ! -x "$SELENE_BIN" ]]; then
    echo "selene-shell not found at $SELENE_BIN" >&2
    echo "Run: selene update   (or curl|sh the installer again)" >&2
    exit 1
  fi
  exec "$SELENE_BIN"
}

cmd_reload() {
  if pkill -USR1 -x selene-shell; then
    echo "reload signal sent"
  else
    echo "no running selene-shell instance" >&2
    exit 1
  fi
}

cmd_quit() {
  if pkill -x selene-shell; then
    echo "selene-shell stopped"
  else
    echo "no running selene-shell instance" >&2
    exit 1
  fi
}

cmd_update() {
  cd "$SELENE_SRC"
  git pull --ff-only
  cargo generate-lockfile --manifest-path rust/Cargo.toml || true
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

  local bins=("qmake6" "ffmpeg" "playerctl" "busctl" "hyprctl")
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
  local conf="${HYPRLAND_CONFIG:-$HOME/.config/hypr/hyprland.conf}"
  mkdir -p "$(dirname "$conf")" "$SELENE_SHARE"
  local marker="# -- selene-shell --"
  local source_line="source = $SELENE_SHARE/hyprland.conf"

  if [[ -f "$conf" ]] && grep -qF "$source_line" "$conf"; then
    echo "Already installed: $source_line present in $conf"
    return 0
  fi

  cat > "$SELENE_SHARE/hyprland.conf" <<EOF
# Generated by 'selene install hyprland'. Edit the user overrides block if you
# need to change settings shipped by Selene; removing this file reverts the
# integration.

# exec-once launches Selene and its companion daemons on login.
exec-once = $SELENE_SRC/build/selene-shell

# Default appearance keybinds (binding style mirrors Ambxst defaults).
\$mainMod = SUPER

bind = \$mainMod, return, exec, $SELENE_SRC/build/selene-shell --reload
bind = \$mainMod SHIFT, escape, exec, $SELENE_SRC/build/selene-shell --quit

# OVERRIDES
# Anything you want to override from Selene's settings should go below this
# line.
EOF

  {
    echo
    echo "$marker"
    echo "$source_line"
    echo "$marker"
  } >> "$conf"

  echo "Installed: appended $source_line to $conf"
  echo "Generated: $SELENE_SHARE/hyprland.conf"
}

cmd_remove_hyprland() {
  local conf="${HYPRLAND_CONFIG:-$HOME/.config/hypr/hyprland.conf}"
  local source_line="source = $SELENE_SHARE/hyprland.conf"

  if [[ ! -f "$conf" ]]; then
    echo "No Hyprland config at $conf; nothing to remove."
    return 0
  fi

  if ! grep -qF "$source_line" "$conf"; then
    echo "Source line not present in $conf; nothing to do."
    return 0
  fi

  python3 - "$conf" "$source_line" <<'PYEOF'
import sys, pathlib, re
path = pathlib.Path(sys.argv[1])
needle = sys.argv[2]
text = path.read_text()
pattern = re.compile(rf"\n# -- selene-shell --\n{re.escape(needle)}\n# -- selene-shell --\n")
path.write_text(pattern.sub("\n", text))
PYEOF

  rm -f "$SELENE_SHARE/hyprland.conf"

  echo "Removed: $source_line from $conf"
}

cmd="${1:-run}"
shift || true

case "$cmd" in
  run|"")         cmd_run ;;
  reload)         cmd_reload ;;
  quit)           cmd_quit ;;
  update)         cmd_update ;;
  status)         cmd_status ;;
  doctor)         cmd_doctor ;;
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
