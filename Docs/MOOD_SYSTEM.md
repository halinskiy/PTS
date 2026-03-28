# PTS — Mood System

The mood system gives the mascot a persistent personality that changes based on what the user is doing. It is modeled after a Tamagotchi: four floating-point stats (energy, happiness, hunger, curiosity) decay and grow continuously, a derived `Mood` enum is computed from thresholds, and the mood drives visible effects like walk speed and facial expression.

---

## Stats Overview

All stats are `Float` values in the range 0.0–1.0, stored in `MoodSystem`. Initial values are set at construction:

| Stat | Initial | Description |
|---|---|---|
| `energy` | 0.8 | How alert and active the mascot feels. Decays over time; restored by interactions and sleep. |
| `happiness` | 0.7 | Overall contentment. Recovers toward a 0.5 baseline slowly; boosted by food, petting, screenshots. |
| `hunger` | 0.0 | Grows over time; reduced by eating apples. High hunger causes `hungry` mood. |
| `curiosity` | 0.5 | Interest and attentiveness. Grows when user types; decays when idle. |

---

## Continuous Decay and Growth (per `update()` call)

`MoodSystem.update(dt:context:)` is called every 0.5 s from the game loop. `dt` is the elapsed time since the last call (nominally 0.5 s but could be longer).

### Energy

```
energy -= dt * 0.0008          // slow passive decay (~0.0004/s)
energy += recentInteractions * 0.05  // interactions immediately restore energy
```

At the `dt = 0.5 s` update rate, passive decay is ~0.0004 per second. Without any interaction, full energy drains to zero in approximately 2500 s (~42 minutes).

### Hunger

```
hunger += dt * 0.001           // grows continuously (~0.001/s at dt=0.5)
```

Hunger grows from 0 to 1 in approximately 1000 s (~17 minutes) without eating.

### Happiness

```
if applesEatenRecently > 0:
    happiness += applesEatenRecently * 0.15

if wasPetted:
    happiness += 0.1

if screenshotDetected:
    happiness += 0.2

if wasThrown:
    happiness -= 0.05

if isIdle:
    happiness -= dt * 0.0005   // very slow idle decay

// Natural recovery toward 0.5 baseline
happiness += (0.5 - happiness) * dt * 0.001
```

The baseline pull (`0.001 * dt`) means happiness always drifts back toward 0.5 over time whether high or low.

### Curiosity

```
if typingSpeed > 3:
    curiosity += dt * 0.01     // grows while user types
    energy    += dt * 0.002    // slight energy boost from typing activity

if isIdle:
    curiosity -= dt * 0.003    // decays faster than other stats when idle
```

---

## Event-Based Changes

Discrete events call methods directly on `MoodSystem`:

| Event | Method | Effect |
|---|---|---|
| Apple eaten | `onAppleEaten()` | `hunger -= 0.25`, `happiness += 0.1` |
| Petted (hold 0.5 s) | `onPetted()` | `happiness += 0.15`, `energy += 0.05` |
| Thrown | `onThrown()` | `happiness -= 0.05`, `energy += 0.1` (exciting!) |
| Woken up | `onWokenUp()` | `energy += 0.3`, `happiness -= 0.05` (slightly annoyed) |
| Slept | `onSlept(duration)` | `energy += min(duration, 30) / 30 * 0.5` (up to +0.5 for 30 s sleep) |

---

## Derived Mood Enum

`overallMood` is a computed property evaluated on every access from the current stat values. Conditions are checked in priority order:

```swift
var overallMood: Mood {
    if energy < 0.15           { return .exhausted }  // 1st priority
    if hunger > 0.8            { return .hungry }
    if happiness > 0.8 && energy > 0.5 { return .ecstatic }
    if happiness > 0.6         { return .happy }
    if curiosity > 0.7 && energy > 0.4 { return .curious }
    if happiness < 0.3         { return .sad }
    if energy < 0.3            { return .tired }
    return .content
}
```

### Mood States and Their Effects

| Mood | Walk Speed Multiplier | Preferred Expression | Jump Frequency | Idle Animation Variety |
|---|---|---|---|---|
| `ecstatic` | 1.3× | `.excited` | 30% | 4 |
| `happy` | 1.1× | `.happy` | 10% | 3 |
| `content` | 1.0× | `.neutral` | 0% | 2 |
| `curious` | 1.15× | `.thinking` | 20% | 3 |
| `tired` | 0.7× | `.sleepy` | 0% | 1 |
| `exhausted` | 0.5× | `.sleepy` | 0% | 1 |
| `hungry` | 0.9× | `.sad` | 0% | 1 |
| `sad` | 0.8× | `.sad` | 0% | 1 |

Walk speed application:

```swift
// In update(), every 0.5 s
let moodMultiplier = moodSystem.overallMood.walkSpeedMultiplier
mascot.walkSpeed = 200 * CGFloat(moodMultiplier)
```

Base walk speed is 200 pt/s. When seeking apples this is multiplied by an additional 1.6×, so a fully ecstatic mascot chasing an apple walks at `200 * 1.3 * 1.6 = 416 pt/s`.

Expression application:

```swift
// Only applied if no active timed expression and current is .neutral
if mascot.expressionDuration == 0 && mascot.currentExpression == .neutral {
    let moodExpr = moodSystem.overallMood.preferredExpression
    if moodExpr != .neutral {
        mascot.setExpression(moodExpr)   // duration 0 = permanent until changed
    }
}
```

---

## SystemContext

`SystemContext` is a value type (`struct`) assembled in `AppController.update()` every 0.5 s and passed into `moodSystem.update(dt:context:)`.

```swift
struct SystemContext {
    var typingSpeed: Float          // keys per second (2 s rolling window)
    var cpuUsage: Float             // 0...1, total user+system across all cores
    var isIdle: Bool                // typingSpeed < 0.5 AND cpuUsage < 0.15
    var recentInteractions: Float   // incremented on clicks; decays by 0.1 per 0.5 s update
    var applesEatenRecently: Int    // count of apples eaten since last mood update
    var wasPetted: Bool             // true if petted this update window
    var wasThrown: Bool             // true if thrown this update window
    var screenshotDetected: Bool    // true if screenshot taken in last 3 s
}
```

Assembly in `update()`:

```swift
systemContext.typingSpeed         = systemMonitor.typingSpeed
systemContext.cpuUsage            = systemMonitor.cpuUsage
systemContext.isIdle              = systemMonitor.isIdle
systemContext.recentInteractions  = recentInteractionCount
systemContext.applesEatenRecently = applesEatenThisFrame
systemContext.screenshotDetected  = systemMonitor.screenshotDetected
moodSystem.update(dt: Float(moodUpdateInterval), context: systemContext)
applesEatenThisFrame   = 0        // reset frame counter
recentInteractionCount = max(0, recentInteractionCount - 0.1)  // decay
```

`recentInteractionCount` is incremented by 1 each time the user clicks on the mascot. It decays by 0.1 every 0.5 s update cycle.

---

## Status Bar Progress Bar

The menu bar icon is a color-coded progress bar rendered as an `NSBitmapImageRep`. It communicates the mascot's overall wellbeing at a glance.

### Formula

```swift
func moodOverall() -> Double {
    let e = Double(moodSystem.energy)
    let h = Double(moodSystem.happiness)
    let notHungry = 1.0 - Double(moodSystem.hunger)
    return (e + h + notHungry) / 3.0
}
```

The score is the average of energy, happiness, and satiation (1 − hunger). Range: 0.0–1.0.

### Color Thresholds

| Score Range | Bar Color |
|---|---|
| ≥ 0.7 | Green (`systemGreen`) |
| 0.4–0.7 | Yellow (`systemYellow`) |
| < 0.4 | Red (`systemRed`) |

### Bar Dimensions

```
Bar width:  36 pt (logical)
Bar height:  6 pt
Image size: 40 × 18 pt (bar + 2 pt padding each side + vertical centering)
Rendered at 2× Retina scale (72 × 36 physical pixels)
```

The fill uses a rounded rect with radius = `barH / 2`. The track (background) is `white 0.5, alpha 0.25`.

When accessibility is not granted, the icon switches to the `ptsicon_warn` SVG from the resource bundle instead of the progress bar.
