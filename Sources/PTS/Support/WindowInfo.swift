import Cocoa

struct WindowInfo {
    let frame: NSRect
    let ownerName: String

    /// Returns frames of all normal on-screen windows (no Accessibility needed).
    /// Excludes our own overlay window, desktop elements, and tiny utility windows.
    static func getAllFrames() -> [NSRect] {
        guard let screen = NSScreen.main else { return [] }
        let options = CGWindowListOption([.optionOnScreenOnly, .excludeDesktopElements])
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let ourPid = ProcessInfo.processInfo.processIdentifier
        var frames: [NSRect] = []

        for info in list {
            guard
                let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != ourPid,
                let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                let x = bounds["X"], let y = bounds["Y"],
                let w = bounds["Width"], let h = bounds["Height"],
                w > 80, h > 80
            else { continue }

            // Convert CG (top-left origin) → Cocoa (bottom-left origin)
            let cocoaY = screen.frame.height - y - h
            frames.append(NSRect(x: x, y: cocoaY, width: w, height: h))
        }
        return frames
    }

    /// Returns the process ID of the window whose frame best matches the given rect.
    static func getPID(for targetFrame: NSRect) -> pid_t? {
        guard let screen = NSScreen.main else { return nil }
        let options = CGWindowListOption([.optionOnScreenOnly, .excludeDesktopElements])
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }

        let ourPid = ProcessInfo.processInfo.processIdentifier
        for info in list {
            guard
                let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != ourPid,
                let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                let x = bounds["X"], let y = bounds["Y"],
                let w = bounds["Width"], let h = bounds["Height"]
            else { continue }

            let cocoaY = screen.frame.height - y - h
            let f = NSRect(x: x, y: cocoaY, width: w, height: h)
            if abs(f.origin.x - targetFrame.origin.x) < 3 &&
               abs(f.origin.y - targetFrame.origin.y) < 3 &&
               abs(f.width - targetFrame.width) < 3 &&
               abs(f.height - targetFrame.height) < 3 {
                return pid_t(pid)
            }
        }
        return nil
    }

    static func getActive() -> WindowInfo? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        if frontApp.bundleIdentifier == "com.apple.dock" { return nil }

        let pid = frontApp.processIdentifier
        let appEl = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &window)

        if let winEl = window as! AXUIElement? {
            var position: CFTypeRef?
            var size: CFTypeRef?
            AXUIElementCopyAttributeValue(winEl, kAXPositionAttribute as CFString, &position)
            AXUIElementCopyAttributeValue(winEl, kAXSizeAttribute as CFString, &size)

            var point = CGPoint.zero
            var sz = CGSize.zero
            if let position { AXValueGetValue(position as! AXValue, .cgPoint, &point) }
            if let size { AXValueGetValue(size as! AXValue, .cgSize, &sz) }

            // Convert to Cocoa coordinates (Y inverted from Core Graphics)
            guard let screen = NSScreen.main else { return nil }
            let cocoaY = screen.frame.height - point.y - sz.height

            return WindowInfo(
                frame: NSRect(x: point.x, y: cocoaY, width: sz.width, height: sz.height),
                ownerName: frontApp.localizedName ?? "Unknown"
            )
        }
        return nil
    }
}
