import Cocoa

struct DockInfo {
    let x: CGFloat
    let width: CGFloat
    let height: CGFloat

    static func get(screen: NSScreen) -> DockInfo {
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let dockHeight = visibleFrame.origin.y - screenFrame.origin.y

        if let dockApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.dock" }) {
            let appEl = AXUIElementCreateApplication(dockApp.processIdentifier)
            var children: CFTypeRef?
            AXUIElementCopyAttributeValue(appEl, "AXChildren" as CFString, &children)
            if let list = children as? [AXUIElement] {
                for child in list {
                    var role: CFTypeRef?
                    AXUIElementCopyAttributeValue(child, "AXRole" as CFString, &role)
                    guard (role as? String) == "AXList" else { continue }

                    var pos: CFTypeRef?
                    var size: CFTypeRef?
                    AXUIElementCopyAttributeValue(child, "AXPosition" as CFString, &pos)
                    AXUIElementCopyAttributeValue(child, "AXSize" as CFString, &size)

                    var point = CGPoint.zero
                    var sz = CGSize.zero
                    if let pos {
                        AXValueGetValue(pos as! AXValue, .cgPoint, &point)
                    }
                    if let size {
                        AXValueGetValue(size as! AXValue, .cgSize, &sz)
                    }
                    return DockInfo(x: point.x, width: sz.width, height: dockHeight)
                }
            }
        }

        let dockWidth = screenFrame.width * 0.5
        let dockX = screenFrame.origin.x + (screenFrame.width - dockWidth) / 2
        return DockInfo(x: dockX, width: dockWidth, height: dockHeight)
    }
}
