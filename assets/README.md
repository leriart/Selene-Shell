# assets

These get bundled into the `selene-shell` binary via `qrc` at
`qrc:/qt/qml/io/github/selene/shell/assets/`.

| File | Purpose |
|---|---|
| `logo-dark.png` | Selene silhouette on transparent background. Used by the Bar and the README `<picture>` tag in light mode. |
| `logo-white.png` | Same silhouette, white. Used in dark mode. |
| `screenshot-shell.png` | The default `selene-shell --screenshot` capture. Re-render with `bash scripts/cli.sh capture`. |
| `panel-launcher.png` | Launcher overlay open. |
| `panel-notif.png` | Notification panel. |
| `panel-walls.png` | Wallpaper picker. |
| `panel-settings.png` | Settings panel. |
| `panel-audio.png` | Audio quick settings. |
| `panel-net.png` | Network quick settings. |
| `panel-bt.png` | Bluetooth quick settings. |

To regenerate every panel:

```bash
for p in launcher notif walls settings audio net bt; do
  QT_QPA_PLATFORM=offscreen build/selene-shell \
      --screenshot "assets/panel-$p.png" --show $p --delay 4000 --size 720x480
done
```
