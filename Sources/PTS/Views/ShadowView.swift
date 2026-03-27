import Cocoa

final class ShadowView: NSView {
    var facingRight = true
    var legRows = 3

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        
        let s = SCALE
        let oy = SHADOW_FLOOR_MARGIN
        let shadowWidth = bounds.width * 0.55
        let shadowHeight = 2 * s
        let shadowX = (bounds.width - shadowWidth) / 2
        let shadowY = oy - shadowHeight / 2 - 1

        ctx.setFillColor(NSColor(red: 0.08, green: 0.03, blue: 0.0, alpha: 0.10).cgColor)
        ctx.fillEllipse(in: CGRect(x: shadowX, y: shadowY, width: shadowWidth, height: shadowHeight))
    }
}
