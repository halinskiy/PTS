# PTS — Pet in The System

A pixel-art desktop pet for macOS that lives in your interface — walks on the active window, climbs its sides, sits on edges with dangling legs, reacts to notifications, and explores autonomously.

## Install

### Download DMG
1. Download **PTS.dmg** from [Releases](https://github.com/halinskiy/PTS/releases/latest)
2. Open the DMG and drag **PTS.app** to **Applications**
3. If macOS blocks the app, open Terminal and run:
   ```
   xattr -cr /Applications/PTS.app
   ```

## Features

### Movement & Physics
- Walks along screen edges, dock, and window tops
- Climbs up and down the active window's sides
- Sits on window edges with legs dangling
- Drag & throw with heavy physics (gravity, air resistance, bounce)
- Falls off when you move a window
- Screen wrapping on ground (walks off one edge, appears on the other)
- Smooth walk deceleration

### Autonomous Behavior
- After 10s of no major mouse movement, starts exploring
- Walks between ground, dock, and the active window
- Phantom apples guide navigation to different surfaces
- 50% chance to leave current window each cycle
- Walks 5 min, sleeps 1 min, repeats
- Idle micro-animations: yawns, stretches, hops, looks around

### Reactions
- **Notifications**: jumps/falls scared when any macOS notification appears
- **Apps**: excited for Xcode/VS Code, happy for Slack/Discord, thinking for browsers
- **Cursor**: flinches on fast flyby, approaches idle cursor to sniff
- **Time of day**: energetic mornings, sleepy nights
- **Claude Code**: detects running Claude, shows thinking expressions

### Pet System
- 11 expressions, 8 mood states, 7 particle effects
- Progression: trust level, days alive, apples eaten
- Orange default tint with 9 color presets
- Feed apples with Option+F

## Build

```sh
swift build -c release
bash build-app.sh
```

## Tech Stack
Swift, AppKit, CoreGraphics, QuartzCore, Accessibility API

## License
MIT
