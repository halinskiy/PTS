# PTS — Pet in The System

A pixel-art desktop pet for macOS that lives in your interface — walks on windows, climbs their sides, sits on edges with dangling legs, reacts to apps, explores autonomously, and sleeps on background windows until you need it.

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
- Screen wrapping on ground (walks off one edge, appears on the other)
- Smooth walk deceleration (easing at endpoints)
- Leaves tiny footprints that fade after 3 seconds
- Respects window z-order (hides behind foreground windows)
- Falls off when you move a window too fast

### Autonomous Behavior
- After configurable idle time (default 5 min), explores the entire interface
- Smart target selection: windows, dock, ground, window edges — weighted random
- Phantom apples: invisible lures spawn on different surfaces to guide navigation
- 50% chance to leave current window per target (doesn't get stuck on one surface)
- Won't climb windows near the menubar (top 80px excluded)
- Sleeps on background windows — escapes to ground if hidden for >60 seconds
- Walks 5 min, sleeps 1 min, repeats until you interact
- Idle micro-animations: looks around, yawns, stretches, hops in place, taps foot
- Animation variety depends on mood (tired → yawns, ecstatic → hops)

### Reactions & Intelligence
- Reacts to specific apps: excited for Xcode/VS Code, happy for Slack/Discord, thinking for browsers
- App body language: "types" when code editor is open, sways to music, watches browser
- Reacts to mouse hover, clicks, and holds
- Fast cursor flyby → surprised flinch; idle cursor nearby → approaches to sniff
- Scoots away if you hover over it for 2+ seconds
- Time-of-day awareness: energetic mornings, sleepy nights
- Battery: sad when low power mode; dark mode switch: surprised
- Claude Code integration: detects running Claude, shows thinking/coding expressions

### Pet System
- 11 expressions (happy, surprised, scared, dizzy, love, thinking, etc.)
- 8 mood states (ecstatic → sad), influenced by CPU, typing, time of day
- 7 particle effects (dust, sleep Z, hearts, sparks, stars, sweat, footprints)
- Progression system: tracks days alive, interactions, apples eaten, trust level
- Trust level (0-100) affects how the pet behaves toward you
- Orange default tint with 9 color presets from the menu bar
- Feed apples with Option+F hotkey
- Self-replication: rare chance to spawn a clone (max 3 instances)

### Rendering
- CADisplayLink (macOS 14+) for display-synced animation
- Timer fallback for macOS 12-13
- Pixel-art rendering with real-time scale, rotation, and expression blending

## Build

```sh
swift build -c release
bash build-app.sh
```

## Tech Stack
Swift, AppKit, CoreGraphics, QuartzCore, Accessibility API (AXObserver)

## License
MIT
