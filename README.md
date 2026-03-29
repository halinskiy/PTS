# PTS — Pet in The System

A pixel-art desktop pet for macOS that lives in your interface — walks on windows, climbs their sides, sits on edges with dangling legs, reacts to notifications, apps, and cursor, and explores autonomously.

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
- Jumps between adjacent windows in the same Space
- Drag & throw with heavy physics (gravity, air resistance, bounce)
- Lands on any visible window when thrown
- Falls off when you move a window — won't re-land for 1.5s
- Screen wrapping on ground (walks off one edge, appears on the other)
- Smooth walk deceleration (easing at endpoints)
- Leaves tiny footprints that fade after 3 seconds

### Autonomous Behavior
- After 1 min idle (no mouse >60px), explores the interface
- Targets windows in current Space only (top 3 z-order)
- Phantom apples: invisible lures spawn to guide navigation
- 50% chance to leave current window per target
- Walks 5 min, sleeps 1 min, repeats
- Idle micro-animations: looks around, yawns, stretches, hops, taps foot
- Animation variety depends on mood (tired → yawns, ecstatic → hops)

### Reactions & Intelligence
- **Notifications**: jumps/falls scared when any macOS notification appears
- **Apps**: excited for Xcode/VS Code, happy for Slack/Discord, thinking for browsers
- **Body language**: "types" for code editors, sways for music, watches browsers
- **Cursor**: flinches on fast flyby, approaches to "sniff" idle cursor
- **Time of day**: energetic mornings, sleepy nights
- **Battery/Dark mode**: reacts to low power and theme changes
- **Claude Code**: detects running Claude, shows thinking expressions
- **Window z-order**: hides behind foreground windows, sleeps on background windows

### Pet System
- 11 expressions, 8 mood states, 7 particle effects
- Progression: tracks days alive, interactions, apples eaten, trust level (0-100)
- Orange default tint with 9 color presets
- Feed apples with Option+F
- Self-replication (rare, max 3 instances)

### Rendering
- CADisplayLink (macOS 14+) / Timer fallback
- Pixel-art with real-time scale, rotation, expression blending

## Build

```sh
swift build -c release
bash build-app.sh
```

## Tech Stack
Swift, AppKit, CoreGraphics, QuartzCore, Accessibility API

## License
MIT
