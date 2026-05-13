# DMS-mpvpaper plugin

A DankMaterialShell plugin for [mpvpaper](https://github.com/GhostNaN/mpvpaper).

![dms-mpvpaper Screenshot](screenshot.png)

## Prerequisites
- ffmpeg (for matugen support)
- [mpvpaper](https://github.com/GhostNaN/mpvpaper)
- Working DMS install

## Installation

### Install via plugin store
Install the plugin from DMS plugin registry. Make sure `show 3rd party` is set to on when searching.

### Manual Installation
For latest head:
```bash
# Copy plugin to DMS plugins directory (create it if it doesn't exist)
cp -r dms-mpvpaper ~/.config/DankMaterialShell/plugins/

# Enable in DMS settings under Plugins tab.
```

## Usage

After enabling the plugin, **you must add the mpvpaper widget to a bar** for the wallpaper to start. DMS only instantiates widget-type plugins when they are placed in a bar, so without this step nothing will happen (no `mpvpaper` process will spawn) even after selecting a video.

To add the widget: open DMS settings → Dank Bar → add **mpvpaper Video Wallpaper** to one of the widget slots (left/center/right). Then configure your video via the widget's popout or the plugin's settings page.

## Acknowledgements
 - Inspiration: [dms-wallpaperengine](https://github.com/sgtaziz/dms-wallpaperengine)
 - The wonderful [DankMaterialShell](https://danklinux.com/)
