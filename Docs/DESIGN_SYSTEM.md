# PTS — Design System

This document describes how the mascot and all visual elements are drawn: pixel grids, scale factors, the color/theme system, animation frame data, coordinate conventions, shadow rendering, and the particle effects system.

---

## Pixel Art Rendering Philosophy

All drawing is done in `CGContext` with antialiasing explicitly disabled (`ctx.setShouldAntialias(false)`). Every visual element is a grid of colored rectangles scaled up by a uniform integer scale factor (`SCALE = 3`). This produces crisp, pixel-perfect art at any Retina density.

No bitmap image assets are loaded for the mascot itself. The body, legs, and eyes are drawn procedurally from the grid constants in `AppConstants.swift` every frame.

---

## Scale Factor

```swift
// AppConstants.swift
let SCALE: CGFloat = 3
```

One logical grid cell = 3×3 screen points. On a 2x Retina display this becomes 6×6 physical pixels.

All sprite dimensions are derived from this constant:

| Measurement | Formula | Value |
|---|---|---|
| Grid cell size | `SCALE` | 3 pt |
| Sprite width | `30 * SCALE` | 90 pt |
| Sprite height | `18 * SCALE` | 54 pt |
| Apple pixel size | `APPLE_SCALE = 1.5` pt | 1.5 pt |
| Apple total size | `appleGrid.count * APPLE_SCALE + APPLE_PADDING * 2` | 32.5 pt |
| Shadow view height | `6 * SCALE + SHADOW_FLOOR_MARGIN` | `18 + 24 = 42` pt |

---

## Body Grid

The mascot body is a 10-column × 7-row pixel grid defined in `AppConstants.swift`. Each cell is either empty (`0`), body color (`1`), or screen color (`2`).

```
bodyGrid[0] = [0,1,1,1,1,1,1,1,1,0]  — Top row (rounded corners)
bodyGrid[1] = [1,1,1,1,1,1,1,1,1,1]  — Side walls
bodyGrid[2] = [1,1,2,2,2,2,2,2,1,1]  — Screen area (cols 2–7)
bodyGrid[3] = [1,1,2,2,2,2,2,2,1,1]  — Screen area
bodyGrid[4] = [1,1,2,2,2,2,2,2,1,1]  — Screen area
bodyGrid[5] = [1,1,1,1,1,1,1,1,1,1]  — Bottom body
bodyGrid[6] = [0,1,1,1,1,1,1,1,1,0]  — Bottom row (rounded corners)
```

The screen area spans rows 2–4 and columns 2–7 (a 6×3 cell window). Eyes and expressions are drawn within this region.

Rendering in `ClaudeView.draw()`:

```swift
for rowIndex in 0..<bodyGrid.count {
    for col in 0..<bodyGrid[rowIndex].count {
        let val = bodyGrid[rowIndex][col]
        // val 1 → bodyColor, val 2 → screenColor
        let rect = px(CGFloat(col), oy + CGFloat(bodyGrid.count - 1 - rowIndex) * s + bb + legYBob)
        ctx.fill(rect)
    }
}
```

Row indices are inverted (`bodyGrid.count - 1 - rowIndex`) because Cocoa Y-axis points upward while the grid is written top-to-bottom.

---

## Coordinate System

### Cocoa vs Core Graphics Y-Axis

| System | Y origin | Direction |
|---|---|---|
| Cocoa / AppKit (`NSRect`, `NSView.frame`) | Bottom-left of screen | Upward ↑ |
| Core Graphics / AX API | Top-left of screen | Downward ↓ |

The game uses Cocoa coordinates exclusively for mascot position, floor levels, window frames, and apple positions. The `WindowTracker` and `WindowInfo` both explicitly convert AX positions:

```swift
let cocoaY = screen.frame.height - point.y - sz.height
```

### Mascot Position vs. Sprite Origin

`mascot.x` and `mascot.y` are the mascot's logical center-bottom coordinates in window space:

```swift
// positionSprite()
claudeView.frame.origin.x = crabX - spriteW / 2   // center horizontally
claudeView.frame.origin.y = crabY                   // y = feet level
```

`crabY` equals the floor level the mascot stands on (ground, dock, or window top).

### Floor Levels

| Level | `crabY` formula |
|---|---|
| Ground | `groundFloorY = -feetOffset` where `feetOffset = 2 * SCALE` |
| Dock | `dockFloorY = dock.height - feetOffset` |
| Window top | `windowFloorY = frame.maxY - feetOffset` |

The −`feetOffset` accounts for the 2-pixel leg grid below the body, placing the visual feet exactly on the floor surface.

---

## Color System

### Base Palette

Defined in `AppConstants.swift` as static `NSColor` values:

| Role | R | G | B |
|---|---|---|---|
| Body | 0.20 | 0.45 | 0.85 |
| Screen | 0.45 | 0.90 | 1.00 |
| Shadow | 0.15 | 0.35 | 0.70 |
| Eye | 0.08 | 0.08 | 0.08 |

### MascotTheme — Hue Shifting

`MascotTheme.shared` applies a hue rotation to all three base colors at once. The shift is persisted in `UserDefaults` under key `"mascotHueShift"`.

```swift
// NSColor extension
func hueRotated(by degrees: CGFloat) -> NSColor {
    var h, s, b, a: CGFloat
    rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
    let newHue = (h + degrees / 360).truncatingRemainder(dividingBy: 1)
    return NSColor(hue: newHue < 0 ? newHue + 1 : newHue, saturation: s, brightness: b, alpha: a)
}
```

### Preset Table

| Name | Hue Shift |
|---|---|
| Blue (Default) | 0° |
| Purple | −40° |
| Pink | −80° |
| Red | −120° |
| Orange | −155° |
| Yellow | −185° |
| Green | +120° |
| Teal | +60° |
| Monochrome | sentinel 1000 (special-cased: white 0.35/0.75/0.25) |

Active colors are exposed as computed globals in `AppConstants.swift`:

```swift
var bodyColor: NSColor { MascotTheme.shared.bodyColor }
var screenColor: NSColor { MascotTheme.shared.screenColor }
var shadowColor: NSColor { MascotTheme.shared.shadowColor }
```

---

## Leg Frame Grids

Seven leg configurations are defined as 10-column arrays. Each `1` cell is rendered at `bodyColor`.

| Constant | Rows | Description |
|---|---|---|
| `legsIdle` | 2 | Straight down, columns 1 and 8 |
| `legsWalk` | 2 | Spread out, columns 0 and 9 (alternating with idle) |
| `legsSquish` | 2 | Wide spread + one empty row (squat) |
| `legsRising` | 2 | Tucked inward, columns 2 and 7 (jump ascent) |
| `legsFalling` | 2 | Same as idle but used for descent visual distinction |
| `legsLand` | 2 | Same as walk — splat on landing impact |
| `legsLandRecover` | 2 | Mixed: row 0 = walk, row 1 = idle (bounce recovery) |

Walk animation alternates between `legsIdle` and `legsWalk` frames on a 0.15 s cycle. The settle animation runs at 0.20 s.

### Walk Shadow

When `isWalking` and scale is 1 (no deformation), a single-pixel offset line is drawn in `shadowColor` on the body's leading-edge column, `shadowOffset = -walkFacing * SCALE` pixels horizontally. This gives the illusion of motion blur / contact shadow.

---

## Face Expression System

Defined in `Core/FaceExpression.swift`. Eleven expressions, each specifying an `EyeStyle`:

| Expression | Left Eye | Right Eye | `eyeCloseOverride` | `animationSpeed` |
|---|---|---|---|---|
| `neutral` | normal | normal | nil | 1.0 |
| `happy` | happy (^) | happy (^) | nil | 1.0 |
| `excited` | star (*) | star (*) | 0 (force open) | 2.0 |
| `surprised` | wide (O) | wide (O) | 0 | 1.0 |
| `sleepy` | squint (-) | squint (-) | 0.7 | 0.5 |
| `sad` | dot | dot | nil | 0.7 |
| `scared` | xEye (X) | xEye (X) | 0 | 3.0 |
| `love` | heart | heart | 0 | 1.2 |
| `dizzy` | spiral (@) | spiral (@) | 0 | 2.0 |
| `thinking` | normal | dot | nil | 0.8 |
| `blush` | happy (^) | happy (^) | nil | 1.0 |

`eyeCloseOverride`: when set, overrides the sleep/drowsy `eyeClose` float. `0` forces eyes fully open regardless of sleep state. `nil` lets the sleep animation blend normally.

### Eye Rendering

Eyes are drawn at pixel positions `(col=3, eyeRow)` and `(col=6, eyeRow)` inside the sprite, where `eyeRow` is screen row 3 (index from top of `bodyGrid`). The pixel position is horizontally shifted by `eyeShift` to simulate look direction.

```swift
let eyeShift = round(max(-1, min(1, lookDir)) * maxEyeShift) * flip
// maxEyeShift = max(0, SCALE - 2)  →  at SCALE=3, maxEyeShift = 1 pt
```

The `ExpressionRenderer.drawEye(shape:at:size:in:animPhase:)` function handles all ten `EyeShape` variants. Animated shapes (`.star`, `.spiral`) use `animPhase` (a 0–1 cycling float) to pulse or wobble.

### Expression Blending

`MascotEntity` maintains a blend system:

```
setExpression(.happy, duration: 2.0)
    targetExpression = .happy
    expressionBlend  = 0          — start of transition
    expressionDuration = 2.0
    expressionTimer    = 0

updateExpression(dt):
    expressionBlend += dt * 6.0   — ~0.17 s transition
    if blend >= 1.0: currentExpression = targetExpression
    if expressionDuration > 0: expressionTimer += dt
        if expressionTimer >= duration: setExpression(.neutral)

effectiveExpression:
    blend >= 0.5 ? targetExpression : currentExpression
```

### Blush Overlay

When expression is `.blush` or `.love`, two half-height rectangles are drawn at screen columns 2 and 7 (lower screen corners) with color `(1.0, 0.4, 0.5, alpha: 0.3 * blushAmount)`.

---

## Sprite Transform

Before all drawing, the context is transformed around the pivot point (bottom-center of the sprite):

```swift
let pivotX = bounds.width / 2
let pivotY = oy - CGFloat(lowestLegRow + 1) * s   // foot level

ctx.translateBy(x: pivotX, y: pivotY)
ctx.rotate(by: rotation)
ctx.scaleBy(x: scaleX, y: scaleY)
ctx.translateBy(x: -pivotX, y: -pivotY)
```

`scaleX` and `scaleY` are used for squash-and-stretch (jump, land, drag, squeeze). `rotation` is used for idle sway (`sin(breatheTimer * 0.7) * 0.015`), drag tilt, and wall-climbing (±π/2).

---

## Shadow Rendering

`ShadowView` is a separate `NSView` positioned below the mascot at `currentShadowFloorY()`. It draws a single semi-transparent ellipse:

```swift
// ShadowView.draw()
let shadowWidth  = bounds.width * 0.55
let shadowHeight = 2 * SCALE
// color: (r:0.08, g:0.03, b:0.0, a:0.10)
ctx.fillEllipse(in: CGRect(x: shadowX, y: shadowY, width: shadowWidth, height: shadowHeight))
```

Shadow floor logic:

```swift
func currentShadowFloorY() -> CGFloat {
    if jumpPhase != .none { return min(jumpStartY, jumpEndY) }  // stays on takeoff floor
    if level == .window   { return windowFloorY }
    return level == .dock ? dockFloorY : groundFloorY
}
// Shadow frame origin.y = shadowFloorY - SHADOW_FLOOR_MARGIN (24 pt below floor)
```

During a jump the shadow stays on the source floor, creating depth. The `SHADOW_FLOOR_MARGIN` (24 pt) provides vertical room inside the `ShadowView` for the ellipse offset.

---

## Apple Sprite

`AppleView` uses a class-level cached `CGImage` built once at first access:

```swift
static let cachedImage: CGImage? = { ... }()
```

The image is rendered from `appleGrid` (15×15 cells) at `APPLE_SCALE = 1.5 pt` per cell, padded by `APPLE_PADDING = 5 pt` on all sides.

### Apple Color Table

| Index | Color | Usage |
|---|---|---|
| 1 | (0.05, 0.05, 0.06) near-black | Outline / stem shadow |
| 2 | (0.16, 0.67, 0.38) green | Leaf |
| 3 | (0.95, 0.02, 0.00) red | Apple body |
| 4 | (1.00, 1.00, 1.00) white | Highlight |
| 5 | (0.74, 0.02, 0.03) dark red | Shadow side |

`AppleView.draw()` applies a CGContext rotation transform around the image center before drawing the cached image, implementing spin physics cheaply without per-frame pixel redraw.

---

## Particle Effects System

`ParticleSystem` manages a pool of `Particle` value structs, each with an associated `ParticleView` subview.

### Particle Types

| Type | Trigger | Velocity | Lifetime | Visual |
|---|---|---|---|---|
| `dust` | Landing, bouncing | Fan upward (0.3–2.8 rad), 40–120 pt/s | 0.3–0.6 s | Gray-brown ellipse with friction |
| `sleepZ` | Every 1.5 s while asleep | Up 30–50 pt/s + lateral wave | 1.5 s | Blue-purple pixel "Z" that grows |
| `heart` | Petting (hold 0.5 s) | Up 60–100 pt/s + lateral wave | 1.2 s | Red pixel heart with pop-in animation |
| `spark` | Running fast (apple seek), random 1/8 chance | Against run direction, 80–160 pt/s | 0.2–0.4 s | Yellow square, gravity applied |
| `star` | Screenshot taken | Up 30–60 pt/s, gentle float | 0.8 s | Gold cross-star, sine fade in/out |
| `sweat` | CPU > 80% | Right +10, down −30 pt/s, then gravity | 0.8 s | Blue teardrop, linear fade |

### Particle Physics Per Type

```
dust:    velocityY += 50 * dt (slight upward resistance)
         velocityX *= (1 - 2*dt)
         velocityY *= (1 - 1.5*dt)

sleepZ:  velocityX = sin(life * 4) * 20  (sinusoidal drift)
         scale grows from 0.5 to 1.3 over lifetime

heart:   velocityX = sin(life * 3) * 15  (sinusoidal drift)
         scale pops in: 0 → 1 during first 30% of life

spark:   velocityY -= 100 * dt  (gravity)
         scale = life / maxLife  (linear shrink)

star:    velocityY *= (1 - dt)  (deceleration)
         scale = sin(lifeRatio * π)  (arc: small → full → small)

sweat:   velocityY -= 200 * dt  (gravity, teardrop fall)
         scale = lifeRatio  (linear fade)
```

### Alpha Fade

All particles share the same alpha formula:

```swift
let alpha = min(1, particle.life / (particle.maxLife * 0.3))
```

This means full opacity for the first 70% of life, then fading to 0 over the last 30%.

### Emitter Offsets

```
emitDust(at point, count: 4–6)   — exactly at landing point
emitSleepZ(at point)              — +0..±5 x, +20 y above mascot head
emitHeart(at point)               — ±10 x, +20 y above mascot head
emitSparks(at point, direction)   — at foot level, trailing behind
emitStar(at point)                — ±15 x, +10..+30 y above mascot head
emitSweat(at point)               — +15 x, +25 y (side of head)
```
