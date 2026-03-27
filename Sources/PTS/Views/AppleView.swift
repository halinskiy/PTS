import Cocoa

final class AppleView: NSView {
    static let cachedImage: CGImage? = {
        let s = APPLE_SCALE
        let cols = appleGrid[0].count
        let rows = appleGrid.count
        let imageSize = CGFloat(rows) * s + APPLE_PADDING * 2
        let width = Int(imageSize)
        let height = Int(imageSize)

        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        ctx.setShouldAntialias(false)

        for rowIndex in 0..<rows {
            for col in 0..<cols {
                let colorIdx = appleGrid[rowIndex][col]
                guard colorIdx != 0, let color = appleColors[colorIdx] else { continue }
                ctx.setFillColor(color.cgColor)
                let y = APPLE_PADDING + CGFloat(rows - 1 - rowIndex) * s
                ctx.fill(CGRect(x: APPLE_PADDING + CGFloat(col) * s, y: y, width: s, height: s))
            }
        }

        return ctx.makeImage()
    }()

    var rotation: CGFloat = 0

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let image = Self.cachedImage else { return }
        ctx.clear(bounds)
        ctx.setShouldAntialias(false)

        let cx = bounds.width / 2
        let cy = bounds.height / 2
        ctx.saveGState()
        ctx.translateBy(x: cx, y: cy)
        ctx.rotate(by: rotation)
        ctx.translateBy(x: -bounds.width / 2, y: -bounds.height / 2)
        ctx.interpolationQuality = .none
        ctx.draw(image, in: bounds)
        ctx.restoreGState()
    }
}
