import Cocoa

// MARK: - Interactive Content View
// Handles mouse events directly for the mascot: click, drag, throw, pet.
// The parent window toggles ignoresMouseEvents in the 60fps loop so that
// events only arrive when the cursor is near the mascot or an apple.

final class InteractiveContentView: NSView {
    weak var controller: AppController?

    private var isDragging = false
    private var dragStartPoint: CGPoint = .zero
    private var mouseDownOnMascot = false

    // MARK: - Mouse Down

    override func mouseDown(with event: NSEvent) {
        guard let ctrl = controller else { return }
        let screenPoint = window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        let localPoint = convert(event.locationInWindow, from: nil)

        // Apple click?
        if ctrl.handleAppleClick(at: screenPoint) { return }

        // On mascot?
        let mascotRect = ctrl.claudeView.frame.insetBy(dx: -10, dy: -10)
        guard mascotRect.contains(localPoint) else {
            mouseDownOnMascot = false
            return
        }

        mouseDownOnMascot = true
        let now = CACurrentMediaTime()

        // Wake if sleeping
        if ctrl.mascot.isAsleep {
            ctrl.mascot.isAsleep = false
            ctrl.mascot.wakingUp = true
            ctrl.mascot.lastActivityTime = now
            ctrl.mascot.lastMouseMoveTime = now
            ctrl.mascot.mouseSettled = false
            ctrl.moodSystem.onWokenUp()
            return
        }

        // Begin squeeze animation (visual feedback for mouse press)
        ctrl.mascot.isSqueezing = true
        ctrl.mascot.squeezeStartTime = now
        ctrl.mascot.lastActivityTime = now

        // Prepare for potential drag
        isDragging = false
        dragStartPoint = localPoint
        ctrl.mascot.dragOffsetX = screenPoint.x - ctrl.mascot.x
        ctrl.mascot.dragOffsetY = screenPoint.y - ctrl.mascot.y
        ctrl.mascot.dragVelocityHistory.removeAll()
        ctrl.mascot.recordDragPosition(screenPoint, at: now)
    }

    // MARK: - Mouse Dragged

    override func mouseDragged(with event: NSEvent) {
        guard let ctrl = controller, mouseDownOnMascot else { return }
        let screenPoint = window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        let localPoint = convert(event.locationInWindow, from: nil)

        let dist = sqrt(
            pow(localPoint.x - dragStartPoint.x, 2) +
            pow(localPoint.y - dragStartPoint.y, 2)
        )

        if !isDragging && dist > 5 {
            isDragging = true
            ctrl.mascot.isSqueezing = false
            ctrl.mascot.isDragged = true
            ctrl.mascot.isAsleep = false
            ctrl.mascot.wakingUp = false
            ctrl.mascot.jumpPhase = .none
            ctrl.mascot.lastActivityTime = CACurrentMediaTime()
            ctrl.mascot.setExpression(.surprised, duration: 0)
        }

        if isDragging {
            let now = CACurrentMediaTime()
            ctrl.mascot.x = screenPoint.x - ctrl.mascot.dragOffsetX
            ctrl.mascot.y = max(0, screenPoint.y - ctrl.mascot.dragOffsetY)
            ctrl.mascot.recordDragPosition(screenPoint, at: now)
            ctrl.mascot.lastActivityTime = now
            ctrl.positionSprite()
        }
    }

    // MARK: - Mouse Up

    override func mouseUp(with event: NSEvent) {
        guard let ctrl = controller else { return }
        let localPoint = convert(event.locationInWindow, from: nil)

        if isDragging {
            isDragging = false
            // Let ThrownState.enter() handle velocity calculation
            ctrl.mascot.isDragged = false
            ctrl.stateMachine.forceTransition(to: StateKey.thrown, mascot: ctrl.mascot)
            mouseDownOnMascot = false
            return
        }

        // End squeeze
        let wasSqueezing = ctrl.mascot.isSqueezing
        ctrl.mascot.isSqueezing = false

        // Hold-to-pet: if held for 0.5s+ without dragging
        if wasSqueezing {
            let holdDuration = CACurrentMediaTime() - ctrl.mascot.squeezeStartTime
            if holdDuration > 0.5 {
                ctrl.moodSystem.onPetted()
                ctrl.mascot.setExpression(.love, duration: 2.0)
                ctrl.particleSystem?.emitHeart(
                    at: CGPoint(x: ctrl.mascot.x, y: ctrl.mascot.y + ctrl.mascot.spriteH)
                )
                mouseDownOnMascot = false
                return
            }
        }

        // Single click on mascot = in-place jump
        let mascotRect = ctrl.claudeView.frame.insetBy(dx: -10, dy: -10)
        if mascotRect.contains(localPoint) && ctrl.isFullyAwake() {
            ctrl.mascot.lastActivityTime = CACurrentMediaTime()
            ctrl.recentInteractionCount += 1
            ctrl.startInPlaceJump()
        }
        mouseDownOnMascot = false
    }

    // MARK: - Dragging state for the update loop
    var isCurrentlyDragging: Bool { isDragging }
}
