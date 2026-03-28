# PTS Architecture

## Core Loop
`AppController+Movement.swift` → `update()` at display refresh rate (CADisplayLink on macOS 14+, Timer fallback).

## State Machine
`StateMachine` + `MascotStateProtocol` with states:
- **IdleState** — micro-animations (look, yawn, stretch, hop, tap, sit), edge sitting, drowsy→sleep transition
- **WalkingState** — moves to `autoTargetX` with deceleration easing
- **SleepingState** — Z particles, full sit/eye close
- **WakingUpState** — gradual eye/body recovery
- **DraggedState** — follows cursor, velocity-based expressions, stretch/squash
- **ThrownState** — physics (gravity -2600, air resistance, bounce), multi-window landing
- **WallClimbState** — climbs/hangs on window sides, transitions to idle or falls

## Entity Model
`MascotEntity` — position, velocity, level (.ground/.dock/.window), jump phase, expressions, mood state, trust, edge sitting, wall climb state.

## Subsystems
- **MoodSystem** — 4 needs (energy, happiness, curiosity, hunger) → 8 mood states → walk speed, expressions, animation variety. Time-of-day integration.
- **ProgressionSystem** — lifetime stats (days, interactions, apples, throws, distance), trust level (0-100) gating behaviors.
- **SystemMonitor** — typing speed, CPU, screenshots, app switching, battery, dark mode, Claude Code process detection.
- **ParticleSystem** — 7 types: dust, sleepZ, heart, spark, star, sweat, footprint.
- **WindowTracker** — AXObserver real-time tracking of frontmost window. Separate `petWindowFrame` for physical pet position.
- **InputHandler** — global mouse monitors for drag/throw/click/petting.

## Window Model
- `activeWindowFrame` = frontmost window (WindowTracker, for climbing decisions)
- `petWindowFrame` = window pet is physically on (for stickiness, riding)
- `visibleWindowFrames` = all windows (CGWindowListCopyWindowInfo, 5fps refresh)

## Rendering
`ClaudeView` — pixel grid (10x7 body + 2-3 row legs), properties: scaleX/Y, rotation, eyeClose, sitAmount, legFrame, bodyBob, armsRaised, expression, blushAmount.

## Key Files
```
Sources/PTS/
├── App/
│   ├── AppController.swift              — properties, state machine setup, system callbacks
│   ├── AppController+Movement.swift     — main update loop, walking, jumping, visuals
│   ├── AppController+Autonomous.swift   — autonomous roaming, breeding
│   ├── AppController+Core.swift         — dock/window bounds, debug, helpers
│   ├── AppController+Accessibility.swift — launch flow, window creation, CADisplayLink
│   └── AppController+Apples.swift       — apple feeding system
├── Core/
│   ├── MascotStates.swift       — all state implementations + idle micro-animations
│   ├── MascotEntity.swift       — pet data model
│   ├── StateMachine.swift       — generic FSM
│   ├── MoodSystem.swift         — tamagotchi needs + time-of-day
│   ├── ProgressionSystem.swift  — stats, trust level
│   ├── SystemMonitor.swift      — typing, CPU, apps, battery, dark mode, Claude
│   ├── ParticleSystem.swift     — particle emitter
│   ├── WindowTracker.swift      — AXObserver window tracking
│   └── FaceExpression.swift     — 11 expressions, 10 eye shapes
├── Views/
│   ├── ClaudeView.swift         — pixel-art renderer
│   ├── ParticleView.swift       — particle renderer
│   └── ShadowView.swift         — drop shadow
└── Support/
    ├── AppConstants.swift        — grid data, colors, leg poses
    ├── WindowInfo.swift          — CGWindowList helpers
    └── Models.swift              — CrabLevel, JumpPhase, AppleState
```
