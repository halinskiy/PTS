# PTS — Architecture

Pet in The System (PTS) is a macOS desktop-pet application written in Swift using AppKit. The executable runs as an accessory-policy app (no Dock icon, no menu bar activation) and overlays a transparent, borderless `NSWindow` on top of everything on the primary display.

---

## Module Breakdown

The source tree under `Sources/PTS/` is divided into four groups:

```
Sources/PTS/
├── App/          — Entry point, NSApplicationDelegate, game-loop coordination
│   ├── main.swift
│   ├── AppController.swift                (root class + all property declarations)
│   ├── AppController+Core.swift           (bounds helpers, apple targeting, mouse interactivity toggle)
│   ├── AppController+Movement.swift       (walk, jump, climb, look direction, visuals)
│   ├── AppController+Updates.swift        (60fps update() entry point, visual helpers)
│   ├── AppController+Apples.swift         (apple spawning, physics, collision, eating)
│   ├── AppController+Accessibility.swift  (status bar, accessibility flow, auto-update)
│   └── AboutWindowController.swift
│
├── Core/         — Pure-logic model layer, no UI dependencies
│   ├── MascotEntity.swift        (all per-mascot mutable state)
│   ├── StateMachine.swift        (generic protocol-based FSM)
│   ├── MascotStates.swift        (concrete state objects + StateKey constants)
│   ├── MoodSystem.swift          (Tamagotchi-style needs + SystemContext)
│   ├── WindowTracker.swift       (AXObserver real-time window geometry tracking)
│   ├── SystemMonitor.swift       (typing speed, CPU, screenshot detection, app-switch)
│   ├── ParticleSystem.swift      (particle emitters + lightweight physics)
│   ├── InputHandler.swift        (legacy global mouse monitor; instantiated but not active at runtime)
│   └── FaceExpression.swift      (expression enum + ExpressionRenderer pixel-art drawing)
│
├── Views/        — NSView subclasses, pure drawing, no logic
│   ├── ClaudeView.swift              (mascot sprite renderer)
│   ├── ShadowView.swift              (elliptical drop shadow)
│   ├── AppleView.swift               (cached pixel-art apple, supports rotation)
│   ├── ParticleView.swift            (per-particle NSView renderer)
│   └── InteractiveContentView.swift  (full-screen clear NSView; mouse event entry point)
│
└── Support/      — Shared data, constants, utilities
    ├── AppConstants.swift    (SCALE, pixel-art grids, apple color table)
    ├── Models.swift          (CrabLevel, JumpPhase, ApplePhase, AppleState)
    ├── DockInfo.swift        (Dock bounds via AXUIElement)
    ├── WindowInfo.swift      (active window bounds via AXUIElement, one-shot helper)
    ├── MascotTheme.swift     (hue-shift color system, UserDefaults persistence)
    ├── AppMetadata.swift     (bundle version helpers)
    ├── AppVersion.swift      (semver string parsing and Comparable)
    └── AppResources.swift    (SPM resource-bundle locator)
```

---

## Key Objects and Their Roles

| Object | Role |
|---|---|
| `AppController` | Central coordinator. `NSApplicationDelegate`. Owns all subsystems and drives the 60fps `update()` loop via a `Timer`. All concrete state objects hold a `weak var controller: AppController?`. |
| `MascotEntity` | Plain-Swift model containing the mascot's complete mutable state: position, velocity, jump phase, drag offsets, expression, sleep flags, apple-seeking state, sprite dimensions, and physics constants. No UI references. |
| `MascotStateMachine` | Generic FSM backed by a `[String: MascotStateProtocol]` dictionary. `transition()` respects `canBeInterrupted`. `forceTransition()` always succeeds. |
| `MoodSystem` | Tamagotchi-style needs engine (energy, happiness, hunger, curiosity). Consumes a `SystemContext` snapshot every 0.5 s and derives `overallMood`. |
| `WindowTracker` | Owns one `AXObserver` per frontmost app window. Fires three closures: `onWindowMoved`, `onWindowResized`, `onWindowChanged`. |
| `SystemMonitor` | Global keyboard event monitor (key rate), CPU usage via Mach `host_processor_info`, screenshot detection via distributed notification. |
| `ParticleSystem` | Pool of `Particle` value-type structs each backed by a `ParticleView` subview. Manages lifetime, physics, and removal. |
| `ClaudeView` | Pixel-art sprite renderer. Properties are written by the game loop every frame; it calls `needsDisplay = true` to schedule a redraw. |
| `InteractiveContentView` | Full-screen clear `NSView` inside the overlay window. Receives `mouseDown/Dragged/Up` events only when the game loop enables them via `window.ignoresMouseEvents = false`. |

---

## Initialization Sequence

```
main.swift
  NSApplication.shared.setActivationPolicy(.accessory)   // no Dock icon
  AppController(debugEnabled:)
    setupStateMachine()       — registers IdleState, WalkingState, SleepingState,
                                WakingUpState, DraggedState, ThrownState
    setupSystemCallbacks()    — wires closures on WindowTracker and SystemMonitor
  NSApplication.run()
    └─ applicationDidFinishLaunching
         setupStatusItemIfNeeded()        — creates NSStatusItem with full menu
         setupAutomaticUpdateChecks()     — background GitHub check after 3 s delay
         beginLaunchFlow()
           if AXIsProcessTrusted()
             completeLaunch()             — create NSWindow + view hierarchy + Timer
             activateAccessibilityFeaturesIfNeeded()
               refreshDockBounds()        — read true Dock geometry via AXUIElement
               windowTracker.startTracking()
               systemMonitor.startMonitoring()
           else
             deactivateAccessibilityFeatures()
             startAccessibilityPolling()  — 0.5 s Timer polls AXIsProcessTrusted()
             completeLaunch()             — app is usable (reduced) without accessibility
             presentAccessibilityPrePromptIfNeeded()
```

`completeLaunch()` is guarded with `guard window == nil` so it runs exactly once regardless of how many times `beginLaunchFlow()` is called (it is also called from `applicationDidBecomeActive`).

`activateAccessibilityFeaturesIfNeeded()` is guarded by `accessibilityFeaturesActive` so the observer and monitors are registered only once even if the accessibility poll fires repeatedly.

---

## Window Configuration

The overlay window is created once in `completeLaunch()`:

```swift
window = NSWindow(contentRect: screenFrame, styleMask: .borderless, ...)
window.isOpaque = false
window.backgroundColor = .clear
window.level = .statusBar              // floats above normal app windows
window.ignoresMouseEvents = true       // default; toggled per-frame dynamically
window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
window.hasShadow = false
```

View hierarchy inside the window:

```
NSWindow.contentView  →  InteractiveContentView (full screen, clear)
    ├── ShadowView              (positioned below the mascot's floor level)
    ├── ClaudeView              (positioned at current mascot coordinates)
    ├── AppleView × 0..N        (added/removed dynamically)
    └── ParticleView × 0..N     (added/removed dynamically)
```

---

## 60 fps Update Loop

A `Timer` with interval `1.0/60.0` added to `RunLoop.main` in `.common` mode drives everything. Entry point: `AppController.update()` in `AppController+Updates.swift`.

```
update()
  dt = now - lastTime

  updateApples(dt)                  — apple physics, floor transitions, eating
  particleSystem.update(dt)         — particle lifetime, position, removal
  updateMouseInteractivity()        — toggle window.ignoresMouseEvents based on cursor proximity
  expressionAnimPhase += dt * speed — cycling phase for animated eye shapes
  mascot.updateExpression(dt)       — blend transitions, expire timed expressions

  every 2.0 s → refreshDockBounds()          — re-read Dock geometry; detects dock auto-hide reveal
                                               (if dock floor jumps from <10 to ≥20 pt and mascot
                                               is standing in dock X range → forceTransition(.thrown))
  every 0.5 s → windowTracker.pollUpdate()   — fallback polling for window changes

  early-return if dock obscured (window.alphaValue = 0, no movement needed)

  every 0.5 s → build SystemContext → moodSystem.update(dt, context)
    → apply walkSpeedMultiplier → mascot.walkSpeed
    → apply preferredExpression if no timed expression active

  sleep-Z particle every 1.5 s when isAsleep

  apply windowInertiaVelocity (decay factor 0.85 per frame × dt)

  ── PRIORITY BRANCHES (each returns early) ──────────────────────────
  if mascot.isDragged || mascot.isThrown
      stateMachine.update(dt, mascot) → positionSprite() → return

  if jumpPhase != .none
      updateJump(dt) → updateVisuals() → positionSprite() → return

  if recoveryTimer > 0
      tick recovery; on expiry: handle seekActiveWindow → return

  if isAsleep
      updateVisuals() → positionSprite() → return

  if wakingUp
      updateVisuals() → positionSprite() → return
  ─────────────────────────────────────────────────────────────────────

  updateAutonomousMode(now)
    threshold = autonomousIdleThreshold (default 300 s, configurable, -1 = disabled)
    if not autonomous and lastUserActivityTime + threshold elapsed → enterAutonomousMode()
    walking phase (60 s): keeps lastActivityTime fresh; pickAutonomousWalkTarget() picks
                          from screenLeft…screenRight — navigation code handles level jumps
    sleeping phase (120 s): lets lastActivityTime expire → normal sleep visuals
    after 120 s → restart walking phase (wake up if sleeping)

  mouse-settle logic → compute autoTargetX
    apple-seek mode: autoTargetX = currentAppleSeekTargetX()
    normal mode:     autoTargetX set after settleDelay (0.52 s) of mouse stillness

  walk toward autoTargetX:
    check dock-exit jump, dock-entry jump, window jump, window climb
    move mascot.x, set facingRight, isWalking

  updateLookDirection(dt)
  updateVisuals(dt, isWalking)
  hover intensity ramp (hoverIntensity 0→1, curious expression after 0.8 s)
  squeeze animation (isSqueezing visual squish)
  window-stickiness clamp (if level == .window)
  positionSprite()
```

Processing priority is strictly: thrown/dragged > jumping > recovery > asleep > waking > normal navigation.

---

## State Machine

### Registered States

| Key | Class | `canBeInterrupted` | Purpose |
|---|---|---|---|
| `idle` | `IdleState` | true | Standing still; drowsy/sleep transition; waits for `autoTargetX` |
| `walking` | `WalkingState` | true | Moving toward `autoTargetX`; returns to idle when target reached |
| `sleeping` | `SleepingState` | true | Fully asleep, eyes/sit locked to 1; particles emitted externally |
| `wakingUp` | `WakingUpState` | true | Animates `eyeClose` and `sitAmount` back to 0 |
| `dragged` | `DraggedState` | **false** | User is holding mascot; velocity history accumulates each frame |
| `thrown` | `ThrownState` | **false** | Free-flight with gravity (−1800), air resistance, and bounce |

Note: `jumping`, `climbing`, and `seekingApple` keys are defined in `StateKey` but their behavior is driven inline via `jumpPhase` and `isSeekingApples` rather than through state-machine objects.

### Transition Map

```
idle          ──── autoTargetX set ──────────────────> walking
idle          ──── idleTime > sleepDelay ────────────> sleeping
walking       ──── target reached / cleared ─────────> idle
sleeping      ──── mouse click / window move ────────> wakingUp  (via isAsleep=false, wakingUp=true)
wakingUp      ──── sitAmount < 0.05 ─────────────────> idle
any           ──── mouseDown + drag threshold ───────> dragged   (forceTransition)
dragged       ──── mouseUp ──────────────────────────> thrown    (forceTransition)
thrown        ──── floor settle (speed < 50) ────────> idle      (forceTransition, level set)
thrown        ──── lands on window ──────────────────> idle      (forceTransition, level = .window)
thrown        ──── lands on dock top ────────────────> idle      (forceTransition, level = .dock)
any           ──── window disappears (alt-tab/close) > thrown    (forceTransition, seekActiveWindow=true)
any (on win.) ──── window moves > 80 px ────────────> thrown    (forceTransition, detach)
any (on win.) ──── window moves down fast ───────────> thrown    (forceTransition, bounce off)
```

`forceTransition` bypasses `canBeInterrupted`, used for physics events that must preempt the drag/throw states.

---

## How Accessibility, WindowTracker, and SystemMonitor Connect

### Accessibility Permission Gate

`AXIsProcessTrusted()` is polled by a 0.5 s `Timer`. Until permission is granted:

- Status bar icon shows `ptsicon_warn`
- Accessibility menu item is visible and points to System Preferences
- Dock alignment uses fallback geometry (screen-center estimate)

Once granted, `activateAccessibilityFeaturesIfNeeded()` fires exactly once:

```swift
accessibilityFeaturesActive = true
refreshDockBounds()            // read true Dock bounds via AXUIElement
windowTracker.startTracking()  // set up AXObserver for frontmost window
systemMonitor.startMonitoring() // keyboard, CPU, screenshot monitors
```

### WindowTracker Data Flow

```
WindowTracker
  NSWorkspace.didActivateApplicationNotification
      → updateTrackedWindow()
          AXUIElementCreateApplication(pid)
          AXUIElementCopyAttributeValue(kAXFocusedWindowAttribute)
          setupObserver(window, pid)
              AXObserverAddNotification(kAXMovedNotification)
              AXObserverAddNotification(kAXResizedNotification)
              CFRunLoopAddSource(CFRunLoopGetMain(), ...)

  AX callback fires on main queue
      → handleWindowChange() → readWindowFrame() → updateFrame()
          computes delta (dx, dy) and velocity
          if origin changed:  fires onWindowMoved(frame, delta)
          if size changed:    fires onWindowResized(frame)

  pollUpdate() every 0.5 s (fallback / app-switch recovery)
      if trackedWindow nil: updateTrackedWindow()
      else: updateFrame() → may fire onWindowChanged(frame?)

AppController callbacks:
  onWindowMoved  → if level == .window: ride along; detach if displacement > 80 px;
                   bounce if delta.dy < -25; apply horizontal inertia if |delta.dx| > 10
  onWindowResized → clamp X; update Y to new floor; wobble expression
  onWindowChanged → if window gone: forceTransition(.thrown), seekActiveWindow = true
                    if different window: forceTransition(.thrown), seekActiveWindow = true
```

Coordinate conversion note: AX reports positions in Core Graphics coordinates (Y=0 at top). `readWindowFrame()` converts to Cocoa coordinates with `cocoaY = screen.frame.height - point.y - sz.height`.

### SystemMonitor Data Flow

```
SystemMonitor
  NSEvent.addGlobalMonitorForEvents(.keyDown)
      keyTimestamps rolling-window (2 s)
      typingSpeed = count / 2.0  (keys per second)
      fires onTypingSpeedChanged(speed)
          if speed > 5 → mascot.setExpression(.excited, 2.0)

  Timer 3 s → host_processor_info(PROCESSOR_CPU_LOAD_INFO)
      cpuUsage = (user + system) / total across all cores
      fires onCPUChanged(cpu)
          if cpu > 0.8 and cooldown > 5 s → .scared + sweat particle

  DistributedNotificationCenter "com.apple.screencapture.didFinish"
      screenshotDetected = true; resets after 3 s
      fires onScreenshot()
          → mascot.setExpression(.happy, 3.0) + star particle

  NSWorkspace.didActivateApplicationNotification
      fires onAppSwitch(localizedName)  (registered but unused by current callbacks)
```

`SystemContext` is assembled in `update()` every 0.5 s from `systemMonitor` properties and passed to `moodSystem.update(dt:context:)`.
