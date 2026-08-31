# Wallpapers

Drop your wallpapers here. Selene reads this folder as the default
wallpaper directory and the picker shows every image and video inside.

Supported formats:

- Images: png, jpg, jpeg, webp, bmp
- Animated: gif, apng
- Video: mp4, webm, mkv, mov, avi

Set `SELENE_WALLPAPER_DIR` to point at any other directory instead.
Videos decode with hardware acceleration when available and are
downscaled into `~/.cache/selene/video-cache` when needed.
