import Cocoa

// MARK: - Mascot Entity — Central state for the mascot

final class MascotEntity {
    // Position
    var x: CGFloat = 0
    var y: CGFloat = 0
    var level: CrabLevel = .dock
    var facingRight: Bool = true

    // Velocity (for drag/throw physics)
    var velocityX: CGFloat = 0
    var velocityY: CGFloat = 0

    // Jump state
    var jumpPhase: JumpPhase = .none
    var jumpTimer: CGFloat = 0
    var jumpStartY: CGFloat = 0
    var jumpEndY: CGFloat = 0
    var jumpDirection: CGFloat = 0
    var currentJumpHorizontalDistance: CGFloat = 0
    var landingTravelDirection: CGFloat = 0
    var climbingOnLeft = false

    // Walk
    var walkSpeed: CGFloat = 200
    var walkTimer: CGFloat = 0
    var breatheTimer: CGFloat = 0
    var settleTimer: CGFloat = 0
    let settleDuration: CGFloat = 0.35

    // Look
    var rawLookDir: CGFloat = 0
    var lookDirVelocity: CGFloat = 0
    var eyeLookStep: CGFloat = 0

    // Activity tracking
    var lastActivityTime: TimeInterval = 0
    var lastMouseMoveTime: TimeInterval = 0
    var mouseSettled = false
    var pendingTargetX: CGFloat? = nil
    var autoTargetX: CGFloat? = nil

    // Drag state
    var isDragged = false
    var dragOffsetX: CGFloat = 0
    var dragOffsetY: CGFloat = 0
    var dragVelocityHistory: [(point: CGPoint, time: TimeInterval)] = []
    var isThrown = false

    // Hover state
    var isHovered = false
    var hoverStartTime: TimeInterval = 0
    var hoverIntensity: CGFloat = 0 // 0..1, ramps up smoothly

    // Edge sitting
    var isEdgeSitting = false
    var edgeSitTimer: CGFloat = 0
    var legSwingPhase: CGFloat = 0

    // Wall climbing state
    var wallSide: Int = 0  // -1 left, +1 right, 0 none
    var wallClimbDir: CGFloat = 0  // +1 up, -1 down, 0 hanging

    // Squeeze (mouse-down hold)
    var isSqueezing = false
    var squeezeStartTime: TimeInterval = 0

    // Landing shake
    var landingShakeTimer: CGFloat = 0

    // Recovery after falling (alt-tab, window close, etc.)
    var recoveryTimer: CGFloat = 0        // countdown until pet starts moving
    var seekActiveWindow = false           // after recovery, walk to active window

    // Expression
    var currentExpression: FaceExpression = .neutral
    var expressionTimer: CGFloat = 0
    var expressionDuration: CGFloat = 0 // 0 = permanent until changed
    var targetExpression: FaceExpression = .neutral
    var expressionBlend: CGFloat = 1.0 // 0 = transitioning, 1 = fully in current

    // Sleep
    var isAsleep = false
    var wakingUp = false
    let drowsyDelay: TimeInterval = 3.0
    let sleepDelay: TimeInterval = 5.0

    // Apple seeking
    var isSeekingApples = false
    var appleSeekStartTime: TimeInterval = 0
    var appleSeekDelay: TimeInterval = 0
    var appleSeekTargetID: ObjectIdentifier? = nil
    var appleSeekHopTriggers: [CGFloat] = []

    // Sprite dimensions
    let spriteW: CGFloat = 30 * SCALE
    let spriteH: CGFloat = 18 * SCALE

    // Jump physics constants
    let squishDur: CGFloat = 0.07
    let airDur: CGFloat = 0.28
    let landDur: CGFloat = 0.08
    let jumpArcHeight: CGFloat = 60
    let jumpHorizontalDistance: CGFloat = 180
    let autoThresh: CGFloat = 5
    let settleDelay: TimeInterval = 0.52

    // MARK: - Expression Management

    func setExpression(_ expression: FaceExpression, duration: CGFloat = 0) {
        if expression == currentExpression { return }
        targetExpression = expression
        expressionBlend = 0
        expressionDuration = duration
        expressionTimer = 0
    }

    func updateExpression(dt: CGFloat) {
        // Blend transition
        if expressionBlend < 1.0 {
            expressionBlend = min(1.0, expressionBlend + dt * 6.0) // ~0.17s transition
            if expressionBlend >= 1.0 {
                currentExpression = targetExpression
            }
        }

        // Auto-expire timed expressions
        if expressionDuration > 0 && currentExpression == targetExpression {
            expressionTimer += dt
            if expressionTimer >= expressionDuration {
                setExpression(.neutral)
            }
        }
    }

    // Effective expression considering blend
    var effectiveExpression: FaceExpression {
        expressionBlend >= 0.5 ? targetExpression : currentExpression
    }

    // MARK: - Drag Velocity Tracking

    func recordDragPosition(_ point: CGPoint, at time: TimeInterval) {
        dragVelocityHistory.append((point: point, time: time))
        // Keep only last 5 samples for velocity calculation
        if dragVelocityHistory.count > 5 {
            dragVelocityHistory.removeFirst()
        }
    }

    func computeThrowVelocity() -> CGVector {
        guard dragVelocityHistory.count >= 2 else { return .zero }
        let recent = dragVelocityHistory.suffix(3)
        guard let first = recent.first, let last = recent.last else { return .zero }
        let dt = last.time - first.time
        guard dt > 0.001 else { return .zero }

        let dx = last.point.x - first.point.x
        let dy = last.point.y - first.point.y
        return CGVector(dx: dx / CGFloat(dt), dy: dy / CGFloat(dt))
    }

    func clearDragState() {
        isDragged = false
        isThrown = false
        dragVelocityHistory.removeAll()
        dragOffsetX = 0
        dragOffsetY = 0
    }
}
