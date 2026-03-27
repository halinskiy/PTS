import Cocoa

// MARK: - Face Expression System

enum FaceExpression: String, CaseIterable {
    case neutral    // ._. default
    case happy      // ^_^
    case excited    // *_*
    case surprised  // O_O
    case sleepy     // -_-
    case sad        // ._.
    case scared     // >_<
    case love       // <3_<3
    case dizzy      // @_@
    case thinking   // ._.?
    case blush      // ^//^

    // Each expression defines how eyes are drawn on the 6x3 screen
    // Returns (leftEyePattern, rightEyePattern, mouthPattern)
    // Eye patterns are pixel offsets from standard eye position
    struct EyeStyle {
        let leftShape: EyeShape
        let rightShape: EyeShape
        let mouthPixels: [(col: Int, row: Int)] // relative to screen area
        let eyeCloseOverride: CGFloat? // nil = use current eyeClose
        let animationSpeed: CGFloat // multiplier for any built-in animation
    }

    enum EyeShape {
        case normal          // Single square pixel
        case wide            // 2px tall (surprised)
        case squint          // 0.5px tall line
        case closed          // flat line
        case happy           // ^ shape (inverted V)
        case star            // * sparkle
        case heart           // <3 shape
        case spiral          // @ dizzy
        case xEye            // X shaped (scared)
        case dot             // tiny dot
    }

    var style: EyeStyle {
        switch self {
        case .neutral:
            return EyeStyle(leftShape: .normal, rightShape: .normal, mouthPixels: [], eyeCloseOverride: nil, animationSpeed: 1)
        case .happy:
            return EyeStyle(leftShape: .happy, rightShape: .happy, mouthPixels: [], eyeCloseOverride: nil, animationSpeed: 1)
        case .excited:
            return EyeStyle(leftShape: .star, rightShape: .star, mouthPixels: [], eyeCloseOverride: 0, animationSpeed: 2)
        case .surprised:
            return EyeStyle(leftShape: .wide, rightShape: .wide, mouthPixels: [], eyeCloseOverride: 0, animationSpeed: 1)
        case .sleepy:
            return EyeStyle(leftShape: .squint, rightShape: .squint, mouthPixels: [], eyeCloseOverride: 0.7, animationSpeed: 0.5)
        case .sad:
            return EyeStyle(leftShape: .dot, rightShape: .dot, mouthPixels: [], eyeCloseOverride: nil, animationSpeed: 0.7)
        case .scared:
            return EyeStyle(leftShape: .xEye, rightShape: .xEye, mouthPixels: [], eyeCloseOverride: 0, animationSpeed: 3)
        case .love:
            return EyeStyle(leftShape: .heart, rightShape: .heart, mouthPixels: [], eyeCloseOverride: 0, animationSpeed: 1.2)
        case .dizzy:
            return EyeStyle(leftShape: .spiral, rightShape: .spiral, mouthPixels: [], eyeCloseOverride: 0, animationSpeed: 2)
        case .thinking:
            return EyeStyle(leftShape: .normal, rightShape: .dot, mouthPixels: [], eyeCloseOverride: nil, animationSpeed: 0.8)
        case .blush:
            return EyeStyle(leftShape: .happy, rightShape: .happy, mouthPixels: [], eyeCloseOverride: nil, animationSpeed: 1)
        }
    }
}

// MARK: - Expression Renderer

struct ExpressionRenderer {
    // Draws the eye shape at a given position in the CGContext
    static func drawEye(
        shape: FaceExpression.EyeShape,
        at point: CGPoint,
        size: CGFloat,
        in ctx: CGContext,
        animPhase: CGFloat = 0 // 0...1 for animated expressions
    ) {
        let s = size

        switch shape {
        case .normal:
            ctx.fill(CGRect(x: point.x, y: point.y, width: s, height: s))

        case .wide:
            // O - tall eye
            let h = s * 1.4
            let yOff = (s - h) / 2
            ctx.fill(CGRect(x: point.x, y: point.y + yOff, width: s, height: h))

        case .squint:
            // - horizontal line
            let h = max(1, s * 0.3)
            let yOff = (s - h) / 2
            ctx.fill(CGRect(x: point.x, y: point.y + yOff, width: s, height: h))

        case .closed:
            let h = max(1, s * 0.15)
            let yOff = (s - h) / 2
            ctx.fill(CGRect(x: point.x, y: point.y + yOff, width: s, height: h))

        case .happy:
            // ^ shape — draw as inverted V using two small rects
            let half = s / 2
            ctx.fill(CGRect(x: point.x, y: point.y + half, width: half, height: half))
            ctx.fill(CGRect(x: point.x + half, y: point.y + half, width: half, height: half))
            ctx.fill(CGRect(x: point.x + half * 0.3, y: point.y + s * 0.7, width: s * 0.4, height: half * 0.6))

        case .star:
            // * — cross pattern
            let third = s / 3
            ctx.fill(CGRect(x: point.x + third, y: point.y, width: third, height: s))
            ctx.fill(CGRect(x: point.x, y: point.y + third, width: s, height: third))
            // Animate sparkle by pulsing
            let pulse = 0.8 + 0.2 * sin(animPhase * .pi * 2)
            let inset = s * (1 - pulse) / 2
            ctx.fill(CGRect(x: point.x + inset, y: point.y + inset, width: s - inset * 2, height: s - inset * 2))

        case .heart:
            // Simple heart — two bumps on top, point at bottom
            let half = s / 2
            ctx.fill(CGRect(x: point.x, y: point.y + half, width: half, height: half))
            ctx.fill(CGRect(x: point.x + half, y: point.y + half, width: half, height: half))
            ctx.fill(CGRect(x: point.x + s * 0.15, y: point.y + s * 0.2, width: s * 0.7, height: half))
            ctx.fill(CGRect(x: point.x + s * 0.3, y: point.y, width: s * 0.4, height: s * 0.4))

        case .spiral:
            // @ — circle with center dot
            let inset = s * 0.15
            ctx.fill(CGRect(x: point.x + inset, y: point.y, width: s - inset * 2, height: s))
            ctx.fill(CGRect(x: point.x, y: point.y + inset, width: s, height: s - inset * 2))
            // Clear center for spiral effect
            let offset = sin(animPhase * .pi * 4) * s * 0.1
            ctx.setFillColor(screenColor.cgColor)
            ctx.fill(CGRect(x: point.x + s * 0.3 + offset, y: point.y + s * 0.3, width: s * 0.4, height: s * 0.4))
            ctx.setFillColor(eyeColor.cgColor)

        case .xEye:
            // X shape
            let quarter = s / 4
            // Diagonal 1
            ctx.fill(CGRect(x: point.x, y: point.y, width: quarter, height: quarter))
            ctx.fill(CGRect(x: point.x + quarter, y: point.y + quarter, width: quarter, height: quarter))
            ctx.fill(CGRect(x: point.x + quarter * 2, y: point.y + quarter * 2, width: quarter, height: quarter))
            ctx.fill(CGRect(x: point.x + quarter * 3, y: point.y + quarter * 3, width: quarter, height: quarter))
            // Diagonal 2
            ctx.fill(CGRect(x: point.x + quarter * 3, y: point.y, width: quarter, height: quarter))
            ctx.fill(CGRect(x: point.x + quarter * 2, y: point.y + quarter, width: quarter, height: quarter))
            ctx.fill(CGRect(x: point.x + quarter, y: point.y + quarter * 2, width: quarter, height: quarter))
            ctx.fill(CGRect(x: point.x, y: point.y + quarter * 3, width: quarter, height: quarter))

        case .dot:
            // Tiny centered dot
            let dotSize = max(1, s * 0.5)
            let off = (s - dotSize) / 2
            ctx.fill(CGRect(x: point.x + off, y: point.y + off, width: dotSize, height: dotSize))
        }
    }

    // Draws mouth pixels on the screen area
    static func drawMouth(
        pixels: [(col: Int, row: Int)],
        screenOrigin: CGPoint,
        pixelSize: CGFloat,
        in ctx: CGContext,
        facingRight: Bool,
        screenWidth: Int = 8
    ) {
        let mouthColor = NSColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 0.6)
        ctx.setFillColor(mouthColor.cgColor)
        for pixel in pixels {
            let col = facingRight ? CGFloat(pixel.col) : CGFloat(screenWidth - 1 - pixel.col)
            let row = CGFloat(pixel.row)
            ctx.fill(CGRect(
                x: screenOrigin.x + col * pixelSize,
                y: screenOrigin.y + row * pixelSize,
                width: pixelSize,
                height: max(1, pixelSize * 0.5)
            ))
        }
    }
}
