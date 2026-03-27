import Cocoa

// MARK: - Input Handler — Mouse interactions, drag & drop

final class InputHandler {
    weak var controller: AppController?

    private var globalMouseDownMonitor: Any?
    private var globalMouseDraggedMonitor: Any?
    private var globalMouseUpMonitor: Any?
    private var localMouseDownMonitor: Any?

    private var isDragging = false
    private var dragStartPoint: CGPoint = .zero
    private var consecutiveClickCount = 0
    private var lastClickTime: TimeInterval = 0
    private let petClickThreshold: TimeInterval = 0.5

    // MARK: - Setup

    func setupMonitors() {
        guard controller != nil else { return }

        // Global click monitor
        globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handleGlobalMouseDown(at: NSEvent.mouseLocation)
        }

        // Global drag monitor
        globalMouseDraggedMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            self?.handleGlobalMouseDragged(at: NSEvent.mouseLocation)
        }

        // Global mouse up monitor
        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.handleGlobalMouseUp(at: NSEvent.mouseLocation)
        }

        // Local click monitor (when our window receives events during drag)
        localMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            if let window = self?.controller?.window {
                let point = window.convertPoint(toScreen: event.locationInWindow)
                self?.handleGlobalMouseDown(at: point)
            }
            return event
        }
    }

    func removeMonitors() {
        if let m = globalMouseDownMonitor { NSEvent.removeMonitor(m) }
        if let m = globalMouseDraggedMonitor { NSEvent.removeMonitor(m) }
        if let m = globalMouseUpMonitor { NSEvent.removeMonitor(m) }
        if let m = localMouseDownMonitor { NSEvent.removeMonitor(m) }
        globalMouseDownMonitor = nil
        globalMouseDraggedMonitor = nil
        globalMouseUpMonitor = nil
        localMouseDownMonitor = nil
    }

    // MARK: - Mouse Down

    private func handleGlobalMouseDown(at screenPoint: CGPoint) {
        guard let ctrl = controller else { return }

        // Check apple click first
        if ctrl.handleAppleClick(at: screenPoint) { return }

        // Check if clicking on mascot
        guard let hitRect = ctrl.crabHitRectInScreen(), hitRect.contains(screenPoint) else {
            return
        }

        let now = CACurrentMediaTime()

        // If sleeping, wake up
        if ctrl.mascot.isAsleep {
            ctrl.stateMachine.forceTransition(to: StateKey.wakingUp, mascot: ctrl.mascot)
            ctrl.mascot.lastActivityTime = now
            ctrl.moodSystem.onWokenUp()
            return
        }

        // Start drag detection
        isDragging = false
        dragStartPoint = screenPoint

        // Track consecutive clicks for "petting"
        if now - lastClickTime < petClickThreshold {
            consecutiveClickCount += 1
        } else {
            consecutiveClickCount = 1
        }
        lastClickTime = now

        // If 3+ rapid clicks = petting!
        if consecutiveClickCount >= 3 {
            ctrl.moodSystem.onPetted()
            ctrl.mascot.setExpression(.love, duration: 2.0)
            ctrl.particleSystem.emitHeart(at: CGPoint(x: ctrl.mascot.x, y: ctrl.mascot.y + ctrl.mascot.spriteH))
            consecutiveClickCount = 0
            return
        }

        // Prepare for potential drag
        ctrl.mascot.dragOffsetX = screenPoint.x - ctrl.mascot.x
        ctrl.mascot.dragOffsetY = screenPoint.y - ctrl.mascot.y
        ctrl.mascot.recordDragPosition(screenPoint, at: now)
    }

    // MARK: - Mouse Dragged

    private func handleGlobalMouseDragged(at screenPoint: CGPoint) {
        guard let ctrl = controller else { return }
        guard ctrl.crabHitRectInScreen()?.contains(dragStartPoint) == true || isDragging else { return }

        let dragThreshold: CGFloat = 5
        let distFromStart = sqrt(
            pow(screenPoint.x - dragStartPoint.x, 2) +
            pow(screenPoint.y - dragStartPoint.y, 2)
        )

        if !isDragging && distFromStart > dragThreshold {
            // Start dragging
            isDragging = true
            ctrl.stateMachine.forceTransition(to: StateKey.dragged, mascot: ctrl.mascot)
        }

        if isDragging {
            let now = CACurrentMediaTime()
            ctrl.mascot.x = screenPoint.x - ctrl.mascot.dragOffsetX
            ctrl.mascot.y = screenPoint.y - ctrl.mascot.dragOffsetY
            ctrl.mascot.recordDragPosition(screenPoint, at: now)
            ctrl.mascot.lastActivityTime = now
        }
    }

    // MARK: - Mouse Up

    private func handleGlobalMouseUp(at screenPoint: CGPoint) {
        guard let ctrl = controller else { return }

        if isDragging {
            isDragging = false
            let vel = ctrl.mascot.computeThrowVelocity()
            let speed = sqrt(vel.dx * vel.dx + vel.dy * vel.dy)

            if speed > 200 {
                // Throw!
                ctrl.moodSystem.onThrown()
                ctrl.stateMachine.forceTransition(to: StateKey.thrown, mascot: ctrl.mascot)
            } else {
                // Gentle drop — just fall
                ctrl.mascot.velocityX = 0
                ctrl.mascot.velocityY = 0
                ctrl.stateMachine.forceTransition(to: StateKey.thrown, mascot: ctrl.mascot)
            }
            return
        }

        // Single click on mascot (not dragged) = in-place jump
        if ctrl.crabHitRectInScreen()?.contains(screenPoint) == true {
            if ctrl.isFullyAwake() {
                ctrl.mascot.lastActivityTime = CACurrentMediaTime()
                ctrl.startInPlaceJump()
            }
        }
    }

    deinit {
        removeMonitors()
    }
}
