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
}

// MARK: - Idle State

final class IdleState: MascotStateProtocol {
    weak var controller: AppController?
    var blinkTimer: CGFloat = 0

    func enter(mascot: MascotEntity) {
        mascot.jumpPhase = .none
        blinkTimer = 0
    }

    func update(dt: CGFloat, mascot: MascotEntity) {
        guard let ctrl = controller else { return }

        let now = CACurrentMediaTime()
        let idleTime = now - mascot.lastActivityTime

        // Check transitions
        if mascot.isSeekingApples {
            ctrl.stateMachine.transition(to: StateKey.seekingApple, mascot: mascot)
            return
        }

        if idleTime > mascot.sleepDelay && !mascot.isAsleep {
            // Transition to sleeping
            let sleepSpeed: CGFloat = 1.5
            ctrl.claudeView.eyeClose += (1 - ctrl.claudeView.eyeClose) * min(1, sleepSpeed * dt)
            ctrl.claudeView.sitAmount += (1 - ctrl.claudeView.sitAmount) * min(1, sleepSpeed * dt)
            if ctrl.claudeView.eyeClose > 0.95 && ctrl.claudeView.sitAmount > 0.95 {
                mascot.isAsleep = true
                ctrl.stateMachine.transition(to: StateKey.sleeping, mascot: mascot)
                return
            }
        } else if idleTime > mascot.drowsyDelay {
            // Drowsy — blink cycle
            blinkTimer += dt
            let blinkCycle = blinkTimer.truncatingRemainder(dividingBy: 0.8)
            if blinkCycle < 0.12 {
                ctrl.claudeView.eyeClose = min(max(ctrl.claudeView.eyeClose, 0.85), 1)
            } else {
                ctrl.claudeView.eyeClose = max(ctrl.claudeView.eyeClose - dt * 8, 0)
            }
            ctrl.claudeView.sitAmount = max(ctrl.claudeView.sitAmount - dt * 6, 0)
            mascot.setExpression(.sleepy)
        } else {
            blinkTimer = 0
            ctrl.claudeView.eyeClose = max(ctrl.claudeView.eyeClose - dt * 6, 0)
            ctrl.claudeView.sitAmount = max(ctrl.claudeView.sitAmount - dt * 6, 0)
            if mascot.effectiveExpression == .sleepy {
                mascot.setExpression(.neutral)
            }
        }

        // Check if we should start walking (mouse target)
        if mascot.autoTargetX != nil {
            ctrl.stateMachine.transition(to: StateKey.walking, mascot: mascot)
            return
        }

        // Visual updates
        ctrl.claudeView.legFrame = 0
        ctrl.claudeView.currentLegs = legsIdle
        ctrl.claudeView.armsRaised = false
    }

    func exit(mascot: MascotEntity) {
        blinkTimer = 0
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
    let gravity: CGFloat = -1800
    let airResistanceX: CGFloat = 0.04  // Shimeji-style air resistance
    let airResistanceY: CGFloat = 0.08
    let bounceDamping: CGFloat = 0.5
    let frictionX: CGFloat = 0.98
    var canBeInterrupted: Bool { false }

    func enter(mascot: MascotEntity) {
        mascot.isThrown = true
        mascot.isAsleep = false
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

        // Screen edge bounce
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

        // Window top collision — land on active window
        if let winFrame = ctrl.activeWindowFrame, mascot.velocityY < 0 {
            let winFloor = ctrl.computeWindowFloorY(for: winFrame)
            let onWindowX = mascot.x >= winFrame.minX && mascot.x <= winFrame.maxX
            // Falling through the window top border
            if onWindowX && mascot.y <= winFloor + 5 && mascot.y > winFloor - 20 {
                mascot.y = winFloor
                if abs(mascot.velocityY) < 120 && abs(mascot.velocityX) < 60 {
                    // Land on window
                    mascot.velocityY = 0
                    mascot.velocityX = 0
                    mascot.isThrown = false
                    mascot.level = .window
                    ctrl.windowFloorY = winFloor
                    mascot.landingShakeTimer = 0.2
                    mascot.setExpression(.happy, duration: 1.5)
                    ctrl.stateMachine.forceTransition(to: StateKey.idle, mascot: mascot)
                    ctrl.particleSystem?.emitDust(at: CGPoint(x: mascot.x, y: mascot.y), count: 5)
                    return
                }
                // Bounce off window
                mascot.velocityY = abs(mascot.velocityY) * bounceDamping * 0.6
                ctrl.particleSystem?.emitDust(at: CGPoint(x: mascot.x, y: mascot.y), count: 2)
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
