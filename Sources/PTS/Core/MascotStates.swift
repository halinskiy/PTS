import Cocoa

// MARK: - State Keys

enum StateKey {
    static let idle = "idle"
    static let walking = "walking"
    static let jumping = "jumping"
    static let climbing = "climbing"
    static let sleeping = "sleeping"
    static let wakingUp = "wakingUp"
    static let dragged = "dragged"
    static let thrown = "thrown"
    static let seekingApple = "seekingApple"
    static let wallClimb = "wallClimb"
}

// MARK: - Idle Micro-Animations

enum MicroAnimation: CaseIterable {
    case lookAround     // subtle body tilt side to side
    case yawn           // eyes close, stretch up, then back
    case stretch        // expand wide, arms raised
    case hopInPlace     // small jump (uses existing jump system)
    case tapFoot        // rapid leg alternation
    case sitRelax       // partial sit, relax for a moment
}

// MARK: - Idle State

final class IdleState: MascotStateProtocol {
    weak var controller: AppController?
    var blinkTimer: CGFloat = 0

    // Micro-animation system
    var microTimer: CGFloat = 0
    var nextMicroTime: CGFloat = CGFloat.random(in: 5...10)
    var currentMicro: MicroAnimation? = nil
    var microProgress: CGFloat = 0
    var microDuration: CGFloat = 0

    func enter(mascot: MascotEntity) {
        mascot.jumpPhase = .none
        blinkTimer = 0
        microTimer = 0
        nextMicroTime = CGFloat.random(in: 4...8)
        currentMicro = nil
    }

    func update(dt: CGFloat, mascot: MascotEntity) {
        guard let ctrl = controller else { return }

        let now = CACurrentMediaTime()
        let idleTime = now - mascot.lastActivityTime

        // Don't run micro-animations when drowsy or sleeping (updateVisuals handles that)
        guard idleTime < mascot.drowsyDelay && !mascot.isAsleep else {
            currentMicro = nil
            mascot.isEdgeSitting = false
            return
        }

        // Edge sitting detection: on a window, near edge, idle for >2s
        if ctrl.level == .window, let petWin = ctrl.petWindowFrame, currentMicro == nil {
            let nearLeft = mascot.x <= petWin.minX + 10
            let nearRight = mascot.x >= petWin.maxX - 10
            if nearLeft || nearRight {
                mascot.edgeSitTimer += dt
                if mascot.edgeSitTimer > 2 && !mascot.isEdgeSitting {
                    mascot.isEdgeSitting = true
                    ctrl.claudeView.facingRight = nearLeft
                    mascot.setExpression(.happy, duration: 0)
                }
            } else {
                mascot.edgeSitTimer = 0
                mascot.isEdgeSitting = false
            }
        } else {
            mascot.edgeSitTimer = 0
            mascot.isEdgeSitting = false
        }

        // Edge sitting animation
        if mascot.isEdgeSitting {
            mascot.legSwingPhase += dt * 0.8
            let swing = sin(mascot.legSwingPhase * .pi * 2)
            ctrl.claudeView.currentLegs = swing > 0 ? legsDangle : legsDangleSwing
            ctrl.claudeView.sitAmount += (0.4 - ctrl.claudeView.sitAmount) * min(1, 4 * dt)
            ctrl.claudeView.armsRaised = false
            return
        }

        // Micro-animation system
        updateMicroAnimation(dt: dt, mascot: mascot, ctrl: ctrl)
    }

    func exit(mascot: MascotEntity) {
        blinkTimer = 0
        currentMicro = nil
    }

    // MARK: Micro-Animation Logic

    private func updateMicroAnimation(dt: CGFloat, mascot: MascotEntity, ctrl: AppController) {
        if let micro = currentMicro {
            // Advance current animation
            microProgress += dt / microDuration
            if microProgress >= 1 {
                finishMicroAnimation(ctrl: ctrl)
                return
            }
            applyMicroAnimation(micro, progress: microProgress, ctrl: ctrl, mascot: mascot)
        } else {
            // Timer to next animation
            microTimer += dt
            if microTimer >= nextMicroTime {
                startRandomMicroAnimation(mascot: mascot, ctrl: ctrl)
            }
        }
    }

    private func startRandomMicroAnimation(mascot: MascotEntity, ctrl: AppController) {
        let mood = ctrl.moodSystem.overallMood
        let weights = microWeights(for: mood)
        let micro = weightedRandom(from: weights)

        // hopInPlace uses the jump system — hand off directly
        if micro == .hopInPlace {
            ctrl.startInPlaceJump()
            microTimer = 0
            nextMicroTime = CGFloat.random(in: 5...12)
            return
        }

        currentMicro = micro
        microProgress = 0
        microTimer = 0

        switch micro {
        case .lookAround:  microDuration = 1.4
        case .yawn:        microDuration = 1.2
        case .stretch:     microDuration = 1.0
        case .tapFoot:     microDuration = 0.6
        case .sitRelax:    microDuration = 3.0
        default:           microDuration = 1.0
        }
    }

    private func applyMicroAnimation(_ micro: MicroAnimation, progress t: CGFloat, ctrl: AppController, mascot: MascotEntity) {
        switch micro {
        case .lookAround:
            // Subtle body tilt: left → center → right → center
            let phase = sin(t * .pi * 2)
            ctrl.claudeView.rotation = phase * 0.04

        case .yawn:
            // First half: eyes close + stretch up. Second half: recover.
            if t < 0.5 {
                let p = t / 0.5
                ctrl.claudeView.eyeClose = p
                ctrl.claudeView.scaleY = 1 + 0.08 * p
                ctrl.claudeView.scaleX = 1 - 0.03 * p
            } else {
                let p = (t - 0.5) / 0.5
                ctrl.claudeView.eyeClose = 1 - p
                ctrl.claudeView.scaleY = 1.08 - 0.08 * p
                ctrl.claudeView.scaleX = 0.97 + 0.03 * p
            }
            mascot.setExpression(.sleepy, duration: 0)

        case .stretch:
            // Expand wide with arms up, then back
            let bell = sin(t * .pi)
            ctrl.claudeView.scaleX = 1 + 0.12 * bell
            ctrl.claudeView.scaleY = 1 - 0.04 * bell
            ctrl.claudeView.armsRaised = t < 0.8
            if t < 0.1 { mascot.setExpression(.happy, duration: 0) }

        case .tapFoot:
            // Rapid leg alternation 4 times
            let cycle = Int(t * 8)
            ctrl.claudeView.legFrame = cycle % 2
            ctrl.claudeView.currentLegs = ctrl.claudeView.legFrame == 0 ? legsIdle : legsWalk

        case .sitRelax:
            // Gradually sit down, hold, then back up
            if t < 0.2 {
                ctrl.claudeView.sitAmount = (t / 0.2) * 0.5
            } else if t < 0.8 {
                ctrl.claudeView.sitAmount = 0.5
                ctrl.claudeView.legYBob = -2 * SCALE * 0.5
            } else {
                ctrl.claudeView.sitAmount = 0.5 * (1 - (t - 0.8) / 0.2)
            }
            mascot.setExpression(.happy, duration: 0)

        case .hopInPlace:
            break // handled by jump system
        }
    }

    private func finishMicroAnimation(ctrl: AppController) {
        // Reset visual overrides
        ctrl.claudeView.armsRaised = false
        ctrl.claudeView.currentLegs = legsIdle
        ctrl.claudeView.legFrame = 0
        currentMicro = nil
        nextMicroTime = CGFloat.random(in: 5...12)
    }

    // MARK: Mood-weighted random selection

    private func microWeights(for mood: MoodSystem.Mood) -> [(MicroAnimation, Float)] {
        switch mood {
        case .tired, .exhausted:
            return [(.yawn, 0.4), (.sitRelax, 0.3), (.lookAround, 0.2), (.stretch, 0.1)]
        case .ecstatic:
            return [(.hopInPlace, 0.35), (.tapFoot, 0.25), (.stretch, 0.2), (.lookAround, 0.2)]
        case .curious:
            return [(.lookAround, 0.4), (.tapFoot, 0.2), (.hopInPlace, 0.2), (.yawn, 0.1), (.stretch, 0.1)]
        case .happy:
            return [(.hopInPlace, 0.2), (.stretch, 0.2), (.lookAround, 0.2), (.tapFoot, 0.2), (.sitRelax, 0.2)]
        case .sad, .hungry:
            return [(.sitRelax, 0.4), (.yawn, 0.3), (.lookAround, 0.2), (.tapFoot, 0.1)]
        default:
            return [(.lookAround, 0.25), (.yawn, 0.15), (.stretch, 0.15), (.tapFoot, 0.15), (.hopInPlace, 0.15), (.sitRelax, 0.15)]
        }
    }

    private func weightedRandom(from weights: [(MicroAnimation, Float)]) -> MicroAnimation {
        let total = weights.reduce(Float(0)) { $0 + $1.1 }
        var roll = Float.random(in: 0..<total)
        for (anim, weight) in weights {
            roll -= weight
            if roll <= 0 { return anim }
        }
        return weights.last?.0 ?? .lookAround
    }
}

// MARK: - Walking State

final class WalkingState: MascotStateProtocol {
    weak var controller: AppController?

    func enter(mascot: MascotEntity) {
        mascot.settleTimer = 0
    }

    func update(dt: CGFloat, mascot: MascotEntity) {
        guard let ctrl = controller else { return }

        // If no target, go back to idle
        guard let target = mascot.autoTargetX else {
            ctrl.stateMachine.transition(to: StateKey.idle, mascot: mascot)
            return
        }

        let now = CACurrentMediaTime()
        mascot.lastActivityTime = now

        let dx = target - mascot.x
        if abs(dx) > mascot.autoThresh {
            let dir: CGFloat = dx > 0 ? 1 : -1
            let activeWalkSpeed = mascot.isSeekingApples ? mascot.walkSpeed * 1.6 : mascot.walkSpeed
            let nextX = mascot.x + dir * min(activeWalkSpeed * dt, abs(dx))
            mascot.x = nextX
            mascot.facingRight = dir > 0

            ctrl.claudeView.facingRight = mascot.facingRight
            ctrl.claudeView.isWalking = true
            ctrl.claudeView.walkFacing = dir

            // Leg animation
            mascot.walkTimer += dt
            let cycleSpeed: CGFloat = 0.15
            if mascot.walkTimer > cycleSpeed {
                ctrl.claudeView.legFrame = ctrl.claudeView.legFrame == 0 ? 1 : 0
                mascot.walkTimer = 0
            }
            ctrl.claudeView.currentLegs = ctrl.claudeView.legFrame == 0 ? legsIdle : legsWalk
        } else {
            mascot.autoTargetX = nil
            ctrl.claudeView.isWalking = false
            ctrl.stateMachine.transition(to: StateKey.idle, mascot: mascot)
        }
    }

    func exit(mascot: MascotEntity) {
        controller?.claudeView.isWalking = false
        controller?.claudeView.walkFacing = 0
    }
}

// MARK: - Sleeping State

final class SleepingState: MascotStateProtocol {
    weak var controller: AppController?
    var canBeInterrupted: Bool { true }

    func enter(mascot: MascotEntity) {
        mascot.isAsleep = true
        mascot.setExpression(.sleepy)
        controller?.claudeView.eyeClose = 1
        controller?.claudeView.sitAmount = 1
    }

    func update(dt: CGFloat, mascot: MascotEntity) {
        guard let ctrl = controller else { return }
        ctrl.claudeView.eyeClose = 1
        ctrl.claudeView.sitAmount = 1
        ctrl.claudeView.currentLegs = legsIdle
        // Particles handled by ParticleSystem
    }

    func exit(mascot: MascotEntity) {
        mascot.isAsleep = false
        mascot.wakingUp = true
        mascot.setExpression(.neutral)
    }
}

// MARK: - Waking Up State

final class WakingUpState: MascotStateProtocol {
    weak var controller: AppController?

    func enter(mascot: MascotEntity) {
        mascot.wakingUp = true
        mascot.lastActivityTime = CACurrentMediaTime()
    }

    func update(dt: CGFloat, mascot: MascotEntity) {
        guard let ctrl = controller else { return }

        ctrl.claudeView.eyeClose = max(ctrl.claudeView.eyeClose - dt * 6, 0)
        ctrl.claudeView.sitAmount = max(ctrl.claudeView.sitAmount - dt * 6, 0)

        if ctrl.claudeView.sitAmount < 0.05 {
            mascot.wakingUp = false
            ctrl.stateMachine.transition(to: StateKey.idle, mascot: mascot)
        }
    }

    func exit(mascot: MascotEntity) {
        mascot.wakingUp = false
    }
}

// MARK: - Dragged State

final class DraggedState: MascotStateProtocol {
    weak var controller: AppController?
    var canBeInterrupted: Bool { false }

    func enter(mascot: MascotEntity) {
        mascot.isDragged = true
        mascot.setExpression(.surprised, duration: 0)
        mascot.isAsleep = false
        mascot.wakingUp = false
        mascot.lastActivityTime = CACurrentMediaTime()

        controller?.window?.ignoresMouseEvents = false
    }

    func update(dt: CGFloat, mascot: MascotEntity) {
        guard let ctrl = controller else { return }

        let vel = mascot.computeThrowVelocity()
        let speed = sqrt(vel.dx * vel.dx + vel.dy * vel.dy)

        // Direction-based facing
        if abs(vel.dx) > 50 {
            ctrl.claudeView.facingRight = vel.dx > 0
        }

        // Velocity-based stretch (squash in movement direction)
        let stretchFactor = min(0.15, speed / 5000)
        let moveAngle = atan2(vel.dy, vel.dx)
        ctrl.claudeView.scaleX = 1 + stretchFactor * abs(sin(moveAngle))
        ctrl.claudeView.scaleY = 1 - stretchFactor * abs(cos(moveAngle)) * 0.5

        // Limb poses based on vertical velocity
        if vel.dy > 200 {
            ctrl.claudeView.currentLegs = legsRising
            ctrl.claudeView.armsRaised = true
        } else if vel.dy < -200 {
            ctrl.claudeView.currentLegs = legsFalling
            ctrl.claudeView.armsRaised = false
        } else {
            ctrl.claudeView.currentLegs = legsIdle
            ctrl.claudeView.armsRaised = true
        }

        // Rotation tilt based on horizontal velocity
        let tilt = max(-0.3, min(0.3, vel.dx / 2000))
        ctrl.claudeView.rotation += (tilt - ctrl.claudeView.rotation) * min(1, 8 * dt)

        // Expression thresholds
        if speed > 800 {
            mascot.setExpression(.dizzy)
        } else if speed > 400 {
            mascot.setExpression(.scared)
        } else if speed > 150 {
            mascot.setExpression(.surprised)
        } else {
            mascot.setExpression(.thinking)
        }

        ctrl.claudeView.eyeClose = 0
        ctrl.claudeView.sitAmount = 0
    }

    func exit(mascot: MascotEntity) {
        mascot.isDragged = false
        controller?.window?.ignoresMouseEvents = true
    }
}

// MARK: - Thrown State

final class ThrownState: MascotStateProtocol {
    weak var controller: AppController?
    let gravity: CGFloat = -2600       // heavier feel
    let airResistanceX: CGFloat = 0.10 // more horizontal drag — stops drifting
    let airResistanceY: CGFloat = 0.06
    let bounceDamping: CGFloat = 0.38  // less bouncy
    let frictionX: CGFloat = 0.98
    var canBeInterrupted: Bool { false }

    func enter(mascot: MascotEntity) {
        mascot.isThrown = true
        mascot.isAsleep = false
        controller?.petWindowFrame = nil  // pet is no longer on any window
        mascot.wakingUp = false
        controller?.claudeView.eyeClose = 0
        controller?.claudeView.sitAmount = 0

        // If velocity was pre-set (window physics, etc.), keep it
        let presetSpeed = sqrt(mascot.velocityX * mascot.velocityX + mascot.velocityY * mascot.velocityY)
        if presetSpeed > 10 && mascot.dragVelocityHistory.isEmpty {
            // Already have velocity from external source (window bounce, detach, etc.)
            if presetSpeed > 300 {
                mascot.setExpression(.scared)
            } else {
                mascot.setExpression(.surprised)
            }
            return
        }

        // Compute throw velocity from drag history
        let vel = mascot.computeThrowVelocity()
        let speed = sqrt(vel.dx * vel.dx + vel.dy * vel.dy)

        if speed > 150 {
            mascot.velocityX = vel.dx * 1.2
            mascot.velocityY = vel.dy * 1.2
            mascot.setExpression(.scared)
            controller?.moodSystem.onThrown()
        } else {
            // Gentle drop
            mascot.velocityX = vel.dx * 0.3
            mascot.velocityY = max(vel.dy * 0.3, -50)
            mascot.setExpression(.surprised, duration: 1.0)
        }
        mascot.dragVelocityHistory.removeAll()
    }

    func update(dt: CGFloat, mascot: MascotEntity) {
        guard let ctrl = controller else { return }

        // Apply gravity with air resistance (Shimeji-style)
        mascot.velocityX -= mascot.velocityX * airResistanceX
        mascot.velocityY += (gravity - mascot.velocityY * airResistanceY) * dt
        mascot.x += mascot.velocityX * dt
        mascot.y += mascot.velocityY * dt

        // Screen edge bounce (when thrown)
        if mascot.x < ctrl.screenLeft {
            mascot.x = ctrl.screenLeft
            mascot.velocityX = abs(mascot.velocityX) * bounceDamping
        } else if mascot.x > ctrl.screenRight {
            mascot.x = ctrl.screenRight
            mascot.velocityX = -abs(mascot.velocityX) * bounceDamping
        }

        // Floor collision
        let floorY: CGFloat
        let onDock = mascot.x >= ctrl.dockLeft && mascot.x <= ctrl.dockRight
        if onDock && mascot.y >= ctrl.dockFloorY - 10 {
            floorY = ctrl.dockFloorY
        } else {
            floorY = ctrl.groundFloorY
        }

        if mascot.y <= floorY {
            mascot.y = floorY
            let impactSpeed = abs(mascot.velocityY)

            if impactSpeed < 50 && abs(mascot.velocityX) < 30 {
                // Settled — land
                mascot.velocityX = 0
                mascot.velocityY = 0
                mascot.isThrown = false
                mascot.level = onDock ? .dock : .ground

                // Landing shake for hard landings
                if impactSpeed > 20 {
                    mascot.landingShakeTimer = 0.3
                }

                // If seeking active window after fall, start recovery pause
                if mascot.seekActiveWindow {
                    mascot.recoveryTimer = 1.2
                    mascot.setExpression(.dizzy, duration: 1.2)
                } else {
                    mascot.setExpression(.happy, duration: 1.5)
                }
                ctrl.stateMachine.forceTransition(to: StateKey.idle, mascot: mascot)
                ctrl.particleSystem?.emitDust(at: CGPoint(x: mascot.x, y: mascot.y), count: 6)
                return
            }

            // Impact squish proportional to velocity
            let impactStrength = min(1, impactSpeed / 800)
            ctrl.claudeView.scaleX = 1 + 0.25 * impactStrength
            ctrl.claudeView.scaleY = 1 - 0.20 * impactStrength

            if impactStrength > 0.5 {
                mascot.setExpression(.dizzy, duration: 0.5)
            } else {
                mascot.setExpression(.surprised, duration: 0.3)
            }

            mascot.velocityY = abs(mascot.velocityY) * bounceDamping
            mascot.velocityX *= 0.85
            ctrl.particleSystem?.emitDust(at: CGPoint(x: mascot.x, y: mascot.y), count: 3)
        }

        // Window top collision — skip if recently thrown off a window (cooldown)
        let canLandOnWindows = CACurrentMediaTime() >= mascot.noWindowLandingUntil
        if mascot.velocityY < 0 && canLandOnWindows {
            // Only land on top 5 visible windows (avoid background-Space windows)
            var candidates: [NSRect] = []
            if let active = ctrl.activeWindowFrame { candidates.append(active) }
            for f in ctrl.visibleWindowFrames.prefix(5) where !candidates.contains(f) { candidates.append(f) }

            for winFrame in candidates {
                let winFloor = ctrl.computeWindowFloorY(for: winFrame)
                let onWindowX = mascot.x >= winFrame.minX && mascot.x <= winFrame.maxX
                guard onWindowX && mascot.y <= winFloor + 8 && mascot.y > winFloor - 24 else { continue }

                mascot.y = winFloor
                if abs(mascot.velocityY) < 160 && abs(mascot.velocityX) < 80 {
                    // Land on window
                    mascot.velocityY = 0
                    mascot.velocityX = 0
                    mascot.isThrown = false
                    mascot.level = .window
                    ctrl.petWindowFrame = winFrame
                    ctrl.petWindowFloorY = winFloor
                    mascot.windowLandedAt = CACurrentMediaTime() // grace period
                    mascot.landingShakeTimer = 0.2
                    mascot.setExpression(.happy, duration: 1.5)
                    ctrl.stateMachine.forceTransition(to: StateKey.idle, mascot: mascot)
                    ctrl.particleSystem?.emitDust(at: CGPoint(x: mascot.x, y: mascot.y), count: 5)
                    return
                }
                // Bounce off window
                mascot.velocityY = abs(mascot.velocityY) * bounceDamping * 0.6
                ctrl.particleSystem?.emitDust(at: CGPoint(x: mascot.x, y: mascot.y), count: 2)
                break
            }
        }

        // Top of screen
        if let screen = NSScreen.main, mascot.y > screen.frame.height - mascot.spriteH {
            mascot.y = screen.frame.height - mascot.spriteH
            mascot.velocityY = -abs(mascot.velocityY) * bounceDamping
        }

        // Dock top collision (from above, while airborne on ground level)
        if !onDock && mascot.y <= ctrl.dockFloorY + 20 && mascot.y > ctrl.dockFloorY - 5 {
            if mascot.x >= ctrl.dockLeft && mascot.x <= ctrl.dockRight {
                mascot.y = ctrl.dockFloorY
                if abs(mascot.velocityY) < 80 {
                    mascot.velocityY = 0
                    mascot.velocityX = 0
                    mascot.isThrown = false
                    mascot.level = .dock
                    mascot.landingShakeTimer = 0.25
                    mascot.setExpression(.happy, duration: 1.5)
                    ctrl.stateMachine.forceTransition(to: StateKey.idle, mascot: mascot)
                    ctrl.particleSystem?.emitDust(at: CGPoint(x: mascot.x, y: mascot.y), count: 5)
                    return
                }
                mascot.velocityY = abs(mascot.velocityY) * bounceDamping
            }
        }

        // Visual: rotation based on velocity
        let speed = sqrt(mascot.velocityX * mascot.velocityX + mascot.velocityY * mascot.velocityY)
        let spin = atan2(mascot.velocityY, mascot.velocityX)
        ctrl.claudeView.rotation = mascot.velocityX > 0 ? spin * 0.1 : -spin * 0.1

        // Airborne stretch: elongated in direction of travel
        ctrl.claudeView.currentLegs = mascot.velocityY > 0 ? legsRising : legsFalling
        ctrl.claudeView.armsRaised = true
        ctrl.claudeView.scaleX = 0.92
        ctrl.claudeView.scaleY = 1.10

        if speed > 600 {
            mascot.setExpression(.dizzy)
        }
    }

    func exit(mascot: MascotEntity) {
        mascot.isThrown = false
        mascot.velocityX = 0
        mascot.velocityY = 0
        // Don't snap scale/rotation — let update loop smooth them back
    }
}

// MARK: - Wall Climb State (climbing sides of windows, hanging)

final class WallClimbState: MascotStateProtocol {
    weak var controller: AppController?
    var canBeInterrupted: Bool { true }

    private var hangTimer: CGFloat = 0
    private var hangDuration: CGFloat = 0
    private var legTimer: CGFloat = 0
    private var windowFrame: NSRect = .zero

    func enter(mascot: MascotEntity) {
        hangTimer = 0
        hangDuration = CGFloat.random(in: 4...12)
        legTimer = 0
        mascot.level = .window

        guard let ctrl = controller, let petWin = ctrl.petWindowFrame else { return }
        windowFrame = petWin

        // Rotate to cling to wall
        let side = mascot.wallSide
        ctrl.claudeView.rotation = side < 0 ? -CGFloat.pi / 2 : CGFloat.pi / 2
        ctrl.claudeView.facingRight = true
        ctrl.claudeView.armsRaised = true
        ctrl.claudeView.currentLegs = legsWalk

        // Snap X to window edge
        mascot.x = side < 0 ? windowFrame.minX : windowFrame.maxX
    }

    func update(dt: CGFloat, mascot: MascotEntity) {
        guard let ctrl = controller else { return }

        // Check window still exists — if closed/moved, fall off
        let windowExists = ctrl.visibleWindowFrames.contains {
            abs($0.origin.x - windowFrame.origin.x) < 10 && abs($0.origin.y - windowFrame.origin.y) < 10
        }
        if !windowExists {
            mascot.velocityX = 0
            mascot.velocityY = 100
            mascot.setExpression(.surprised)
            ctrl.stateMachine.forceTransition(to: StateKey.thrown, mascot: mascot)
            return
        }

        let climbSpeed: CGFloat = 280

        // Keep X snapped to wall side
        mascot.x = mascot.wallSide < 0 ? windowFrame.minX : windowFrame.maxX

        if mascot.wallClimbDir != 0 {
            // Moving up or down
            mascot.y += mascot.wallClimbDir * climbSpeed * dt

            // Leg animation while climbing
            legTimer += dt
            if legTimer > 0.1 {
                ctrl.claudeView.legFrame = ctrl.claudeView.legFrame == 0 ? 1 : 0
                ctrl.claudeView.currentLegs = ctrl.claudeView.legFrame == 0 ? legsIdle : legsWalk
                legTimer = 0
            }

            // Reached top of window → transition to standing on top
            if mascot.wallClimbDir > 0 && mascot.y >= ctrl.computeWindowFloorY(for: windowFrame) {
                mascot.y = ctrl.computeWindowFloorY(for: windowFrame)
                mascot.wallSide = 0
                mascot.wallClimbDir = 0
                ctrl.claudeView.rotation = 0
                ctrl.claudeView.armsRaised = false
                ctrl.petWindowFrame = windowFrame
                ctrl.petWindowFloorY = ctrl.computeWindowFloorY(for: windowFrame)
                mascot.setExpression(.happy, duration: 1.0)
                ctrl.stateMachine.forceTransition(to: StateKey.idle, mascot: mascot)
                return
            }

            // Reached bottom → transition to ground
            if mascot.wallClimbDir < 0 && mascot.y <= ctrl.groundFloorY {
                mascot.y = ctrl.groundFloorY
                mascot.level = .ground
                mascot.wallSide = 0
                mascot.wallClimbDir = 0
                ctrl.claudeView.rotation = 0
                ctrl.claudeView.armsRaised = false
                ctrl.petWindowFrame = nil
                ctrl.stateMachine.forceTransition(to: StateKey.idle, mascot: mascot)
                return
            }
        } else {
            // Hanging in place
            hangTimer += dt
            ctrl.claudeView.currentLegs = legsIdle
            ctrl.claudeView.armsRaised = true

            // Slow leg swing while hanging
            legTimer += dt
            if legTimer > 0.4 {
                ctrl.claudeView.legFrame = ctrl.claudeView.legFrame == 0 ? 1 : 0
                ctrl.claudeView.currentLegs = ctrl.claudeView.legFrame == 0 ? legsIdle : legsWalk
                legTimer = 0
            }

            // After hang duration, decide next action
            if hangTimer >= hangDuration {
                let roll = Float.random(in: 0...1)
                if roll < 0.4 {
                    mascot.wallClimbDir = 1   // climb up
                } else if roll < 0.7 {
                    mascot.wallClimbDir = -1  // climb down
                } else {
                    // Fall off
                    mascot.wallSide = 0
                    mascot.wallClimbDir = 0
                    mascot.velocityX = CGFloat(mascot.wallSide) * -80
                    mascot.velocityY = 50
                    mascot.setExpression(.surprised, duration: 1.0)
                    ctrl.claudeView.rotation = 0
                    ctrl.stateMachine.forceTransition(to: StateKey.thrown, mascot: mascot)
                    return
                }
                hangTimer = 0
                hangDuration = CGFloat.random(in: 3...8)
            }
        }

        ctrl.positionSprite()
    }

    func exit(mascot: MascotEntity) {
        mascot.wallClimbDir = 0
        controller?.claudeView.rotation = 0
        controller?.claudeView.armsRaised = false
    }
}
