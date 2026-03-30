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
            // Keep accessibility menu state in sync
            updateAccessibilityMenuState()
        }

        // Window tracking — use AXObserver with polling fallback
        if now - lastWindowCheck > windowCheckInterval {
            lastWindowCheck = now
            windowTracker.pollUpdate()
            // Fallback: if AX didn't provide a window, use first visible window
            if activeWindowFrame == nil, let first = visibleWindowFrames.first {
                activeWindowFrame = first
                windowFloorY = computeWindowFloorY(for: first)
            }
        }

        // Refresh all visible window frames for thrown-state landing (5x/s)
        if now - lastVisibleWindowsCheck > 0.2 {
            lastVisibleWindowsCheck = now
            visibleWindowFrames = WindowInfo.getAllFrames()

            if level == .window && !mascot.isAsleep && !mascot.isThrown && jumpPhase == .none,
               let petWin = petWindowFrame {
                let windowStill = visibleWindowFrames.contains { f in
                    abs(f.origin.x - petWin.origin.x) < 5
                        && abs(f.origin.y - petWin.origin.y) < 5
                        && abs(f.width - petWin.width) < 5
                        && abs(f.height - petWin.height) < 5
                }
                if !windowStill {
                    mascot.velocityX = CGFloat.random(in: -150...150)
                    mascot.velocityY = 400
                    mascot.setExpression(.surprised)
                    mascot.noWindowLandingUntil = now + 1.5  // don't re-land on windows
                    windowClimbCooldown = now + 3.0
                    stateMachine.forceTransition(to: StateKey.thrown, mascot: mascot)
                }
            }
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

            // Apply mood + time-of-day to walk speed
            let moodMultiplier = moodSystem.overallMood.walkSpeedMultiplier
            let timeMultiplier = TimeOfDay.current.walkSpeedMultiplier
            mascot.walkSpeed = 200 * CGFloat(moodMultiplier) * CGFloat(timeMultiplier)

            // Mood-based idle expression (only if no active expression)
            if mascot.expressionDuration == 0 && mascot.currentExpression == .neutral {
                // Claude Code companion: occasionally look thoughtful when Claude is running
                if systemMonitor.isClaudeRunning && !mascot.isAsleep && Int.random(in: 0..<20) == 0 {
                    mascot.setExpression(.thinking, duration: 2.0)
                } else {
                    let moodExpr = moodSystem.overallMood.preferredExpression
                    if moodExpr != .neutral {
                        mascot.setExpression(moodExpr)
                    }
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

        // Cursor velocity tracking
        let cdx = mouseLocation.x - prevCursorX
        let cdy = mouseLocation.y - prevCursorY
        cursorSpeed = cursorSpeed * 0.7 + sqrt(cdx * cdx + cdy * cdy) / max(0.001, dt) * 0.3
        prevCursorX = mouseLocation.x
        prevCursorY = mouseLocation.y

        // Cursor reactions (only when awake and idle)
        if !mascot.isDragged && !mascot.isThrown && !mascot.isAsleep && jumpPhase == .none {
            let distToPet = sqrt(pow(mouseLocation.x - crabX, 2) + pow(mouseLocation.y - crabY - spriteH * 0.5, 2))

            // Fast cursor flying past → surprised flinch
            if cursorSpeed > 2000 && distToPet < 120 && now - lastReactionTime > 2 {
                lastReactionTime = now
                mascot.setExpression(.surprised, duration: 0.8)
                let flinchDir: CGFloat = mouseLocation.x > crabX ? -0.06 : 0.06
                claudeView.rotation = flinchDir
            }

            // Cursor idle near pet → approach to "sniff"
            if distToPet < 150 && cursorSpeed < 30 {
                cursorIdleNearPetTimer += dt
                if cursorIdleNearPetTimer > 5 && autoTargetX == nil && !isSeekingApples {
                    let approachDir: CGFloat = mouseLocation.x > crabX ? 1 : -1
                    autoTargetX = mouseLocation.x - approachDir * 30
                    mascot.setExpression(.thinking, duration: 1.5)
                    cursorIdleNearPetTimer = -10 // cooldown
                }
            } else {
                cursorIdleNearPetTimer = max(0, cursorIdleNearPetTimer)
                if cursorSpeed > 50 { cursorIdleNearPetTimer = 0 }
            }
        }

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
        if let pending = pendingTargetX, abs(mouseX - pending) > 8 {
            if !isSeekingApples {
                lastMouseMoveTime = now
                mouseSettled = false
                if !isAsleep {
                    lastActivityTime = now
                    if claudeView.sitAmount > 0.1 {
                        wakingUp = true
                    }
                }
            }
            // Only very large mouse movements reset autonomous timer
            if abs(mouseX - pending) > 200 {
                if isAutonomousMode {
                    exitAutonomousMode(now: now)
                } else {
                    lastUserActivityTime = now
                }
            }
        }
        // Typing does NOT reset autonomous timer — pet roams while you work
        pendingTargetX = mouseX

        updateAutonomousMode(now: now)

        if wakingUp && claudeView.sitAmount < 0.05 {
            wakingUp = false
        }

        if isAsleep {
            // Wake up and scoot away if cursor lingers for 2s
            if mascot.isHovered && CACurrentMediaTime() - mascot.hoverStartTime > 2.0 {
                mascot.isAsleep = false
                mascot.wakingUp = true
                mascot.lastActivityTime = now
                mascot.setExpression(.surprised, duration: 1.5)
                let awayDir: CGFloat = mouseX >= crabX ? -1 : 1
                let minX = currentMinX()
                let maxX = currentMaxX()
                autoTargetX = awayDir < 0
                    ? max(minX, crabX - CGFloat.random(in: 180...320))
                    : min(maxX, crabX + CGFloat.random(in: 180...320))
                mascot.hoverStartTime = now
            }
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
            } else if let index = nearestAppleIndex() {
                // Always go straight to the apple — no dock routing, no detours
                autoTargetX = max(screenLeft, min(screenRight, apples[index].x))
            } else {
                endAppleSeek(now: now)
            }
        } else if !isAutonomousMode {
            // Stop ~80px to the side of the cursor so the mascot doesn't block clicks
            let cursorStopOffset: CGFloat = 80
            let approachDir: CGFloat = mouseX >= crabX ? 1 : -1
            let mouseTargetX = max(screenLeft, min(screenRight, mouseX - approachDir * cursorStopOffset))

            if !mouseSettled && timeSinceMove > settleDelay {
                mouseSettled = true
                if abs(mouseTargetX - crabX) > autoThresh * 2 {
                    autoTargetX = mouseTargetX
                }
            }

            if let target = autoTargetX, !mouseSettled {
                if abs(mouseX - target) > 120 {  // hysteresis: wider cancel zone
                    autoTargetX = nil
                }
            }
        }

        var isWalking = false
        var walkFacing: CGFloat = 0

        if let target = autoTargetX {
            var movementTarget = target
            let jumpOffMargin: CGFloat = 30
            let onDockArea = crabX >= dockLeft && crabX <= dockRight
            if !isSeekingApples && level == .dock && onDockArea && (target < dockLeft || target > dockRight) {
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

            // When seeking apples: only jump up if the apple is actually ON the dock.
            // Using target X alone causes a loop when the apple is on the ground
            // but happens to be horizontally inside the dock's range.
            let shouldTransitionUpToDock = !isSeekingApples && level == .ground && (
                target >= dockLeft && target <= dockRight
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

            // Window Climbing Detection — skip when chasing apple or in cooldown
            let skipClimb = (isSeekingApples && currentAppleSeekTargetLevel() != .window)
                || now < windowClimbCooldown
            if !skipClimb && (level == .ground || level == .dock) {
                // Only climb onto activeWindowFrame (frontmost, guaranteed current Space)
                var climbTarget: NSRect? = nil
                if let aw = activeWindowFrame, aw.width > 80, aw.height > 80,
                   target >= aw.minX && target <= aw.maxX {
                    climbTarget = aw
                }
                if let winFrame = climbTarget {
                    let sideMargin: CGFloat = 40
                    let nearLeft = abs(crabX - winFrame.minX) <= sideMargin
                    let nearRight = abs(crabX - winFrame.maxX) <= sideMargin

                    if nearLeft || nearRight {
                        activeWindowFrame = winFrame
                        windowFloorY = computeWindowFloorY(for: winFrame)
                        startClimbing(onLeft: nearLeft)
                        updateVisuals(dt, isWalking: false)
                        positionSprite()
                        return
                    }

                    let nearWindow = crabX >= winFrame.minX - 80 && crabX <= winFrame.maxX + 80
                    if nearWindow {
                        activeWindowFrame = winFrame
                        windowFloorY = computeWindowFloorY(for: winFrame)
                        let entryDir: CGFloat = target < crabX ? -1 : 1
                        startJumpToWindow(frame: winFrame, direction: entryDir)
                        updateVisuals(dt, isWalking: false)
                        positionSprite()
                        return
                    }
                }
            }

            if level == .window, let winFrame = petWindowFrame ?? activeWindowFrame {
                let appleOnLowerLevel = isSeekingApples && currentAppleSeekTargetLevel() != .window
                if target < winFrame.minX || target > winFrame.maxX || appleOnLowerLevel {
                    let exitDir: CGFloat = target < winFrame.minX ? -1 : (target > winFrame.maxX ? 1 : (crabX < winFrame.midX ? -1 : 1))
                    // Set cooldown — don't climb back for 3 seconds
                    windowClimbCooldown = now + 3.0

                    if !isSeekingApples && Float.random(in: 0...1) < 0.15 {
                        mascot.wallSide = exitDir < 0 ? -1 : 1
                        mascot.wallClimbDir = -1  // start going down
                        stateMachine.forceTransition(to: StateKey.wallClimb, mascot: mascot)
                        updateVisuals(dt, isWalking: false)
                        positionSprite()
                        return
                    }

                    // Try to hop directly to an adjacent window
                    if let adjWin = adjacentWindowForHop(from: winFrame, direction: exitDir) {
                        hopToWindow(adjWin, direction: exitDir)
                    } else {
                        startJump(down: true, direction: exitDir)
                    }
                    updateVisuals(dt, isWalking: false)
                    positionSprite()
                    return
                }
            }

            let dx = movementTarget - crabX
            if abs(dx) > autoThresh {
                let dir: CGFloat = dx > 0 ? 1 : -1
                let activeWalkSpeed = isSeekingApples ? mascot.walkSpeed * 1.6 : mascot.walkSpeed
                // Decelerate in the last 80px for smooth stopping (not during apple seek)
                let decelDistance: CGFloat = 80
                let decelFactor: CGFloat
                if isSeekingApples {
                    decelFactor = 1.0
                } else if abs(dx) < decelDistance {
                    decelFactor = max(0.15, abs(dx) / decelDistance)
                } else {
                    decelFactor = 1.0
                }
                let nextX = crabX + dir * min(activeWalkSpeed * decelFactor * dt, abs(dx))

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

                // Footprints every ~40px
                if Int(abs(crabX)) % 40 < 3 {
                    particleSystem?.emitFootprint(at: CGPoint(x: crabX, y: crabY))
                }

                // Screen wrapping (snake-style) on ground level
                if level == .ground {
                    if crabX < screenLeft - spriteW {
                        crabX = screenRight + spriteW * 0.5
                    } else if crabX > screenRight + spriteW {
                        crabX = screenLeft - spriteW * 0.5
                    }
                } else if crabX >= minX && crabX <= maxX {
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

        // Run state machine for idle/walking states (micro-animations, edge sitting, wall climb)
        if !isWalking && jumpPhase == .none {
            stateMachine.update(dt: dt, mascot: mascot)
        }

        // Hover reaction: subtle body perk + curious expression after sustained hover
        if mascot.isHovered && !mascot.isDragged && !mascot.isThrown && jumpPhase == .none && !mascot.isSqueezing {
            mascot.hoverIntensity = min(1, mascot.hoverIntensity + dt * 4)
            claudeView.bodyBob += mascot.hoverIntensity * SCALE * 0.3
            let hoverElapsed = CACurrentMediaTime() - mascot.hoverStartTime
            // After hovering 0.8s, show curious expression
            if hoverElapsed > 0.8 {
                if mascot.effectiveExpression == .neutral {
                    mascot.setExpression(.thinking, duration: 0)
                }
            }
            // After hovering 2s with no interaction → scoot away
            if hoverElapsed > 2.0 && autoTargetX == nil && !isSeekingApples && !isAsleep && !wakingUp {
                let awayDir: CGFloat = mouseX >= crabX ? -1 : 1
                let minX = currentMinX()
                let maxX = currentMaxX()
                let targetX = awayDir < 0
                    ? max(minX, crabX - CGFloat.random(in: 180...320))
                    : min(maxX, crabX + CGFloat.random(in: 180...320))
                autoTargetX = targetX
                mascot.setExpression(.surprised, duration: 1.2)
                mascot.hoverStartTime = now  // reset so it doesn't re-trigger immediately
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

        // Window stickiness
        if level == .window {
            crabY = petWindowFloorY
            if let petWin = petWindowFrame {
                if crabX < petWin.minX - 2 { crabX = petWin.minX - 2 }
                if crabX > petWin.maxX + 2 { crabX = petWin.maxX + 2 }
            }
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
                petWindowFrame = activeWindowFrame  // now on the frontmost window
                petWindowFloorY = windowFloorY
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
                    petWindowFrame = nil
                } else if jumpEndY == windowFloorY && activeWindowFrame != nil {
                    level = .window
                    petWindowFrame = activeWindowFrame   // landed on the frontmost window
                    petWindowFloorY = windowFloorY
                } else {
                    level = .ground
                    petWindowFrame = nil
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
                if level != .window { petWindowFrame = nil }
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

        // App-specific body language (overrides idle sway when active)
        if activeAppBehavior != .none && !isWalking && !isAsleep && jumpPhase == .none
            && !mascot.isDragged && !mascot.isThrown {
            appBehaviorTimer += dt
            if appBehaviorTimer < 30 { // active for 30s after app switch
                switch activeAppBehavior {
                case .watching:
                    claudeView.rotation = 0.03
                    claudeView.sitAmount += (0.3 - claudeView.sitAmount) * min(1, 3 * dt)
                case .coding:
                    // Fast "typing" leg alternation
                    let typeCycle = Int(appBehaviorTimer * 12)
                    claudeView.legFrame = typeCycle % 2
                    claudeView.currentLegs = claudeView.legFrame == 0 ? legsIdle : legsWalk
                    claudeView.sitAmount += (0.35 - claudeView.sitAmount) * min(1, 3 * dt)
                case .vibing:
                    claudeView.rotation = sin(breatheTimer * .pi) * 0.025
                default: break
                }
            } else {
                activeAppBehavior = .none
            }
        }
    }

    func positionSprite() {
        claudeView.frame.origin.x = crabX - spriteW / 2
        claudeView.frame.origin.y = crabY
        claudeView.needsDisplay = true

        shadowView.isHidden = true

        // Z-order: default visible. Only hide sleeping pet on background window.
        var shouldHide = false
        if mascot.isAsleep && level == .window, let petWin = petWindowFrame {
            let isTopWindow = visibleWindowFrames.prefix(2).contains {
                abs($0.midX - petWin.midX) < 60 && abs($0.midY - petWin.midY) < 60
            }
            if !isTopWindow { shouldHide = true }
        }
        // Awake pet on window obscured by foreground → fall
        if !shouldHide && level == .window && !mascot.isAsleep
            && !mascot.isDragged && !mascot.isThrown && jumpPhase == .none {
            if isPetObscuredByForegroundWindow() {
                mascot.velocityX = CGFloat.random(in: -60...60)
                mascot.velocityY = 400
                mascot.setExpression(.surprised)
                mascot.noWindowLandingUntil = CACurrentMediaTime() + 1.5
                windowClimbCooldown = CACurrentMediaTime() + 3.0
                stateMachine.forceTransition(to: StateKey.thrown, mascot: mascot)
            }
        }
        claudeView.alphaValue = shouldHide ? 0 : 1
    }

    /// Check if any visible window in front of the pet's window covers the pet's position.
    /// visibleWindowFrames is ordered front-to-back (from CGWindowListCopyWindowInfo).
    func isPetObscuredByForegroundWindow() -> Bool {
        guard level == .window || mascot.isThrown, let petWin = petWindowFrame else { return false }
        let petPoint = CGPoint(x: crabX, y: crabY + spriteH * 0.5)

        for f in visibleWindowFrames {
            // Found our window first → pet is on top, not obscured
            if abs(f.midX - petWin.midX) < 50 && abs(f.midY - petWin.midY) < 50
                && abs(f.width - petWin.width) < 50 {
                return false
            }
            // Another window covers the pet's position → obscured
            if f.contains(petPoint) {
                return true
            }
        }
        return false
    }

    func currentShadowFloorY() -> CGFloat {
        if jumpPhase != .none {
            return min(jumpStartY, jumpEndY)
        }
        if level == .window { return petWindowFloorY }
        return level == .dock ? dockFloorY : groundFloorY
    }

    // MARK: - Window-to-window hop

    /// Returns a nearby visible window in the given direction that the pet can hop to directly.
    func adjacentWindowForHop(from currentFrame: NSRect, direction: CGFloat) -> NSRect? {
        let maxHopDist: CGFloat = 460
        let maxHeightDiff: CGFloat = 260
        let currentFloor = computeWindowFloorY(for: currentFrame)

        // Only hop to activeWindowFrame (guaranteed current Space)
        guard let aw = activeWindowFrame, aw != currentFrame, aw.width > 60 else { return nil }
        let candidates = [aw].filter { f in
            guard f != currentFrame, f.width > 60 else { return false }
            // Window must be ahead in the right direction
            let gap: CGFloat = direction > 0
                ? f.minX - currentFrame.maxX
                : currentFrame.minX - f.maxX
            guard gap > -40 && gap < maxHopDist else { return false }
            // Not too far vertically
            return abs(computeWindowFloorY(for: f) - currentFloor) < maxHeightDiff
        }

        return candidates.min { a, b in
            let da = direction > 0 ? a.minX - currentFrame.maxX : currentFrame.minX - a.maxX
            let db = direction > 0 ? b.minX - currentFrame.maxX : currentFrame.minX - b.maxX
            return da < db
        }
    }

    /// Throw the pet from its current window toward an adjacent window.
    /// ThrownState physics + visibleWindowFrames will handle the actual landing.
    func hopToWindow(_ targetFrame: NSRect, direction: CGFloat) {
        let targetFloor = computeWindowFloorY(for: targetFrame)
        let heightDiff = targetFloor - crabY   // positive = target is higher

        // Horizontal velocity: scaled by distance
        let gap: CGFloat = direction > 0
            ? targetFrame.minX - (petWindowFrame?.maxX ?? crabX)
            : (petWindowFrame?.minX ?? crabX) - targetFrame.maxX
        let hopDist = max(60, gap + 60)
        mascot.velocityX = direction * max(350, hopDist * 5.5)

        // Vertical velocity: enough to clear the gap height + a small arc
        mascot.velocityY = max(220, 260 - heightDiff * 0.7)

        mascot.setExpression(.excited, duration: 1.2)
        stateMachine.forceTransition(to: StateKey.thrown, mascot: mascot)
    }
}
