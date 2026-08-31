# assets

These get bundled into the `selene-shell` binary via `qrc` at
`qrc:/qt/qml/io/github/selene/shell/assets/`.

| File | Purpose |
|---|---|
| `logo-dark.png` | Selene crescent, trimmed to content, on a transparent background. Used by the Bar and the README `<picture>` tag in light mode. |
| `logo-white.png` | Same silhouette in white, used in dark mode. |

Screenshots live here too and are taken by hand:

```bash
QT_QPA_PLATFORM=offscreen build/selene-shell \
    --screenshot assets/screenshot-shell.png --delay 4000 --size 1280x720

for p in launcher dashboard overview powermenu notes todo walls settings audio net bt sidebar; do
  QT_QPA_PLATFORM=offscreen build/selene-shell \
      --screenshot "assets/panel-$p.png" --show $p --delay 4000 --size 1100x700
done
```

Add `--preset full-moon` (or any Tokens preset) and `--anim-profile bouncy`
to any capture to showcase a theme.
