import Cocoa

// MARK: - Particle Rendering View

final class ParticleView: NSView {
    var particleType: ParticleSystem.ParticleType = .dust
    var particleRotation: CGFloat = 0
    var baseSize: CGFloat = 8

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        ctx.setShouldAntialias(false)

        let s = min(bounds.width, bounds.height)
        let cx = bounds.midX
        let cy = bounds.midY

        ctx.saveGState()
        ctx.translateBy(x: cx, y: cy)
        ctx.rotate(by: particleRotation)
        ctx.translateBy(x: -cx, y: -cy)

        switch particleType {
        case .dust:
            drawDust(ctx: ctx, size: s)
        case .sleepZ:
            drawZ(ctx: ctx, size: s)
        case .heart:
            drawHeart(ctx: ctx, size: s)
        case .spark:
            drawSpark(ctx: ctx, size: s)
        case .star:
            drawStar(ctx: ctx, size: s)
        case .sweat:
            drawSweat(ctx: ctx, size: s)
        case .footprint:
            drawFootprint(ctx: ctx, size: s)
        }

        ctx.restoreGState()
    }

    private func drawFootprint(ctx: CGContext, size: CGFloat) {
        ctx.setFillColor(NSColor(white: 0.4, alpha: 0.3).cgColor)
        ctx.fillEllipse(in: CGRect(x: -size * 0.5, y: -size * 0.3, width: size, height: size * 0.6))
    }

    private func drawDust(ctx: CGContext, size: CGFloat) {
        let color = NSColor(red: 0.6, green: 0.5, blue: 0.4, alpha: 0.5)
        ctx.setFillColor(color.cgColor)
        let inset = size * 0.2
        ctx.fillEllipse(in: bounds.insetBy(dx: inset, dy: inset))
    }

    private func drawZ(ctx: CGContext, size: CGFloat) {
        // Pixel art "Z"
        let color = NSColor(red: 0.5, green: 0.5, blue: 0.8, alpha: 0.7)
        ctx.setFillColor(color.cgColor)
        let px = size / 4
        // Top bar
        ctx.fill(CGRect(x: bounds.minX + px, y: bounds.maxY - px * 1.5, width: px * 2, height: px))
        // Diagonal
        ctx.fill(CGRect(x: bounds.midX, y: bounds.midY, width: px, height: px))
        // Bottom bar
        ctx.fill(CGRect(x: bounds.minX + px, y: bounds.minY + px * 0.5, width: px * 2, height: px))
    }

    private func drawHeart(ctx: CGContext, size: CGFloat) {
        let color = NSColor(red: 1.0, green: 0.3, blue: 0.4, alpha: 0.8)
        ctx.setFillColor(color.cgColor)
        let px = size / 5
        // Heart shape in pixel art
        ctx.fill(CGRect(x: bounds.minX + px, y: bounds.midY, width: px, height: px))
        ctx.fill(CGRect(x: bounds.minX + px * 2, y: bounds.midY + px, width: px, height: px))
        ctx.fill(CGRect(x: bounds.minX + px * 3, y: bounds.midY, width: px, height: px))
        ctx.fill(CGRect(x: bounds.minX + px * 2, y: bounds.midY - px, width: px, height: px))
        // Top bumps
        ctx.fill(CGRect(x: bounds.minX + px * 0.5, y: bounds.midY + px, width: px, height: px))
        ctx.fill(CGRect(x: bounds.minX + px * 3.5, y: bounds.midY + px, width: px, height: px))
    }

    private func drawSpark(ctx: CGContext, size: CGFloat) {
        let color = NSColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 0.9)
        ctx.setFillColor(color.cgColor)
        let px = max(1, size / 3)
        ctx.fill(CGRect(x: bounds.midX - px / 2, y: bounds.midY - px / 2, width: px, height: px))
    }

    private func drawStar(ctx: CGContext, size: CGFloat) {
        let color = NSColor(red: 1.0, green: 0.95, blue: 0.4, alpha: 0.85)
        ctx.setFillColor(color.cgColor)
        let px = size / 5
        let cx = bounds.midX
        let cy = bounds.midY
        // Cross pattern
        ctx.fill(CGRect(x: cx - px / 2, y: cy - px * 1.5, width: px, height: px * 3))
        ctx.fill(CGRect(x: cx - px * 1.5, y: cy - px / 2, width: px * 3, height: px))
        // Diagonal fills
        ctx.fill(CGRect(x: cx - px, y: cy + px * 0.5, width: px, height: px))
        ctx.fill(CGRect(x: cx + px * 0.5, y: cy + px * 0.5, width: px, height: px * 0.5))
    }

    private func drawSweat(ctx: CGContext, size: CGFloat) {
        let color = NSColor(red: 0.5, green: 0.7, blue: 1.0, alpha: 0.7)
        ctx.setFillColor(color.cgColor)
        let px = size / 4
        // Teardrop shape
        ctx.fill(CGRect(x: bounds.midX - px / 2, y: bounds.midY + px, width: px, height: px))
        ctx.fill(CGRect(x: bounds.midX - px, y: bounds.midY - px, width: px * 2, height: px * 2))
    }
}
