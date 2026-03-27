import Cocoa

final class ClaudeView: NSView {
    var lookDir: CGFloat = 0
    var legFrame = 0
    var bodyBob: CGFloat = 0
    var facingRight = true
    var isWalking = false
    var walkFacing: CGFloat = 0
    var legYBob: CGFloat = 0

    var eyeClose: CGFloat = 0
    var sitAmount: CGFloat = 0

    var currentLegs: [[Int]] = legsIdle
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    var armsRaised = false
    var rotation: CGFloat = 0

    // MARK: - New: Face Expression System
    var expression: FaceExpression = .neutral
    var expressionAnimPhase: CGFloat = 0 // 0...1 cycling for animated expressions
    var blushAmount: CGFloat = 0 // 0...1 for blush overlay

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        ctx.setShouldAntialias(false)

        let s = SCALE
        let ox: CGFloat = 10 * s
        let oy: CGFloat = 4 * s
        let bb = bodyBob

        let bodyWidth = 10 * s
        let centerX = ox + bodyWidth / 2

        func px(_ col: CGFloat, _ row: CGFloat, w: CGFloat = s, h: CGFloat = s) -> CGRect {
            let rawX = ox + col * s
            let flippedX = facingRight ? rawX : (2 * centerX - rawX - w)
            return CGRect(x: flippedX, y: row, width: w, height: h)
        }

        let legs = currentLegs
        let lowestLegRow = legs.lastIndex { $0.contains(1) } ?? max(0, legs.count - 1)
        let pivotX = bounds.width / 2
        let pivotY = oy - CGFloat(lowestLegRow + 1) * s

        ctx.saveGState()
        ctx.translateBy(x: pivotX, y: pivotY)
        ctx.rotate(by: rotation)
        ctx.scaleBy(x: scaleX, y: scaleY)
        ctx.translateBy(x: -pivotX, y: -pivotY)

        // Draw Shadows for legs if walking
        if isWalking && scaleX == 1 && scaleY == 1 {
            let shadowOffset = -walkFacing * s
            ctx.setFillColor(shadowColor.cgColor)
            for rowIndex in 0..<bodyGrid.count {
                let row = bodyGrid[rowIndex]
                guard let edgeCol = row.firstIndex(of: 1) else { continue }
                let rect = px(CGFloat(edgeCol), oy + CGFloat(bodyGrid.count - 1 - rowIndex) * s + bb + legYBob)
                ctx.fill(rect.offsetBy(dx: shadowOffset, dy: 0))
            }
        }

        // Draw Legs
        ctx.setFillColor(bodyColor.cgColor)
        for rowIndex in 0..<legs.count {
            for col in 0..<legs[rowIndex].count where legs[rowIndex][col] == 1 {
                ctx.fill(px(CGFloat(col), oy - CGFloat(rowIndex + 1) * s))
            }
        }

        // Draw Body and Screen
        for rowIndex in 0..<bodyGrid.count {
            for col in 0..<bodyGrid[rowIndex].count {
                let val = bodyGrid[rowIndex][col]
                if val == 0 { continue }

                if val == 1 {
                    ctx.setFillColor(bodyColor.cgColor)
                } else if val == 2 {
                    ctx.setFillColor(screenColor.cgColor)
                }

                let rect = px(CGFloat(col), oy + CGFloat(bodyGrid.count - 1 - rowIndex) * s + bb + legYBob)
                ctx.fill(rect)
            }
        }

        // MARK: - Draw Face Expression
        let style = expression.style
        ctx.setFillColor(eyeColor.cgColor)
        let flip: CGFloat = facingRight ? 1 : -1
        let minimumEyeInset: CGFloat = 2
        let maxEyeShift = max(0, s - minimumEyeInset)
        let eyeShift = round(max(-1, min(1, lookDir)) * maxEyeShift) * flip

        let eyeY = oy + CGFloat(bodyGrid.count - 1 - 3) * s + bb + legYBob

        // Eye close override from expression
        let effectiveEyeClose = style.eyeCloseOverride ?? eyeClose

        if effectiveEyeClose > 0.9 && expression == .neutral {
            // Fully closed — simple flat lines (original behavior for sleep)
            let eyeHeight = max(1, s * (1 - effectiveEyeClose * 0.75))
            let eyeYOffset = (s - eyeHeight) / 2

            let leftEye = px(3, eyeY + eyeYOffset)
            let rightEye = px(6, eyeY + eyeYOffset)
            ctx.fill(CGRect(x: leftEye.origin.x + eyeShift, y: leftEye.origin.y, width: s, height: eyeHeight))
            ctx.fill(CGRect(x: rightEye.origin.x + eyeShift, y: rightEye.origin.y, width: s, height: eyeHeight))
        } else {
            // Expression-based eye rendering
            let leftEyeOrigin = px(3, eyeY)
            let rightEyeOrigin = px(6, eyeY)

            let leftPt = CGPoint(x: leftEyeOrigin.origin.x + eyeShift, y: leftEyeOrigin.origin.y)
            let rightPt = CGPoint(x: rightEyeOrigin.origin.x + eyeShift, y: rightEyeOrigin.origin.y)

            // Apply eye close as blend: fully closed = flat line, open = expression shape
            if effectiveEyeClose > 0.5 {
                // Closing eyes — draw flat lines with height based on close amount
                let eyeHeight = max(1, s * (1 - effectiveEyeClose * 0.75))
                let eyeYOffset = (s - eyeHeight) / 2
                ctx.fill(CGRect(x: leftPt.x, y: leftPt.y + eyeYOffset, width: s, height: eyeHeight))
                ctx.fill(CGRect(x: rightPt.x, y: rightPt.y + eyeYOffset, width: s, height: eyeHeight))
            } else {
                ExpressionRenderer.drawEye(
                    shape: style.leftShape,
                    at: leftPt,
                    size: s,
                    in: ctx,
                    animPhase: expressionAnimPhase
                )
                ExpressionRenderer.drawEye(
                    shape: style.rightShape,
                    at: rightPt,
                    size: s,
                    in: ctx,
                    animPhase: expressionAnimPhase
                )
            }
        }

        // Mouth removed — face shows only eyes

        // Blush overlay (for .blush and .love expressions)
        if blushAmount > 0 || expression == .blush || expression == .love {
            let blush = max(blushAmount, expression == .blush || expression == .love ? 0.4 : 0)
            let blushColor = NSColor(red: 1.0, green: 0.4, blue: 0.5, alpha: Double(blush) * 0.3)
            ctx.setFillColor(blushColor.cgColor)
            // Small blush marks on cheeks (screen area, lower corners)
            let cheekY = oy + CGFloat(bodyGrid.count - 1 - 4) * s + bb + legYBob
            let leftCheek = px(2, cheekY)
            let rightCheek = px(7, cheekY)
            ctx.fill(CGRect(x: leftCheek.origin.x, y: leftCheek.origin.y, width: s, height: s * 0.5))
            ctx.fill(CGRect(x: rightCheek.origin.x, y: rightCheek.origin.y, width: s, height: s * 0.5))
        }

        ctx.restoreGState()
    }
}
