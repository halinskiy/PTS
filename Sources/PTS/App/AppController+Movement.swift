import Cocoa

extension AppController {
    func updateDisplayedLookDirection(from rawLook: CGFloat) {
        let enterThreshold: CGFloat = 0.38
        let exitThreshold: CGFloat = 0.18

        switch eyeLookStep {
        case 1:
            if rawLook < exitThreshold {
                eyeLookStep = 0
            }
        case -1:
            if rawLook > -exitThreshold {
                eyeLookStep = 0
            }
        default:
            if rawLook > enterThreshold {
                eyeLookStep = 1
            } else if rawLook < -enterThreshold {
                eyeLookStep = -1
            } else {
                eyeLookStep = 0
            }
        }

        claudeView.lookDir = eyeLookStep
    }

    func updateLookDirection(dt: CGFloat, fallbackX: CGFloat, smoothing: CGFloat = 14) {
        let targetLook: CGFloat
        let dx = lookTargetX(fallback: fallbackX) - crabX
        let maxDist: CGFloat = 300
        let closeRangeEyeDeadzone: CGFloat = 8
        let effectiveDX = abs(dx) <= closeRangeEyeDeadzone ? 0 : dx
        var directionalLook = max(-1, min(1, effectiveDX / maxDist))
        if !claudeView.facingRight {
            directionalLook *= -1
        }
        targetLook = directionalLook

        let blend = min(1, smoothing * dt)
        lookDirVelocity = (targetLook - rawLookDir) * blend
        rawLookDir += lookDirVelocity
        updateDisplayedLookDirection(from: rawLookDir)
    }

    func update() {
        let now = CACurrentMediaTime()
        let dt = CGFloat(now - lastTime)
        lastTime = now
        debugSnapshot(now: now)

        updateApples(dt)

        // Particle system update
        particleSystem?.update(dt: dt)

        // --- Dynamic mouse interaction toggle ---
        // Enable mouse events on our window ONLY when cursor is near the mascot
        // or an apple.  This lets clicks pass through everywhere else.
        updateMouseInteractivity()

        // Expression animation phase
        claudeView.expressionAnimPhase += dt * (mascot.effectiveExpression.style.animationSpeed)
        if claudeView.expressionAnimPhase > 1 { claudeView.expressionAnimPhase -= 1 }
        claudeView.expression = mascot.effectiveExpression
        mascot.updateExpression(dt: dt)

        if now - lastDockCheck > dockCheckInterval {
            lastDockCheck = now
            refreshDockBounds()
        }

        // Window tracking — use AXObserver with polling fallback
        if now - lastWindowCheck > windowCheckInterval {
            lastWindowCheck = now
            windowTracker.pollUpdate()
        }

        if !dockVisible {
            lastActivityTime = now
            return
        }

        // Mood system update
        if now - lastMoodUpdateTime > moodUpdateInterval {
            lastMoodUpdateTime = now
            systemContext.typingSpeed = systemMonitor.typingSpeed
            systemContext.cpuUsage = systemMonitor.cpuUsage
            systemContext.isIdle = systemMonitor.isIdle
            systemContext.recentInteractions = recentInteractionCount
            systemContext.applesEatenRecently = applesEatenThisFrame
            systemContext.screenshotDetected = systemMonitor.screenshotDetected
            moodSystem.update(dt: Float(moodUpdateInterval), context: systemContext)
            applesEatenThisFrame = 0
            recentInteractionCount = max(0, recentInteractionCount - 0.1)

            // Apply mood to walk speed
            let moodMultiplier = moodSystem.overallMood.walkSpeedMultiplier
            mascot.walkSpeed = 200 * CGFloat(moodMultiplier)

            // Mood-based idle expression (only if no active expression)
            if mascot.expressionDuration == 0 && mascot.currentExpression == .neutral {
                let moodExpr = moodSystem.overallMood.preferredExpression
                if moodExpr != .neutral {
                    mascot.setExpression(moodExpr)
                }
            }
        }

        // Sleep Z particles
        if isAsleep && now - lastParticleZTime > 1.5 {
            lastParticleZTime = now
            particleSystem?.emitSleepZ(at: CGPoint(x: crabX, y: crabY + spriteH * 0.8))
        }

        // Window inertia: horizontal slide when window moves fast
        if abs(windowInertiaVelocity.dx) > 0.5 {
            crabX += windowInertiaVelocity.dx * dt
            windowInertiaVelocity.dx *= windowInertiaDecay
            if abs(windowInertiaVelocity.dx) < 0.5 { windowInertiaVelocity.dx = 0 }
        }

        let mouseLocation = NSEvent.mouseLocation
        let mouseX = mouseLocation.x

        // If mascot is being dragged or thrown, run state machine and skip normal movement
        if mascot.isDragged || mascot.isThrown {
            stateMachine.update(dt: dt, mascot: mascot)
            positionSprite()
            return
        }

        if jumpPhase != .none {
            claudeView.isWalking = false
            claudeView.walkFacing = landingTravelDirection != 0 ? landingTravelDirection : jumpDirection
            updateJump(dt)
            updateVisuals(dt, isWalking: false)
            positionSprite()
            return
        }

        // Recovery pause after falling (alt-tab, window close, etc.)
        if mascot.recoveryTimer > 0 {
            mascot.recoveryTimer -= dt
            updateVisuals(dt, isWalking: false)
            updateLookDirection(dt: dt, fallbackX: mouseX, smoothing: 8)
            positionSprite()
            if mascot.recoveryTimer <= 0 {
                mascot.recoveryTimer = 0
                // After recovery, seek the active window
                if mascot.seekActiveWindow, let winFrame = activeWindowFrame {
                    mascot.seekActiveWindow = false
                    // Walk to the nearest edge of the active window
                    let nearestEdge = abs(crabX - winFrame.minX) < abs(crabX - winFrame.maxX)
                        ? winFrame.minX : winFrame.maxX
                    autoTargetX = nearestEdge
                    mascot.setExpression(.neutral)
                    lastActivityTime = now
                } else {
                    mascot.seekActiveWindow = false
                }
            }
            return
        }

        let timeSinceMove = now - lastMouseMoveTime
        if !isSeekingApples, let pending = pendingTargetX, abs(mouseX - pending) > 2 {
            lastMouseMoveTime = now
            mouseSettled = false
            if !isAsleep {
                lastActivityTime = now
                if claudeView.sitAmount > 0.1 {
                    wakingUp = true
                }
            }
        }
        pendingTargetX = mouseX

        if wakingUp && claudeView.sitAmount < 0.05 {
            wakingUp = false
        }

        if isAsleep {
            updateVisuals(dt, isWalking: false)
            positionSprite()
            return
        }

        if wakingUp {
            updateVisuals(dt, isWalking: false)
            updateLookDirection(dt: dt, fallbackX: mouseX, smoothing: 10)
            positionSprite()
            return
        }

        let minX = currentMinX()
        let maxX = currentMaxX()

        if isSeekingApples {
            lastActivityTime = now
            if now - appleSeekStartTime < appleSeekDelay {
                autoTargetX = nil
            } else if let appleX = currentAppleSeekTargetX() {
                autoTargetX = max(screenLeft, min(screenRight, appleX))
            } else if apples.isEmpty {
                endAppleSeek(now: now)
            } else {
                autoTargetX = nil
            }
        } else {
            if !mouseSettled && timeSinceMove > settleDelay {
                mouseSettled = true
                let targetX = max(screenLeft, min(screenRight, mouseX))
                if abs(targetX - crabX) > autoThresh * 2 {
                    autoTargetX = targetX
                }
            }

            if let target = autoTargetX, !mouseSettled {
                if abs(mouseX - target) > 80 {
                    autoTargetX = nil
                } else {
                    autoTargetX = max(screenLeft, min(screenRight, mouseX))
                }
            }
        }

        var isWalking = false
        var walkFacing: CGFloat = 0

        if let target = autoTargetX {
            var movementTarget = target
            let jumpOffMargin: CGFloat = 30
            let onDockArea = crabX >= dockLeft && crabX <= dockRight
            if level == .dock && onDockArea && (target < dockLeft || target > dockRight) {
                let exitDir: CGFloat = target < dockLeft ? -1 : 1
                let nearExitEdge = (exitDir < 0 && crabX <= dockLeft + jumpOffMargin)
                    || (exitDir > 0 && crabX >= dockRight - jumpOffMargin)
                if nearExitEdge {
                    debugLog(String(format: "jumpDown target=%.1f dir=%.0f x=%.1f dock=[%.1f,%.1f]", target, exitDir, crabX, dockLeft, dockRight))
                    startJump(down: true, direction: exitDir)
                    updateVisuals(dt, isWalking: false)
                    positionSprite()
                    return
                }
            }

            let shouldTransitionUpToDock = level == .ground && (
                (target >= dockLeft && target <= dockRight)
                    || (isSeekingApples && pathCrossesDockOnGround(from: crabX, to: target))
            )
            if shouldTransitionUpToDock {
                let entryDir = dockEntryDirection(for: target)
                let approachX = dockEntryApproachX(for: target)
                let jumpMargin: CGFloat = 50
                let underDock = crabX >= dockLeft && crabX <= dockRight
                let nearDockEntry = abs(crabX - approachX) <= jumpMargin
                if nearDockEntry {
                    debugLog(String(format: "jumpUp target=%.1f entryDir=%.0f x=%.1f approachX=%.1f dock=[%.1f,%.1f]", target, entryDir, crabX, approachX, dockLeft, dockRight))
                    startJump(down: false, direction: entryDir)
                    updateVisuals(dt, isWalking: false)
                    positionSprite()
                    return
                }
                if underDock {
                    debugLog(String(format: "underDock reroute target=%.1f approachX=%.1f entryDir=%.0f x=%.1f", target, approachX, entryDir, crabX))
                    movementTarget = approachX
                    autoTargetX = approachX
                }
            }

            // Window Climbing Detection — climb if target is ON the window
            if let winFrame = activeWindowFrame, (level == .ground || level == .dock) {
                let targetOnWindow = target >= winFrame.minX && target <= winFrame.maxX
                if targetOnWindow {
                    let sideMargin: CGFloat = 25
                    let nearLeft = abs(crabX - winFrame.minX) <= sideMargin
                    let nearRight = abs(crabX - winFrame.maxX) <= sideMargin

                    if nearLeft || nearRight {
                        startClimbing(onLeft: nearLeft)
                        updateVisuals(dt, isWalking: false)
                        positionSprite()
                        return
                    }

                    let nearWindow = crabX >= winFrame.minX - 60 && crabX <= winFrame.maxX + 60
                    if nearWindow {
                        let entryDir: CGFloat = target < crabX ? -1 : 1
                        startJumpToWindow(frame: winFrame, direction: entryDir)
                        updateVisuals(dt, isWalking: false)
                        positionSprite()
                        return
                    }
                }
            }

            if level == .window, let winFrame = activeWindowFrame {
                if target < winFrame.minX || target > winFrame.maxX {
                    let exitDir: CGFloat = target < winFrame.minX ? -1 : 1
                    startJump(down: true, direction: exitDir)
                    updateVisuals(dt, isWalking: false)
                    positionSprite()
                    return
                }
            }

            let dx = movementTarget - crabX
            if abs(dx) > autoThresh {
                let dir: CGFloat = dx > 0 ? 1 : -1
                let activeWalkSpeed = isSeekingApples ? mascot.walkSpeed * 1.6 : mascot.walkSpeed
                let nextX = crabX + dir * min(activeWalkSpeed * dt, abs(dx))

                if level == .dock && onDockArea
                    && (nextX < dockLeft + jumpOffMargin || nextX > dockRight - jumpOffMargin)
                    && (target < dockLeft || target > dockRight) {
                    debugLog(String(format: "jumpDown target=%.1f dir=%.0f nextX=%.1f dock=[%.1f,%.1f]", target, dir, nextX, dockLeft, dockRight))
                    startJump(down: true, direction: dir)
                    updateVisuals(dt, isWalking: false)
                    positionSprite()
                    return
                }

                if shouldStartAppleHop(remainingDistance: abs(dx), direction: dir) {
                    debugLog(String(format: "appleHop target=%.1f dir=%.0f x=%.1f", target, dir, crabX))
                    startHop(direction: dir)
                    updateVisuals(dt, isWalking: false)
                    positionSprite()
                    return
                }

                crabX = nextX
                claudeView.facingRight = dir > 0
                walkFacing = dir
                isWalking = true

                // Emit sparks when running fast (seeking apples)
                if isSeekingApples && Int.random(in: 0..<8) == 0 {
                    particleSystem?.emitSparks(
                        at: CGPoint(x: crabX, y: crabY + 4),
                        direction: dir
                    )
                }

                if crabX >= minX && crabX <= maxX {
                    crabX = max(minX, min(maxX, crabX))
                }

                if abs(crabX - target) <= autoThresh {
                    crabX = max(minX, min(maxX, movementTarget))
                    autoTargetX = nil
                }
            } else {
                crabX = max(minX, min(maxX, movementTarget))
                autoTargetX = nil
            }
        }

        claudeView.isWalking = isWalking
        claudeView.walkFacing = walkFacing
        if isWalking {
            lastActivityTime = now
        }

        // Hover: faster eye tracking when hovered
        let lookSmoothing: CGFloat = mascot.isHovered ? 22 : 14
        updateLookDirection(dt: dt, fallbackX: mouseX, smoothing: lookSmoothing)

        // Landing shake: oscillate look direction after hard landing
        if mascot.landingShakeTimer > 0 {
            mascot.landingShakeTimer -= dt
            let shakeFreq: CGFloat = 20
            let shakeAmp = mascot.landingShakeTimer / 0.3
            rawLookDir = sin(mascot.landingShakeTimer * shakeFreq) * shakeAmp
            updateDisplayedLookDirection(from: rawLookDir)
        }

        updateVisuals(dt, isWalking: isWalking)

        // Hover reaction: subtle body perk + curious expression after sustained hover
        if mascot.isHovered && !mascot.isDragged && !mascot.isThrown && jumpPhase == .none && !mascot.isSqueezing {
            mascot.hoverIntensity = min(1, mascot.hoverIntensity + dt * 4)
            claudeView.bodyBob += mascot.hoverIntensity * SCALE * 0.3
            // After hovering 0.8s, show curious expression
            if CACurrentMediaTime() - mascot.hoverStartTime > 0.8 {
                if mascot.effectiveExpression == .neutral {
                    mascot.setExpression(.thinking, duration: 0)
                }
            }
        } else {
            mascot.hoverIntensity = max(0, mascot.hoverIntensity - dt * 3)
            // Clear hover expression
            if mascot.effectiveExpression == .thinking && !mascot.isHovered {
                mascot.setExpression(.neutral)
            }
        }

        // Squeeze animation: squish down while holding mouse on mascot
        if mascot.isSqueezing {
            let elapsed = CGFloat(CACurrentMediaTime() - mascot.squeezeStartTime)
            let t = min(1, elapsed / 0.15)
            claudeView.scaleX = 1 + 0.12 * t
            claudeView.scaleY = 1 - 0.10 * t
            claudeView.currentLegs = legsSquish
        }

        // Window stickiness: if on window, follow its movement
        if level == .window, let winFrame = activeWindowFrame {
            crabY = windowFloorY
            if crabX < winFrame.minX - 2 { crabX = winFrame.minX - 2 }
            if crabX > winFrame.maxX + 2 { crabX = winFrame.maxX + 2 }
        }

        positionSprite()
    }


    func startClimbing(onLeft: Bool) {
        debugLog(String(format: "startClimbing onLeft=%@ x=%.1f y=%.1f", onLeft.description, crabX, crabY))
        jumpPhase = .climbing
        jumpTimer = 0
        climbingOnLeft = onLeft
        jumpStartY = crabY
        windowTracker.pollUpdate()
        if let frame = windowTracker.currentFrame {
            activeWindowFrame = frame
            windowFloorY = computeWindowFloorY(for: frame)
        }
        jumpEndY = windowFloorY
        claudeView.facingRight = true
        claudeView.rotation = onLeft ? -CGFloat.pi / 2 : CGFloat.pi / 2
        claudeView.currentLegs = legsWalk

        if let frame = activeWindowFrame {
            crabX = onLeft ? frame.minX : frame.maxX
        }
    }

    func startJumpToWindow(frame: NSRect, direction: CGFloat) {
        debugLog(String(format: "startJumpToWindow dir=%.0f from=(%.1f,%.1f) toY=%.1f", direction, crabX, crabY, windowFloorY))
        jumpPhase = .squish
        jumpTimer = 0
        jumpStartY = crabY
        jumpEndY = windowFloorY
        jumpDirection = direction
        currentJumpHorizontalDistance = jumpHorizontalDistance
        landingTravelDirection = direction
        autoTargetX = nil
        claudeView.facingRight = direction > 0
    }

    func startJump(down: Bool, direction: CGFloat) {
        debugLog(String(format: "startJump down=%@ dir=%.0f from=(%.1f,%.1f) toY=%.1f", down.description, direction, crabX, crabY, down ? groundFloorY : dockFloorY))
        jumpPhase = .squish
        jumpTimer = 0
        jumpStartY = crabY
        jumpEndY = down ? groundFloorY : dockFloorY
        jumpDirection = direction
        currentJumpHorizontalDistance = jumpHorizontalDistance
        landingTravelDirection = direction
        autoTargetX = nil
        claudeView.facingRight = direction > 0
    }

    func startHop(direction: CGFloat) {
        debugLog(String(format: "startHop dir=%.0f from=(%.1f,%.1f)", direction, crabX, crabY))
        jumpPhase = .squish
        jumpTimer = 0
        jumpStartY = crabY
        jumpEndY = crabY
        jumpDirection = direction
        currentJumpHorizontalDistance = jumpHorizontalDistance
        landingTravelDirection = direction
        autoTargetX = nil
        claudeView.facingRight = direction > 0
    }

    func startInPlaceJump() {
        jumpPhase = .squish
        jumpTimer = 0
        jumpStartY = crabY
        jumpEndY = crabY
        jumpDirection = claudeView.facingRight ? 1 : -1
        currentJumpHorizontalDistance = 0
        landingTravelDirection = 0
    }

    func smoothstep(_ t: CGFloat) -> CGFloat {
        let clamped = max(0, min(1, t))
        return clamped * clamped * (3 - 2 * clamped)
    }

    func updateJump(_ dt: CGFloat) {
        jumpTimer += dt

        switch jumpPhase {
        case .squish:
            if jumpTimer >= squishDur {
                jumpPhase = .airborne
                jumpTimer = 0
            }
            let t = jumpTimer / squishDur
            claudeView.scaleX = 1 + 0.18 * t
            claudeView.scaleY = 1 - 0.18 * t
            claudeView.currentLegs = legsSquish
            claudeView.armsRaised = false

        case .climbing:
            let climbSpeed: CGFloat = 400
            crabY += climbSpeed * dt

            if let frame = activeWindowFrame {
                crabX = climbingOnLeft ? frame.minX : frame.maxX
            }

            walkTimer += dt
            if walkTimer > 0.08 {
                claudeView.legFrame = claudeView.legFrame == 0 ? 1 : 0
                walkTimer = 0
            }
            claudeView.currentLegs = claudeView.legFrame == 0 ? legsIdle : legsWalk
            claudeView.armsRaised = true

            if crabY >= jumpEndY {
                crabY = jumpEndY
                jumpPhase = .none
                level = .window
                claudeView.armsRaised = false
                claudeView.currentLegs = legsIdle
                claudeView.rotation = 0
                mascot.setExpression(.happy, duration: 1.0)
            }

        case .airborne:
            let t = min(1, jumpTimer / airDur)
            let linearY = jumpStartY + (jumpEndY - jumpStartY) * t
            let arc = 4 * jumpArcHeight * t * (1 - t)
            crabY = linearY + arc

            crabX += jumpDirection * (currentJumpHorizontalDistance / airDur) * dt
            crabX = max(screenLeft, min(screenRight, crabX))

            if t < 0.5 {
                claudeView.currentLegs = legsRising
                claudeView.armsRaised = true
                claudeView.scaleX = 0.88
                claudeView.scaleY = 1.18
            } else {
                claudeView.currentLegs = legsFalling
                claudeView.armsRaised = false
                claudeView.scaleX = 0.92
                claudeView.scaleY = 1.10
            }

            if t >= 1 {
                crabY = jumpEndY
                jumpPhase = .land
                jumpTimer = 0
                if jumpEndY == dockFloorY {
                    level = .dock
                } else if jumpEndY == windowFloorY && activeWindowFrame != nil {
                    level = .window
                } else {
                    level = .ground
                }
            }

        case .land:
            if jumpTimer >= landDur {
                jumpPhase = .none
                jumpTimer = 0
                crabY = jumpEndY
                claudeView.scaleX = 1
                claudeView.scaleY = 1
                claudeView.currentLegs = legsIdle
                claudeView.armsRaised = false
                landingTravelDirection = 0
                settleTimer = 0
                mouseSettled = false
                lastMouseMoveTime = CACurrentMediaTime()
                // Landing dust
                particleSystem?.emitDust(at: CGPoint(x: crabX, y: crabY), count: 4)
                return
            }

            let landT = min(1, jumpTimer / landDur)
            let impactT = smoothstep(min(1, landT / 0.42))
            let recoveryT = smoothstep(max(0, (landT - 0.42) / 0.58))
            let movingLanding = landingTravelDirection != 0

            crabY = jumpEndY
            claudeView.scaleX = 1 + 0.22 * impactT - 0.10 * recoveryT
            claudeView.scaleY = 1 - 0.24 * impactT + 0.10 * recoveryT
            if landT < 0.42 {
                claudeView.currentLegs = legsLand
            } else if landT < 0.78 {
                claudeView.currentLegs = legsLandRecover
            } else {
                claudeView.currentLegs = movingLanding ? legsWalk : legsIdle
            }
            claudeView.armsRaised = false

        case .none:
            break
        }

        let look: CGFloat
        if currentJumpHorizontalDistance == 0 {
            look = 0
        } else {
            var jumpLook: CGFloat = jumpDirection > 0 ? 1 : -1
            if !claudeView.facingRight {
                jumpLook *= -1
            }
            look = jumpLook
        }
        rawLookDir = look
        lookDirVelocity = 0
        eyeLookStep = look == 0 ? 0 : (look > 0 ? 1 : -1)
        claudeView.lookDir = eyeLookStep
    }

    func updateVisuals(_ dt: CGFloat, isWalking: Bool) {
        let targetLegYBob: CGFloat
        let settling = !isWalking && settleTimer > 0 && jumpPhase == .none

        if (isWalking || settling) && jumpPhase == .none {
            if isWalking {
                settleTimer = settleDuration
            } else {
                settleTimer -= dt
            }

            let cycleSpeed: CGFloat = settling ? 0.20 : 0.15
            walkTimer += dt
            if walkTimer > cycleSpeed {
                claudeView.legFrame = claudeView.legFrame == 0 ? 1 : 0
                walkTimer = 0
                if settling && claudeView.legFrame == 0 {
                    settleTimer = 0
                }
            }
            claudeView.currentLegs = claudeView.legFrame == 0 ? legsIdle : legsWalk
            claudeView.armsRaised = false
            targetLegYBob = claudeView.legFrame == 1 ? SCALE * 0.4 : 0
        } else if jumpPhase == .none {
            claudeView.legFrame = 0
            walkTimer = 0
            settleTimer = 0
            claudeView.armsRaised = false

            let now = CACurrentMediaTime()
            let idleTime = now - lastActivityTime
            let isDrowsy = idleTime > drowsyDelay && idleTime <= sleepDelay
            let isSleeping = idleTime > sleepDelay

            if isDrowsy {
                blinkTimer += dt
                let blinkCycle = blinkTimer.truncatingRemainder(dividingBy: 0.8)
                if blinkCycle < 0.12 {
                    claudeView.eyeClose = min(max(claudeView.eyeClose, 0.85), 1)
                } else {
                    claudeView.eyeClose = max(claudeView.eyeClose - dt * 8, 0)
                }
                claudeView.sitAmount = max(claudeView.sitAmount - dt * 6, 0)
            } else if isSleeping || isAsleep {
                blinkTimer = 0

                if !isAsleep {
                    let sleepSpeed: CGFloat = 1.5
                    claudeView.eyeClose += (1 - claudeView.eyeClose) * min(1, sleepSpeed * dt)
                    claudeView.sitAmount += (1 - claudeView.sitAmount) * min(1, sleepSpeed * dt)
                    if claudeView.eyeClose > 0.95 && claudeView.sitAmount > 0.95 {
                        isAsleep = true
                    }
                }

                if isAsleep {
                    claudeView.eyeClose = 1
                    claudeView.sitAmount = 1
                }
            } else {
                blinkTimer = 0
                claudeView.eyeClose = max(claudeView.eyeClose - dt * 6, 0)
                claudeView.sitAmount = max(claudeView.sitAmount - dt * 6, 0)
            }

            claudeView.currentLegs = legsIdle
            targetLegYBob = -2 * SCALE * claudeView.sitAmount
        } else {
            targetLegYBob = 0
        }

        let smoothSpeed: CGFloat = 6
        claudeView.legYBob += (targetLegYBob - claudeView.legYBob) * min(1, smoothSpeed * dt)

        if jumpPhase != .airborne {
            let breatheSpeed: CGFloat = claudeView.sitAmount > 0.5 ? 0.6 : 1.0
            breatheTimer += dt * breatheSpeed
        }
        let bob = jumpPhase == .airborne ? 0 :
            max(0, sin(breatheTimer * CGFloat.pi * 2 / 1.2)) * SCALE * 0.2
        claudeView.bodyBob = round(bob)

        // Smooth scale & rotation recovery (after throw, squeeze, etc.)
        // Only when not in a special animation state that sets its own scale
        if jumpPhase == .none && !mascot.isDragged && !mascot.isThrown && !mascot.isSqueezing {
            let recoverySpeed: CGFloat = 10
            claudeView.scaleX += (1 - claudeView.scaleX) * min(1, recoverySpeed * dt)
            claudeView.scaleY += (1 - claudeView.scaleY) * min(1, recoverySpeed * dt)
            claudeView.rotation += (0 - claudeView.rotation) * min(1, recoverySpeed * dt)
            // Snap when close enough to avoid endless micro-adjustments
            if abs(claudeView.scaleX - 1) < 0.005 { claudeView.scaleX = 1 }
            if abs(claudeView.scaleY - 1) < 0.005 { claudeView.scaleY = 1 }
            if abs(claudeView.rotation) < 0.005 { claudeView.rotation = 0 }
        }

        // Subtle idle sway (not during sleep/walk/special states)
        if jumpPhase == .none && !mascot.isDragged && !mascot.isThrown && !isWalking && !isAsleep && !wakingUp {
            let sway = sin(breatheTimer * 0.7) * 0.015
            claudeView.rotation = sway // set, not accumulate
        }
    }

    func positionSprite() {
        claudeView.frame.origin.x = crabX - spriteW / 2
        claudeView.frame.origin.y = crabY
        claudeView.needsDisplay = true

        shadowView.frame.origin.x = crabX - spriteW / 2
        shadowView.frame.origin.y = currentShadowFloorY() - SHADOW_FLOOR_MARGIN
        shadowView.facingRight = claudeView.facingRight
        shadowView.legRows = claudeView.currentLegs.count
        shadowView.needsDisplay = true
    }

    func currentShadowFloorY() -> CGFloat {
        if jumpPhase != .none {
            return min(jumpStartY, jumpEndY)
        }
        if level == .window { return windowFloorY }
        return level == .dock ? dockFloorY : groundFloorY
    }
}
