# PTS — Services and macOS APIs

This document catalogs every macOS API and external service the app uses, explaining what each one does and how it is wired into the codebase.

---

## NSStatusBar / NSStatusItem

**File:** `AppController+Accessibility.swift`

PTS installs a permanent status-bar item using the variable-length style:

```swift
statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
```

The item's button image is updated every frame (`updateStatusBarIcon()`) to reflect one of two states:

1. **Accessibility not granted:** loads `ptsicon_warn.svg` from the resource bundle, 18×18 pt.
2. **Accessibility granted:** renders a live mood progress bar (see `MOOD_SYSTEM.md` for the formula) as an `NSBitmapImageRep`.

### Menu Items

| Title | Action | Notes |
|---|---|---|
| "Enable Accessibility Access" | `openAccessibilitySettings` | Hidden when permission granted |
| "Drop Apple" | `feedApple` | Option-F keyboard shortcut |
| "Tint" submenu | `changeTint(_:)` | One item per `MascotTheme.Preset`; uses `.tag = Int(hueShift)` |
| "Check for Updates…" | `checkForUpdates` | Title changes to "Checking…" during fetch |
| "About" | `showAboutWindow` | Opens `AboutWindowController` |
| "Quit" | `exitApp` | Q shortcut |

---

## NSApplication Activation Policy

**File:** `main.swift`

```swift
app.setActivationPolicy(.accessory)
```

This prevents PTS from appearing in the Dock, the Cmd-Tab switcher, or the app exposé. The process is a "background" app that only appears in the menu bar.

---

## NSWindow — Overlay Window

**File:** `AppController+Accessibility.swift` (`completeLaunch()`)

The overlay uses `.statusBar` window level to float above all normal app windows:

```swift
window.level = .statusBar
window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
```

- `.canJoinAllSpaces` — stays visible across all Mission Control spaces.
- `.stationary` — excluded from Exposé / Mission Control.
- `.ignoresCycle` — excluded from Cmd-Tab window cycling.

`window.ignoresMouseEvents` is toggled dynamically in the 60fps loop: enabled only when the cursor is within ~20 pt of the mascot sprite or within ~10 pt of an apple, then disabled to let clicks pass through to apps below.

---

## Accessibility API (AXUIElement)

PTS requires accessibility permission (`AXIsProcessTrusted()`) to use two capabilities:

### 1. Dock Geometry — `DockInfo.get(screen:)`

**File:** `Support/DockInfo.swift`

Reads the exact horizontal extent of the Dock's app icon list:

```swift
let appEl = AXUIElementCreateApplication(dockApp.processIdentifier)
AXUIElementCopyAttributeValue(appEl, "AXChildren" as CFString, &children)
// Iterates children looking for role == "AXList"
AXUIElementCopyAttributeValue(child, "AXPosition", &pos)
AXUIElementCopyAttributeValue(child, "AXSize", &size)
AXValueGetValue(pos as! AXValue, .cgPoint, &point)
AXValueGetValue(size as! AXValue, .cgSize, &sz)
return DockInfo(x: point.x, width: sz.width, height: dockHeight)
```

`dockHeight` comes from `screen.visibleFrame.origin.y - screen.frame.origin.y`, which is the gap between the bottom of the visible area and the bottom of the physical screen — exactly the Dock height.

Fallback when AX is unavailable or the list child is not found: a centered estimate of width `screenFrame.width * 0.5`.

### 2. Active Window Frame — `WindowInfo.getActive()`

**File:** `Support/WindowInfo.swift`

One-shot snapshot of the frontmost non-Dock window's frame:

```swift
let pid  = frontApp.processIdentifier
let appEl = AXUIElementCreateApplication(pid)
AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute, &window)
AXUIElementCopyAttributeValue(winEl, kAXPositionAttribute, &position)
AXUIElementCopyAttributeValue(winEl, kAXSizeAttribute, &size)
// Convert CG coordinates → Cocoa:
let cocoaY = screen.frame.height - point.y - sz.height
```

Used in `refreshWindowBounds()` as a polling fallback.

### 3. Real-Time Window Tracking — `WindowTracker`

**File:** `Core/WindowTracker.swift`

Creates a persistent `AXObserver` that fires callbacks when the tracked window moves or resizes:

```swift
AXObserverCreate(pid, callbackFn, &obs)
AXObserverAddNotification(observer, window, kAXMovedNotification, refcon)
AXObserverAddNotification(observer, window, kAXResizedNotification, refcon)
CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
```

The observer is re-created each time the frontmost app changes, via:

```swift
NSWorkspace.shared.notificationCenter.addObserver(
    self, selector: #selector(activeAppChanged),
    name: NSWorkspace.didActivateApplicationNotification, object: nil)
```

Notifications received (string constants from `ApplicationServices`):

| Notification | Source |
|---|---|
| `kAXMovedNotification` | Window origin changed |
| `kAXResizedNotification` | Window size changed |

Both are routed to `handleWindowChange()` → `updateFrame()`, which computes `frameDelta` and fires `onWindowMoved` or `onWindowResized` closures on the main queue.

### Permission Flow

```
app launch
  AXIsProcessTrusted()          — check without prompt
    if false:
      AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])
      — triggers system dialog on first launch only (UserDefaults flag)
    if true:
      activateAccessibilityFeaturesIfNeeded()

0.5 s poll Timer → AXIsProcessTrusted() — detect grant without relaunch
```

---

## SystemMonitor

**File:** `Core/SystemMonitor.swift`

### Keyboard Event Monitor

```swift
NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
    keyTimestamps.append(now)
    keyTimestamps = keyTimestamps.filter { now - $0 < 2.0 }  // 2 s window
    onTypingSpeedChanged?(typingSpeed)  // typingSpeed = count / 2.0 keys/s
}
```

Requires accessibility permission to monitor global key events.

### CPU Monitor

```swift
// Timer every 3 s
host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPU, &cpuLoadInfo, &numCPUInfo)
// Sum user + system ticks across all CPU cores
cpuUsage = Float(totalUser + totalSystem) / Float(totalUser + totalSystem + totalIdle)
vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuLoadInfo), size)
```

This is a standard Mach kernel API call. The host port (`mach_host_self()`) does not require entitlements. Memory returned by `host_processor_info` must be manually deallocated with `vm_deallocate`.

### Screenshot Detection

```swift
DistributedNotificationCenter.default().addObserver(
    forName: NSNotification.Name("com.apple.screencapture.didFinish"),
    object: nil, queue: .main
) { _ in
    screenshotDetected = true
    onScreenshot?()
    // resets after 3 s
}
```

`com.apple.screencapture.didFinish` is a system-wide distributed notification posted by `screencaptusd` whenever a screenshot is saved. No special entitlement is needed to observe it.

### App Switch Monitoring

```swift
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didActivateApplicationNotification,
    object: nil, queue: .main
) { notification in
    let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    onAppSwitch?(app.localizedName ?? "Unknown")
}
```

`NSWorkspace.didActivateApplicationNotification` posts to `NSWorkspace.shared.notificationCenter` (not the default center) when the frontmost application changes. The `applicationUserInfoKey` contains the newly active `NSRunningApplication`.

---

## NSEvent Global Mouse Monitors

**File:** `Core/InputHandler.swift` (legacy, not active at runtime)

The `InputHandler` class registers four `NSEvent` global and local monitors for `leftMouseDown`, `leftMouseDragged`, and `leftMouseUp`. This approach is the legacy mechanism; at runtime the app uses `InteractiveContentView`'s native `mouseDown/Dragged/Up` methods instead, enabled by dynamic `ignoresMouseEvents` toggling.

The monitors still exist and are wired up in `deactivateAccessibilityFeatures()` cleanup but `inputHandler` is set to `nil` there so they are torn down.

---

## Carbon HotKey API

**File:** `AppController+Apples.swift` (`registerFeedHotKey()`)

The "Drop Apple" keyboard shortcut (Option-F) uses the Carbon Event Manager because `NSMenuItem` shortcuts only fire when the app is active, but PTS runs as an accessory and is never the active app:

```swift
// Register event handler
InstallEventHandler(GetApplicationEventTarget(), callbackFn, 1, [eventSpec], nil, &hotKeyHandlerRef)

// Register the hot key: Option (optionKey) + F (kVK_ANSI_F)
let hotKeyID = EventHotKeyID(signature: 0x46454544, id: 1)  // "FEED"
RegisterEventHotKey(UInt32(kVK_ANSI_F), UInt32(optionKey), hotKeyID,
                    GetApplicationEventTarget(), 0, &feedHotKeyRef)
```

The Carbon handler dispatches to `feedApple()` via `DispatchQueue.main.async`. The hot key is unregistered in `exitApp()` with `UnregisterEventHotKey(feedHotKeyRef)`.

---

## GitHub Releases API — Auto-Updates

**File:** `AppController+Updates.swift`

```swift
let url = URL(string: "https://api.github.com/repos/halinskiy/PTS/releases/latest")!
var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
URLSession.shared.dataTask(with: request) { data, _, error in
    // parse JSON["tag_name"] and JSON["html_url"]
    let latest  = AppVersion(tagName)
    let current = AppVersion(AppMetadata.installedVersion)
    if latest > current { presentUpdateAvailableAlert(...) }
}.resume()
```

The check runs in two modes:

- **Silent** (on launch, after 3 s delay): shows alert only if an update is available.
- **Manual** ("Check for Updates…" menu): always shows a result (update available or "up to date").

`AppVersion` parses semantic version strings by stripping a leading `v`/`V`, splitting on `.`, and comparing component integers. Handles `v1.2.3-beta` style tags by taking only the numeric prefix of each component.

---

## NSWorkspace

Used in several places:

| Call | Purpose |
|---|---|
| `NSWorkspace.shared.frontmostApplication` | Find current front app for AX and Dock-obscure checks |
| `NSWorkspace.shared.runningApplications` | Find Dock process (`com.apple.dock`) for `DockInfo` |
| `NSWorkspace.shared.open(url)` | Open GitHub release page or Accessibility System Preferences |
| `NSWorkspace.shared.notificationCenter` | Subscribe to `didActivateApplicationNotification` |

---

## NSScreen

| Call | Purpose |
|---|---|
| `NSScreen.main` | Primary display frame (screen origin, width, height) |
| `screen.visibleFrame` | Frame minus Dock and menu bar; `visibleFrame.origin.y` gives Dock height |
| `screen.frame.height` | Used for CG-to-Cocoa Y coordinate conversion |

---

## NSNotificationCenter vs. DistributedNotificationCenter

| Center | Used For |
|---|---|
| `NSWorkspace.shared.notificationCenter` | App activation (in-process delivery within the macOS session) |
| `DistributedNotificationCenter.default()` | Screenshot detection (`com.apple.screencapture.didFinish`) — cross-process, posted by system daemon |
| `NotificationCenter.default` | Not used directly by PTS |

---

## UserDefaults

| Key | Type | Purpose |
|---|---|---|
| `"mascotHueShift"` | `Double` | Persists the selected tint preset across launches |
| `"PTS.accessibilityPrePromptSeen"` | `Bool` | Ensures the accessibility explanation alert is shown at most once ever |
