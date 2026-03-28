# PTS — Physics and Movement

This document describes every aspect of the mascot's physical behavior: how it walks, jumps, climbs, gets thrown, chases apples, and interacts with the screen boundaries, Dock, and active windows.

---

## Coordinate Space

All positions, velocities, and floor levels are in Cocoa window-local points (Y points upward). The overlay window spans the full primary screen, so window-local coordinates equal screen coordinates in both X and Y.

The mascot's logical position `(mascot.x, mascot.y)` is the center-bottom of the sprite — feet level, horizontally centered.

---

## Floor Levels and CrabLevel Enum

Three vertical surfaces the mascot can stand on:

```swift
enum CrabLevel {
    case dock     // top surface of the macOS Dock
    case ground   // bottom edge of the screen (y ≈ 0)
    case window   // top border of the frontmost app window
}
```

Floor Y values (set in `completeLaunch()` and `refreshDockBounds()`):

```swift
let feetOffset: CGFloat = 2 * SCALE   // 6 pt — visual foot clearance below sprite origin

groundFloorY = -feetOffset            // ≈ -6 pt (just below screen bottom edge)
dockFloorY   = dock.height - feetOffset
windowFloorY = windowFrame.maxY - feetOffset   // top of window border
```

The negative `groundFloorY` means the mascot's sprite origin sits slightly below the visible screen edge, giving the feet a grounded appearance.

---

## Screen and Dock Boundaries

Horizontal limits for walking (clamped in movement code):

```swift
let halfBody: CGFloat = 5 * SCALE    // 15 pt

// Ground level
screenLeft  = screenFrame.origin.x + halfBody + 10
screenRight = screenFrame.origin.x + screenFrame.width - halfBody - 10

// Dock level
dockLeft  = dock.x + halfBody
dockRight = dock.x + dock.width - halfBody
```

On dock level the mascot is constrained to `dockLeft…dockRight`. On ground level it spans the full screen width minus margins. On window level it clamps to `windowFrame.minX + 2 … windowFrame.maxX + 2`.

---

## Walk System

Walking is driven by `autoTargetX` — an optional X coordinate the mascot moves toward. When set, the game loop applies velocity each frame:

```swift
let dx = autoTargetX - mascot.x
let dir: CGFloat = dx > 0 ? 1 : -1
let activeWalkSpeed = isSeekingApples ? mascot.walkSpeed * 1.6 : mascot.walkSpeed
let nextX = mascot.x + dir * min(activeWalkSpeed * dt, abs(dx))
mascot.x = nextX
claudeView.facingRight = dir > 0
```

When `abs(dx) <= autoThresh` (15 pt), the mascot snaps to the target and clears `autoTargetX`. The threshold prevents micro-oscillation from floating-point imprecision.

### Walk Speed

Base speed: 200 pt/s. Modified by the mood system:

| Mood | Speed |
|---|---|
| Ecstatic | 260 pt/s |
| Happy | 220 pt/s |
| Content | 200 pt/s |
| Curious | 230 pt/s |
| Tired | 140 pt/s |
| Exhausted | 100 pt/s |
| Hungry | 180 pt/s |
| Sad | 160 pt/s |

Apple-seek bonus: +60% on top of mood-adjusted speed.

### autoTargetX Sources

1. **Mouse follow (normal mode):** After the mouse is still for `settleDelay = 0.52 s`, `autoTargetX` is set to the mouse X clamped to `screenLeft…screenRight`, if the distance exceeds `autoThresh * 2` (30 pt).
2. **Apple seek mode:** `currentAppleSeekTargetX()` returns the target X to approach the nearest apple, accounting for level transitions.
3. **Window seek after fall:** `seekActiveWindow` causes a walk to the nearest edge of `activeWindowFrame` after recovery.

---

## Jump System

Jumps are driven by `jumpPhase` and a set of timing constants:

```swift
let squishDur: CGFloat = 0.07     // 70 ms pre-launch squash
let airDur:    CGFloat = 0.28     // 280 ms airborne
let landDur:   CGFloat = 0.08     // 80 ms landing squash
let jumpArcHeight:           CGFloat = 60    // px peak height above lerp baseline
let jumpHorizontalDistance:  CGFloat = 180   // px traveled horizontally per jump
```

### Jump Arc Formula

During the `.airborne` phase the Y position follows a parabolic arc overlaid on a linear interpolation between start and end Y:

```swift
let t = min(1, jumpTimer / airDur)     // 0 → 1 over 280 ms
let linearY = jumpStartY + (jumpEndY - jumpStartY) * t
let arc     = 4 * jumpArcHeight * t * (1 - t)  // parabola: 0 at t=0 and t=1, peak at t=0.5
crabY = linearY + arc
```

At `t = 0.5` the arc term reaches its maximum: `4 * 60 * 0.5 * 0.5 = 60 pt` above the linear baseline. For a level jump (`jumpStartY == jumpEndY`) the peak height is 60 pt above the floor.

X motion during flight:

```swift
crabX += jumpDirection * (currentJumpHorizontalDistance / airDur) * dt
crabX = max(screenLeft, min(screenRight, crabX))
```

This is constant-velocity horizontal movement, clamped to screen bounds.

### Jump Phases and Visual States

| Phase | Duration | Body Scale | Legs | Arms |
|---|---|---|---|---|
| `.squish` (pre-launch) | 70 ms | scaleX 1→1.18, scaleY 1→0.82 | `legsSquish` | down |
| `.airborne` first half (rising) | 0–140 ms | scaleX 0.88, scaleY 1.18 | `legsRising` | raised |
| `.airborne` second half (falling) | 140–280 ms | scaleX 0.92, scaleY 1.10 | `legsFalling` | down |
| `.land` impact (0–42%) | 33 ms | scaleX 1+0.22t, scaleY 1−0.24t | `legsLand` | down |
| `.land` recovery (42–78%) | 29 ms | scaleX recovering, scaleY recovering | `legsLandRecover` | down |
| `.land` final (78–100%) | 18 ms | scaleX ≈1, scaleY ≈1 | `legsIdle` or `legsWalk` | down |

The landing uses `smoothstep()` — a cubic ease — for both the impact and recovery sub-phases:

```swift
let impactT   = smoothstep(min(1, landT / 0.42))
let recoveryT = smoothstep(max(0, (landT - 0.42) / 0.58))
scaleX = 1 + 0.22 * impactT - 0.10 * recoveryT
scaleY = 1 - 0.24 * impactT + 0.10 * recoveryT
```

On completing `.land`, `particleSystem.emitDust(at:count:4)` fires.

### Level Transitions via Jumps

| Scenario | Jump Type | `jumpStartY` | `jumpEndY` | Level after landing |
|---|---|---|---|---|
| Dock → ground (exit) | `startJump(down: true, direction:)` | `dockFloorY` | `groundFloorY` | `.ground` |
| Ground → dock (entry) | `startJump(down: false, direction:)` | `groundFloorY` | `dockFloorY` | `.dock` |
| Any → window (near window) | `startJumpToWindow(frame:direction:)` | current `crabY` | `windowFloorY` | `.window` |
| Window → ground/dock | `startJump(down: true, direction:)` | `windowFloorY` | `groundFloorY` | `.ground` |
| Apple hop (same level) | `startHop(direction:)` | `crabY` | `crabY` | unchanged |
| In-place jump | `startInPlaceJump()` | `crabY` | `crabY` | unchanged; `horizontalDistance = 0` |

After landing the `level` is set based on which `jumpEndY` was reached:

```swift
if jumpEndY == dockFloorY         { level = .dock }
else if jumpEndY == windowFloorY  { level = .window }
else                              { level = .ground }
```

---

## Window Climbing

When `autoTargetX` points to an X inside the frontmost window frame and the mascot is at ground or dock level, a side-climb is initiated instead of a jump if the mascot is within 25 pt of the window's left or right edge:

```swift
startClimbing(onLeft: nearLeft)
```

During `.climbing` phase:
- `crabX` is locked to `frame.minX` or `frame.maxX`.
- `crabY` increases at `climbSpeed = 400 pt/s`.
- The sprite is rotated 90°: `rotation = onLeft ? -π/2 : π/2`.
- Leg animation cycles at 0.08 s with `legsIdle`/`legsWalk`.
- `armsRaised = true`.

When `crabY >= jumpEndY` (the window's top floor), climbing ends: `level = .window`, rotation resets to 0, expression `.happy` fires.

---

## Throw Physics

### Drag Velocity Recording

While the mascot is held (`isDragged = true`), `InteractiveContentView.mouseDragged()` calls:

```swift
mascot.recordDragPosition(screenPoint, at: now)
```

`MascotEntity` keeps the last 5 `(point, time)` samples. `computeThrowVelocity()` uses the most recent 3:

```swift
let dx = last.point.x - first.point.x
let dy = last.point.y - first.point.y
return CGVector(dx: dx / CGFloat(dt), dy: dy / CGFloat(dt))
```

### ThrownState Physics

When the user releases the mascot, `ThrownState.enter()` computes velocity and `ThrownState.update()` applies physics each frame:

```swift
// Air resistance (Shimeji-style)
mascot.velocityX -= mascot.velocityX * 0.04       // 4% drag per frame
mascot.velocityY += (gravity - mascot.velocityY * 0.08) * dt  // gravity −1800, 8% Y drag

mascot.x += mascot.velocityX * dt
mascot.y += mascot.velocityY * dt
```

Constants:

```swift
let gravity:        CGFloat = -1800  // pt/s²
let airResistanceX: CGFloat = 0.04   // fraction per frame (approximately, not per-second)
let airResistanceY: CGFloat = 0.08
let bounceDamping:  CGFloat = 0.5    // energy retained on floor bounce
let frictionX:      CGFloat = 0.98   // applied to X on floor contact (unused in this implementation)
```

### Throw Velocity Scaling

```swift
if speed > 150 {
    mascot.velocityX = vel.dx * 1.2   // fast throw: amplified 1.2×
    mascot.velocityY = vel.dy * 1.2
    moodSystem.onThrown()
} else {
    mascot.velocityX = vel.dx * 0.3   // gentle drop: damped 0.3×
    mascot.velocityY = max(vel.dy * 0.3, -50)
}
```

### Floor Bounce

On contact with a floor:

```swift
let impactSpeed = abs(mascot.velocityY)
if impactSpeed < 50 && abs(mascot.velocityX) < 30 {
    // settled — transition to idle
} else {
    mascot.velocityY = abs(mascot.velocityY) * bounceDamping   // 0.5 restitution
    mascot.velocityX *= 0.85
    emitDust(count: 3)
}
```

Impact squish proportional to speed:

```swift
let impactStrength = min(1, impactSpeed / 800)
scaleX = 1 + 0.25 * impactStrength
scaleY = 1 - 0.20 * impactStrength
```

### Screen Edge Bounce

```swift
if mascot.x < screenLeft {
    mascot.x = screenLeft
    mascot.velocityX = abs(mascot.velocityX) * 0.5
} else if mascot.x > screenRight {
    mascot.x = screenRight
    mascot.velocityX = -abs(mascot.velocityX) * 0.5
}
```

### Window-Top Landing While Thrown

```swift
if onWindowX && mascot.y <= winFloor + 5 && mascot.y > winFloor - 20 {
    if abs(mascot.velocityY) < 120 && abs(mascot.velocityX) < 60 {
        // Land on window
        mascot.level = .window
        forceTransition(.idle)
    } else {
        // Bounce off window top
        mascot.velocityY = abs(mascot.velocityY) * bounceDamping * 0.6
    }
}
```

### Drag Visual Effects

`DraggedState.update()` applies visual distortion based on current drag velocity:

```swift
let stretchFactor = min(0.15, speed / 5000)
let moveAngle = atan2(vel.dy, vel.dx)
scaleX = 1 + stretchFactor * abs(sin(moveAngle))
scaleY = 1 - stretchFactor * abs(cos(moveAngle)) * 0.5
tilt = max(-0.3, min(0.3, vel.dx / 2000))
rotation → tilt (smoothed)
```

Expression during drag:

```
speed > 800 → .dizzy
speed > 400 → .scared
speed > 150 → .surprised
otherwise   → .thinking
```

---

## Window Inertia

When the active window moves horizontally by more than 10 pt in a single frame, the mascot receives an opposing impulse that makes it slide slightly in the opposite direction:

```swift
if abs(delta.dx) > 10 {
    windowInertiaVelocity.dx = -delta.dx * 0.25
}
// Each frame:
crabX += windowInertiaVelocity.dx * dt
windowInertiaVelocity.dx *= windowInertiaDecay  // 0.85 per second × dt
```

The decay factor of 0.85 per-frame (at 60fps, applied as `velocity *= 0.85` each frame) causes the inertia to fade out in roughly 0.5–1 s.

---

## Auto-Target System

`autoTargetX` is computed differently in normal mode vs. apple-seek mode:

### Normal Mode (Mouse Follow)

```
pendingTargetX tracks the last seen mouse X.
if mouse moves > 2 pt: reset settleTimer
if settleTimer > settleDelay (0.52 s):
    mouseSettled = true
    if |mouseX - crabX| > 30 pt:
        autoTargetX = clamp(mouseX, screenLeft, screenRight)

if mouse moves > 80 pt while target is set:
    autoTargetX = nil   (target abandoned, mouse too erratic)
```

### Apple Seek Mode

Activated when any apple first bounces (`bounceCount == 1`). The mascot starts approaching the nearest apple after `appleSeekDelay` (1.0–2.0 s random).

`currentAppleSeekTargetX()` returns the X to walk toward, accounting for level differences:

```
if apple is on the same level: return apple.x
if apple is on a different level:
    compute cost of approaching via dockLeft vs. dockRight
    return the cheaper dock edge ± 2 pt (to trigger the jump)
```

Once locked to a target apple (by `appleSeekTargetID = ObjectIdentifier(apple.view)`), the mascot stays locked until the apple is eaten or no longer accessible, then re-evaluates.

---

## Apple Hop Triggers (Seek Mode)

When locking onto a new apple target, 0–3 hop trigger distances are generated:

```swift
let hopCount = Int.random(in: 0...3)
let distance = abs(apple.x - crabX)
if hopCount > 0 && distance >= 70 {
    appleSeekHopTriggers = (0..<hopCount)
        .map { _ in CGFloat.random(in: 35...max(40, distance - 20)) }
        .sorted(by: >)  // descending: check largest remaining distance first
}
```

Each frame while seeking, if the remaining distance to the apple drops below the next trigger value and the hop geometry is valid, `startHop(direction:)` fires:

```swift
func shouldStartAppleHop(remainingDistance:, direction:) -> Bool {
    guard remainingDistance > autoThresh * 2 else { return false }
    guard remainingDistance <= nextTrigger else { return false }
    guard canLandHop(on: level, direction: direction) else { return false }
    guard !isAppleHopTooCloseToDockEdge(direction: direction) else { return false }
    appleSeekHopTriggers.removeFirst()
    return true
}
```

This gives the mascot a natural, lively approach with spontaneous hops rather than a straight walk.

---

## Apple Physics

### Spawn

Each apple spawns at the top of the screen at a random X that avoids the mascot:

```swift
apple.velocityX = fallDirection * random(120...180)   // horizontal drift
apple.velocityY = 0                                    // starts stationary
apple.rotationSpeed = random(3...7) * ±1
apple.floorY = (onDock ? dockFloorY : groundFloorY) - APPLE_PADDING
```

### Falling Physics

```
velocityY += appleGravity * dt    // gravity = -1200 pt/s²
x         += velocityX * dt
y         += velocityY * dt
rotation  += rotationSpeed * dt
```

### Bouncing

On hitting `floorY`:

```
bounceCount 1: velocityY *= 0.35, velocityX *= 0.72, rotationSpeed *= 0.5 → phase = .bounce
bounceCount 2: (same)
bounceCount ≥ 3: velocityY = 0, velocityX *= 0.42, rotationSpeed *= 0.35 → phase = .resting
```

At first bounce (`bounceCount == 1`), if not already seeking, `beginAppleSeek()` is called.

### Resting Drag

In `.resting` phase, the apple slides to a stop:

```
velocityX *= (1 - 4.8 * dt)     // slide friction
rotationSpeed *= (1 - 6.5 * dt) // spin friction
snap to 0 when < 6 pt/s or < 0.2 rad/s
```

After both reach 0, a settle-wobble plays (0.22 s, `sin(wobbleT * π) * (1 - wobbleT) * 0.045` rad amplitude).

### Wall Bounce

```
if x < appleHalf:
    x = appleHalf
    velocityX = abs(velocityX) * 0.78
    rotationSpeed *= -0.7
```

### Dock Barrier

Apples below dock height that would slide under the Dock are deflected to the nearest horizontal edge (`dockLeft - appleHalf` or `dockRight + appleHalf`) with a velocity flip and rotation impact.

### Apple-Mascot Collision

Two regions are checked separately:

**Head hit** (apple falling from above):

```
Conditions: jumpPhase == .none, velocityY < -20, not resting, cooldown <= 0
Horizontal: ≥ 12% overlap between apple radius and head rect
Vertical: apple bottom crossed through head top this frame
```

Reaction: mascot jumps/hops in opposite direction, `currentJumpHorizontalDistance *= 2` (double-length panic hop), expression `.surprised`.

**Body contact** (apple overlapping the lower body):

```
Condition: crabBodyRect.intersects(appleRect) AND same level
```

The apple is removed, `moodSystem.onAppleEaten()` fires, expression `.happy` for 1 s.

### Apple-Apple Collision

Resolved via a spatial hash (bucket width = `appleSize * 0.70`). Each frame, neighboring buckets are compared for overlap:

```
if |dx| < contactDistance AND |dy| < rowTolerance:
    overlap = contactDistance - distance
    push each apple apart by overlap * 0.5 * 0.82
    if closing speed < -4:
        impulse = (1 + 0.58) * closingSpeed * 0.5  // restitution 0.58
        apply to velocities
        apply tangential spin impulse
```

---

## Recovery Pause

After the mascot falls off a window (alt-tab, window close), it enters a `recoveryTimer = 1.2 s` daze:

- Expression: `.dizzy` for 1.2 s.
- No movement during recovery.
- After recovery: if `seekActiveWindow` is set, `autoTargetX` is set to the nearest edge of `activeWindowFrame`.
