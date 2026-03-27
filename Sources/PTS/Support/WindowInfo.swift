import Cocoa

struct WindowInfo {
    let frame: NSRect
    let ownerName: String

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
