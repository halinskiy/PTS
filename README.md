# PTS — Pet in The System

A pixel-art desktop pet for macOS that lives on your screen — walks on windows, climbs their sides, sits on edges, reacts to apps, follows your cursor, and explores the interface on its own.

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

### Movement & Physics
- Walks along screen edges, dock, and window tops
- Climbs up and down window sides, hangs on walls
- Sits on window edges with legs dangling
- Jumps between adjacent windows (window-to-window hopping)
- Drag & throw with heavy physics (gravity, air resistance, bounce)
- Lands on any visible window when thrown
- Smooth deceleration at walk endpoints (easing, no snap)
- Leaves tiny footprints that fade after 3 seconds

### Autonomous Behavior
- After configurable idle time (default 5 min), explores the whole interface
- Smart target selection: 40% windows, 20% dock, 15% window edges, 25% ground
- Climbs window sides (30% chance instead of jumping off)
- Sleeps 2 min, walks 1 min, repeats until you interact
- Idle micro-animations: looks around, yawns, stretches, hops in place, taps foot, sits down
- Animation variety depends on mood (tired = yawns, ecstatic = hops)

### Reactions & Intelligence
- Reacts to specific apps: excited for Xcode/VS Code, happy for Slack/Discord, thinking for browsers
- App body language: "types" when code editor is open, sways to music, watches browser
- Reacts to mouse hover, clicks, and holds
- Fast cursor flyby = surprised flinch; idle cursor nearby = approaches to sniff
- Scoot away if you hover over it for 2+ seconds
- Time-of-day awareness: energetic mornings, sleepy nights
- Battery: sad when low power mode; dark mode switch: surprised
- Claude Code integration: detects running Claude process, shows thinking/coding expressions

### Pet System
- 11 expressions (happy, surprised, scared, dizzy, love, thinking, etc.)
- 8 mood states (ecstatic, happy, content, curious, tired, exhausted, hungry, sad)
- Mood influenced by CPU usage, typing speed, time of day, and interactions
- 7 particle effects (dust, sleep Z, hearts, sparks, stars, sweat, footprints)
- Progression system: tracks days alive, interactions, apples eaten, trust level
- Trust level (0-100) affects how the pet behaves toward you
- Color tint presets from the menu bar
- Feed apples with a hotkey (Option+F)
- Self-replication: rare 3% chance to spawn a clone (max 3 instances)

### Rendering
- CADisplayLink (macOS 14+) for butter-smooth animation synced to display refresh
- Timer fallback for macOS 12-13
- Pixel-art rendering with real-time scale, rotation, and expression blending

## Build

```sh
swift build -c release
bash build-app.sh
open /Applications/PTS.app
```

## Tech Stack
Swift, AppKit, CoreGraphics, QuartzCore (CADisplayLink), Accessibility API (AXObserver)

## License
MIT
