import Cocoa
import ApplicationServices

// MARK: - Real-time Window Tracker using AXObserver

final class WindowTracker {
    private var observer: AXObserver?
    private var trackedWindow: AXUIElement?
    private var trackedPID: pid_t = 0
    private var lastKnownFrame: NSRect?
    private var previousFrame: NSRect?
    private var frameDelta: CGVector = .zero
    private var frameVelocity: CGVector = .zero
    private var lastFrameTime: TimeInterval = 0

    var onWindowMoved: ((NSRect, CGVector) -> Void)?
    var onWindowResized: ((NSRect) -> Void)?
    var onWindowChanged: ((NSRect?) -> Void)?

    var currentFrame: NSRect? { lastKnownFrame }
    var currentDelta: CGVector { frameDelta }
    var currentVelocity: CGVector { frameVelocity }

    // MARK: - Tracking Management

    func startTracking() {
        updateTrackedWindow()
        // Set up workspace notifications for app switching
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeAppChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    func stopTracking() {
        removeObserver()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func activeAppChanged(_ notification: Notification) {
        // Small delay to let the new app's window become focused
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.updateTrackedWindow()
        }
    }

    func updateTrackedWindow() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            clearTracking()
            return
        }
        if frontApp.bundleIdentifier == "com.apple.dock" {
            clearTracking()
            return
        }

        let pid = frontApp.processIdentifier
        let appEl = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &window)

        guard let winEl = window as! AXUIElement? else {
            clearTracking()
            return
        }

        // If tracking same window, just update frame
        if trackedPID == pid, trackedWindow != nil {
            // Check if it's the same window element
            let frame = readWindowFrame(winEl)
            updateFrame(frame)
            return
        }

        // New window — set up observer
        removeObserver()
        trackedPID = pid
        trackedWindow = winEl

        setupObserver(for: winEl, pid: pid)

        let frame = readWindowFrame(winEl)
        lastKnownFrame = frame
        previousFrame = frame
        lastFrameTime = CACurrentMediaTime()
        frameDelta = .zero
        frameVelocity = .zero
        onWindowChanged?(frame)
    }

    private func clearTracking() {
        removeObserver()
        trackedWindow = nil
        trackedPID = 0
        let hadFrame = lastKnownFrame != nil
        lastKnownFrame = nil
        previousFrame = nil
        frameDelta = .zero
        frameVelocity = .zero
        if hadFrame {
            onWindowChanged?(nil)
        }
    }

    // MARK: - AXObserver

    private func setupObserver(for window: AXUIElement, pid: pid_t) {
        var obs: AXObserver?
        let result = AXObserverCreate(pid, { (observer, element, notification, refcon) in
            guard let refcon = refcon else { return }
            let tracker = Unmanaged<WindowTracker>.fromOpaque(refcon).takeUnretainedValue()
            let notifString = notification as String

            DispatchQueue.main.async {
                if notifString == kAXMovedNotification as String ||
                   notifString == kAXResizedNotification as String {
                    tracker.handleWindowChange()
                }
            }
        }, &obs)

        guard result == .success, let observer = obs else { return }
        self.observer = observer

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        AXObserverAddNotification(observer, window, kAXMovedNotification as CFString, refcon)
        AXObserverAddNotification(observer, window, kAXResizedNotification as CFString, refcon)

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    private func removeObserver() {
        if let observer = observer, let window = trackedWindow {
            AXObserverRemoveNotification(observer, window, kAXMovedNotification as CFString)
            AXObserverRemoveNotification(observer, window, kAXResizedNotification as CFString)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
    }

    private func handleWindowChange() {
        guard let winEl = trackedWindow else { return }
        let frame = readWindowFrame(winEl)
        updateFrame(frame)
    }

    private func updateFrame(_ frame: NSRect?) {
        guard let frame = frame else { return }
        let now = CACurrentMediaTime()
        let dt = now - lastFrameTime

        if let prev = lastKnownFrame {
            let dx = frame.origin.x - prev.origin.x
            let dy = frame.origin.y - prev.origin.y
            frameDelta = CGVector(dx: dx, dy: dy)

            if dt > 0.001 {
                frameVelocity = CGVector(dx: dx / CGFloat(dt), dy: dy / CGFloat(dt))
            }

            if abs(dx) > 0.5 || abs(dy) > 0.5 {
                onWindowMoved?(frame, frameDelta)
            }

            if abs(frame.width - prev.width) > 0.5 || abs(frame.height - prev.height) > 0.5 {
                onWindowResized?(frame)
            }
        }

        previousFrame = lastKnownFrame
        lastKnownFrame = frame
        lastFrameTime = now
    }

    // MARK: - Read Window Geometry

    private func readWindowFrame(_ window: AXUIElement) -> NSRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position)
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size)

        var point = CGPoint.zero
        var sz = CGSize.zero
        if let position { AXValueGetValue(position as! AXValue, .cgPoint, &point) }
        if let size { AXValueGetValue(size as! AXValue, .cgSize, &sz) }

        guard let screen = NSScreen.main else { return nil }
        let cocoaY = screen.frame.height - point.y - sz.height

        return NSRect(x: point.x, y: cocoaY, width: sz.width, height: sz.height)
    }

    // MARK: - Polling Fallback

    func pollUpdate() {
        guard let winEl = trackedWindow else {
            updateTrackedWindow()
            return
        }
        let frame = readWindowFrame(winEl)
        if frame == nil {
            // Window may have closed
            updateTrackedWindow()
        } else {
            updateFrame(frame)
        }
    }

    deinit {
        stopTracking()
    }
}
