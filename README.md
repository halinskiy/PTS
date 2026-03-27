# PTS — Pet in The System

A pixel-art desktop pet for macOS that lives on your screen, walks on windows, reacts to your actions, and interacts with the system UI.

## Install

### Download DMG
1. Download **PTS.dmg** from [Releases](https://github.com/halinskiy/PTS/releases/latest)
2. Open the DMG and drag **PTS.app** to **Applications**
3. If macOS blocks the app, open Terminal and run:
   ```
   xattr -cr /Applications/PTS.app
   ```

### Required Permissions
- **Accessibility** — needed for window tracking (riding windows, climbing, reacting to window movement)

## Features
- Pixel-art pet that walks along screen edges, dock, and window borders
- Drag & throw with physics (gravity, air resistance, bounce)
- Climbs onto windows and rides them as you move/resize
- Falls off when you alt-tab or close a window, then walks to the new one
- Reacts to mouse hover, clicks, and holds
- Sleeps when idle, wakes up startled when disturbed
- Expressions system (happy, surprised, scared, dizzy, love, etc.)
- Color tint presets from the menu bar
- Feed apples with a hotkey (Option+F)
- Mood system influenced by CPU usage, typing speed, and interactions

## Build

```sh
swift build -c release
bash build-app.sh
open PTS.app
```

## Tech Stack
Swift, AppKit, CoreGraphics, Accessibility API (AXObserver)

## License
MIT
