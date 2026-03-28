import Cocoa
import Carbon.HIToolbox

extension AppController {
    @objc func feedApple() {
        guard window != nil else { return }
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame

        let appleView = AppleView(frame: NSRect(x: 0, y: 0, width: appleSize, height: appleSize))
        appleView.wantsLayer = true
        appleView.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView?.addSubview(appleView)

        let x = appleSpawnX(in: screenFrame)
        let onDock = x >= dockLeft && x <= dockRight

        var apple = AppleState(view: appleView)
        apple.x = x
        apple.y = screenFrame.height
        let fallDirection: CGFloat = Bool.random() ? 1 : -1
        apple.velocityX = fallDirection * CGFloat.random(in: 120...180)
        apple.rotation = CGFloat.random(in: -0.12...0.12)
        apple.rotationSpeed = CGFloat.random(in: 3...7) * (Bool.random() ? 1 : -1)
        apple.floorY = (onDock ? dockFloorY : groundFloorY) - APPLE_PADDING
        apples.append(apple)
    }

    /// Drop an apple at a specific position. Phantom apples are invisible navigation lures.
    func feedAppleAt(x: CGFloat, y: CGFloat, phantom: Bool = false) {
        guard window != nil else { return }

        let appleView = AppleView(frame: NSRect(x: 0, y: 0, width: appleSize, height: appleSize))
        appleView.wantsLayer = true
        appleView.layer?.backgroundColor = NSColor.clear.cgColor
        if phantom { appleView.alphaValue = 0 } // invisible
        window.contentView?.addSubview(appleView)

        let onDock = x >= dockLeft && x <= dockRight
        var apple = AppleState(view: appleView)
        apple.x = x
        apple.y = y
        apple.velocityX = CGFloat.random(in: -40...40)
        apple.rotation = 0
        apple.rotationSpeed = CGFloat.random(in: 1...3)
        apple.floorY = (onDock ? dockFloorY : groundFloorY) - APPLE_PADDING
        apple.isPhantom = phantom
        apples.append(apple)
    }

    func appleSpawnX(in screenFrame: CGRect) -> CGFloat {
        let minX = screenFrame.origin.x + 100
        let maxX = screenFrame.origin.x + screenFrame.width - 100
        guard minX < maxX else { return screenFrame.midX }

        let crabAvoidance = max(appleSize * 1.4, crabHitRect().width * 0.9)
        let safeMin = max(minX, crabX - crabAvoidance)
        let safeMax = min(maxX, crabX + crabAvoidance)

        if safeMin >= safeMax {
            return CGFloat.random(in: minX...maxX)
        }

        for _ in 0..<8 {
            let candidate = CGFloat.random(in: minX...maxX)
            if candidate < safeMin || candidate > safeMax {
                return candidate
            }
        }

        let leftRangeWidth = max(0, safeMin - minX)
        let rightRangeWidth = max(0, maxX - safeMax)
        if leftRangeWidth == 0 && rightRangeWidth == 0 {
            return safeMin < screenFrame.midX ? maxX : minX
        }
        if rightRangeWidth > leftRangeWidth {
            return CGFloat.random(in: safeMax...maxX)
        }
        return CGFloat.random(in: minX...safeMin)
    }

    @objc func exitApp() {
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = nil
        releaseCheckTimer?.invalidate()
        releaseCheckTimer = nil
        updateTimer?.invalidate()
        windowTracker.stopTracking()
        systemMonitor.stopMonitoring()
        inputHandler?.removeMonitors()
        particleSystem?.removeAll()
        if let feedHotKeyRef {
            UnregisterEventHotKey(feedHotKeyRef)
            self.feedHotKeyRef = nil
        }
        NSApp.terminate(nil)
    }

    func registerFeedHotKey() {
        let eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr, hotKeyID.id == 1 else { return noErr }
            DispatchQueue.main.async {
                (NSApp.delegate as? AppController)?.feedApple()
            }
            return noErr
        }, 1, [eventSpec], nil, &hotKeyHandlerRef)

        let hotKeyID = EventHotKeyID(signature: 0x46454544, id: 1)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_F),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &feedHotKeyRef
        )
    }

    func updateApples(_ dt: CGFloat) {
        var toRemove: [Int] = []
        let xBounds = appleHorizontalBounds()
        let topYLimit = appleTopYLimit()
        let crabCollisionRect = crabHitRect().insetBy(dx: 8, dy: 2)
        let crabHeadRect = crabHeadHitRect(from: crabCollisionRect)
        let crabBodyRect = crabBodyHitRect(from: crabCollisionRect)

        for i in 0..<apples.count {
            apples[i].crabHitCooldown = max(0, apples[i].crabHitCooldown - dt)
            switch apples[i].phase {
            case .falling, .bounce:
                let previousX = apples[i].x
                let previousY = apples[i].y
                apples[i].previousX = previousX
                apples[i].previousY = previousY
                apples[i].x += apples[i].velocityX * dt
                apples[i].velocityY += appleGravity * dt
                apples[i].y += apples[i].velocityY * dt
                apples[i].rotation += apples[i].rotationSpeed * dt

                if apples[i].x < xBounds.lowerBound {
                    apples[i].x = xBounds.lowerBound
                    apples[i].velocityX = abs(apples[i].velocityX) * 0.78
                    apples[i].rotationSpeed *= -0.7
                } else if apples[i].x > xBounds.upperBound {
                    apples[i].x = xBounds.upperBound
                    apples[i].velocityX = -abs(apples[i].velocityX) * 0.78
                    apples[i].rotationSpeed *= -0.7
                }

                if apples[i].y > topYLimit {
                    apples[i].y = topYLimit
                    apples[i].velocityY = -abs(apples[i].velocityY) * 0.72
                    apples[i].rotationSpeed *= -0.75
                }

                apples[i].floorY = appleFloorY(
                    forX: apples[i].x,
                    currentY: apples[i].y,
                    previousX: previousX,
                    previousY: previousY
                )
                constrainAppleAgainstDock(i, previousX: previousX)

                if apples[i].y <= apples[i].floorY {
                    apples[i].y = apples[i].floorY
                    apples[i].bounceCount += 1
                    if apples[i].bounceCount == 1 && !isSeekingApples {
                        beginAppleSeek(now: CACurrentMediaTime())
                    }
                    if apples[i].bounceCount < 3 {
                        apples[i].velocityY = abs(apples[i].velocityY) * 0.35
                        apples[i].velocityX *= 0.72
                        apples[i].rotationSpeed *= 0.5
                        apples[i].phase = .bounce
                    } else {
                        apples[i].velocityX *= 0.42
                        apples[i].velocityY = 0
                        apples[i].rotationSpeed *= 0.35
                        apples[i].settleWobbleTime = 0
                        apples[i].phase = .resting
                    }
                }

            case .resting:
                let previousX = apples[i].x
                let previousY = apples[i].y
                apples[i].previousX = previousX
                apples[i].previousY = previousY
                apples[i].x += apples[i].velocityX * dt
                apples[i].floorY = appleFloorY(forX: apples[i].x, currentY: apples[i].floorY)
                apples[i].y = apples[i].floorY
                apples[i].rotation += apples[i].rotationSpeed * dt
                constrainAppleAgainstDock(i, previousX: previousX)

                if apples[i].x < xBounds.lowerBound {
                    apples[i].x = xBounds.lowerBound
                    apples[i].velocityX = 0
                } else if apples[i].x > xBounds.upperBound {
                    apples[i].x = xBounds.upperBound
                    apples[i].velocityX = 0
                }

                let slideDrag = max(0, 1 - 4.8 * dt)
                let spinDrag = max(0, 1 - 6.5 * dt)
                apples[i].velocityX *= slideDrag
                apples[i].rotationSpeed *= spinDrag

                if abs(apples[i].velocityX) < 6 {
                    apples[i].velocityX = 0
                }
                if abs(apples[i].rotationSpeed) < 0.2 {
                    apples[i].rotationSpeed = 0
                }
                if apples[i].velocityX == 0 && apples[i].rotationSpeed == 0 {
                    if apples[i].settleWobbleTime == 0 {
                        apples[i].settleRotation = apples[i].rotation
                    }
                    let wobbleDuration: CGFloat = 0.22
                    apples[i].settleWobbleTime = min(wobbleDuration, apples[i].settleWobbleTime + dt)
                    let wobbleT = apples[i].settleWobbleTime / wobbleDuration
                    let wobbleAmplitude: CGFloat = 0.045
                    let wobble = sin(wobbleT * CGFloat.pi) * (1 - wobbleT) * wobbleAmplitude
                    apples[i].rotation = apples[i].settleRotation + wobble
                    if apples[i].settleWobbleTime >= wobbleDuration {
                        apples[i].rotation = apples[i].settleRotation
                    }
                } else {
                    apples[i].settleWobbleTime = 0
                }
            }
        }

        resolveAppleContacts()

        for i in 0..<apples.count {
            // Universal proximity eat: if pet is close enough, eat it (phantom or real)
            let eatDist: CGFloat = apples[i].isPhantom ? 45 : 40
            let dx = abs(apples[i].x - crabX)
            let dy = abs(apples[i].y - crabY)
            if dx < eatDist && dy < 60 && (apples[i].phase == .resting || apples[i].isPhantom) {
                toRemove.append(i)
                continue
            }

            if apples[i].isPhantom { continue }

            guard level == levelForApple(apples[i]) else {
                apples[i].view.rotation = apples[i].rotation
                apples[i].view.frame.origin.x = apples[i].x - appleSize / 2
                apples[i].view.frame.origin.y = apples[i].y
                apples[i].view.needsDisplay = true
                continue
            }

            let appleRect = CGRect(
                x: apples[i].x - appleSize / 2,
                y: apples[i].y,
                width: appleSize,
                height: appleSize
            )
            if appleHitsCrabHead(apple: apples[i], appleRect: appleRect, crabHeadRect: crabHeadRect) {
                // When actively seeking, eat on head contact instead of deflecting
                if isSeekingApples && apples[i].phase == .resting {
                    toRemove.append(i)
                    continue
                }
                if apples[i].crabHitCooldown > 0 {
                    apples[i].view.rotation = apples[i].rotation
                    apples[i].view.frame.origin.x = apples[i].x - appleSize / 2
                    apples[i].view.frame.origin.y = apples[i].y
                    apples[i].view.needsDisplay = true
                    continue
                }
                reactToTopAppleHit(from: apples[i])
                deflectAppleAfterCrabHit(at: i, crabRect: crabCollisionRect)
                apples[i].view.rotation = apples[i].rotation
                apples[i].view.frame.origin.x = apples[i].x - appleSize / 2
                apples[i].view.frame.origin.y = apples[i].y
                apples[i].view.needsDisplay = true
                continue
            }

            if crabBodyRect.intersects(appleRect) {
                toRemove.append(i)
                continue
            }

            apples[i].view.rotation = apples[i].rotation
            apples[i].view.frame.origin.x = apples[i].x - appleSize / 2
            apples[i].view.frame.origin.y = apples[i].y
            apples[i].view.needsDisplay = true
        }

        for i in toRemove.reversed() {
            apples[i].view.removeFromSuperview()
            apples.remove(at: i)
            // Track apple eaten for mood system
            applesEatenThisFrame += 1
            moodSystem.onAppleEaten()
            mascot.setExpression(.happy, duration: 1.0)
        }

        if isSeekingApples && apples.isEmpty {
            endAppleSeek(now: CACurrentMediaTime())
        }
    }

    func appleHitsCrabHead(apple: AppleState, appleRect: CGRect, crabHeadRect: CGRect) -> Bool {
        guard jumpPhase == .none else { return false }
        guard apple.crabHitCooldown <= 0 else { return false }
        guard apple.velocityY < -20 else { return false }
        guard apple.phase != .resting else { return false }

        let appleRadius = appleCollisionRadius()
        let previousAppleCenterY = apple.previousY + appleSize / 2
        let currentAppleCenterY = appleRect.midY
        let previousAppleBottom = previousAppleCenterY - appleRadius
        let currentAppleBottom = currentAppleCenterY - appleRadius
        let topContactTolerance = max(CGFloat(16), appleSize * 0.55)

        let horizontalOverlap = min(apple.x + appleRadius, crabHeadRect.maxX) - max(apple.x - appleRadius, crabHeadRect.minX)
        guard horizontalOverlap >= min(appleRadius * 2, crabHeadRect.width) * 0.12 else {
            return false
        }

        return previousAppleBottom >= crabHeadRect.minY - topContactTolerance
            && currentAppleBottom <= crabHeadRect.maxY + topContactTolerance
    }

    func crabHeadHitRect(from crabRect: CGRect) -> CGRect {
        let headHeight = max(CGFloat(18), crabRect.height * 0.42)
        let headInset = max(CGFloat(2), crabRect.width * 0.06)
        return CGRect(
            x: crabRect.minX + headInset,
            y: crabRect.maxY - headHeight,
            width: crabRect.width - headInset * 2,
            height: headHeight
        )
    }

    func crabBodyHitRect(from crabRect: CGRect) -> CGRect {
        let headHeight = max(CGFloat(18), crabRect.height * 0.42)
        return CGRect(
            x: crabRect.minX,
            y: crabRect.minY,
            width: crabRect.width,
            height: max(CGFloat(1), crabRect.height - headHeight * 0.68)
        )
    }

    func appleCollisionRadius() -> CGFloat {
        let visibleAppleSize = CGFloat(appleGrid.count) * APPLE_SCALE
        return visibleAppleSize * 0.42
    }

    func reactToTopAppleHit(from apple: AppleState) {
        let direction: CGFloat
        if abs(apple.x - crabX) < 3 {
            if level == .dock {
                direction = crabX < (dockLeft + dockRight) * 0.5 ? -1 : 1
            } else {
                direction = claudeView.facingRight ? -1 : 1
            }
        } else {
            direction = apple.x < crabX ? 1 : -1
        }

        lastActivityTime = CACurrentMediaTime()
        isAsleep = false
        wakingUp = false
        mascot.setExpression(.surprised, duration: 1.5)

        if level == .dock {
            startJump(down: true, direction: direction)
        } else {
            startHop(direction: direction)
        }
        currentJumpHorizontalDistance = jumpHorizontalDistance * 2
    }

    func deflectAppleAfterCrabHit(at index: Int, crabRect: CGRect) {
        apples[index].y = max(apples[index].y, crabRect.maxY - appleSize + 2)
        apples[index].velocityY = max(abs(apples[index].velocityY) * 0.55, 180)
        let horizontalDirection: CGFloat = apples[index].x < crabX ? -1 : 1
        apples[index].velocityX = horizontalDirection * max(abs(apples[index].velocityX) * 0.4, 90)
        apples[index].rotationSpeed += horizontalDirection * 4
        apples[index].phase = .bounce
        apples[index].bounceCount = min(apples[index].bounceCount, 1)
        apples[index].settleWobbleTime = 0
        apples[index].crabHitCooldown = 0.35
    }

    func resolveAppleContacts() {
        guard apples.count > 1 else { return }

        let contactDistance = appleSize * appleContactSeparation
        let rowTolerance = appleSize * appleContactRowTolerance
        let cellSize = max(contactDistance, 1)
        var dockBuckets: [Int: [Int]] = [:]
        var groundBuckets: [Int: [Int]] = [:]

        for index in apples.indices {
            let bucket = Int(floor(apples[index].x / cellSize))
            switch levelForApple(apples[index]) {
            case .dock:
                dockBuckets[bucket, default: []].append(index)
            case .ground, .window:
                groundBuckets[bucket, default: []].append(index)
            }
        }

        resolveAppleContacts(in: dockBuckets, contactDistance: contactDistance, rowTolerance: rowTolerance)
        resolveAppleContacts(in: groundBuckets, contactDistance: contactDistance, rowTolerance: rowTolerance)
    }

    func resolveAppleContacts(
        in buckets: [Int: [Int]],
        contactDistance: CGFloat,
        rowTolerance: CGFloat
    ) {
        guard !buckets.isEmpty else { return }

        for bucket in buckets.keys.sorted() {
            guard let current = buckets[bucket] else { continue }
            resolveAppleContactsWithinBucket(
                current,
                contactDistance: contactDistance,
                rowTolerance: rowTolerance
            )

            guard let neighbor = buckets[bucket + 1] else { continue }
            resolveAppleContactsBetweenBuckets(
                current,
                neighbor,
                contactDistance: contactDistance,
                rowTolerance: rowTolerance
            )
        }
    }

    func resolveAppleContactsWithinBucket(
        _ indices: [Int],
        contactDistance: CGFloat,
        rowTolerance: CGFloat
    ) {
        guard indices.count > 1 else { return }

        for offset in 0..<(indices.count - 1) {
            let i = indices[offset]
            for nextOffset in (offset + 1)..<indices.count {
                let j = indices[nextOffset]
                resolveAppleContactPair(
                    i,
                    j,
                    contactDistance: contactDistance,
                    rowTolerance: rowTolerance
                )
            }
        }
    }

    func resolveAppleContactsBetweenBuckets(
        _ lhs: [Int],
        _ rhs: [Int],
        contactDistance: CGFloat,
        rowTolerance: CGFloat
    ) {
        for i in lhs {
            for j in rhs {
                resolveAppleContactPair(
                    i,
                    j,
                    contactDistance: contactDistance,
                    rowTolerance: rowTolerance
                )
            }
        }
    }

    func resolveAppleContactPair(
        _ i: Int,
        _ j: Int,
        contactDistance: CGFloat,
        rowTolerance: CGFloat
    ) {
        let minDistance: CGFloat = 0.001
        let separationBias: CGFloat = 0.82
        let restitution: CGFloat = 0.58

        let dx = apples[j].x - apples[i].x
        guard abs(dx) < contactDistance else { return }

        let dy = apples[j].y - apples[i].y
        guard abs(dy) < rowTolerance else { return }

        let distance = sqrt(dx * dx + dy * dy)
        guard distance < contactDistance else { return }

        let overlap = contactDistance - distance
        let normalX = distance > minDistance ? dx / distance : (apples[i].x <= apples[j].x ? 1 : -1)
        let normalY = distance > minDistance ? dy / distance : 0
        let push = overlap * 0.5 * separationBias

        apples[i].x -= normalX * push
        apples[j].x += normalX * push

        if apples[i].phase != .resting {
            apples[i].y -= normalY * push * 0.3
        }
        if apples[j].phase != .resting {
            apples[j].y += normalY * push * 0.3
        }

        let relativeVelocityX = apples[j].velocityX - apples[i].velocityX
        let relativeVelocityY = apples[j].velocityY - apples[i].velocityY
        let closingSpeed = relativeVelocityX * normalX + relativeVelocityY * normalY
        guard closingSpeed < -4 else { return }

        let impulse = -(1 + restitution) * closingSpeed * 0.5
        apples[i].velocityX -= impulse * normalX
        apples[j].velocityX += impulse * normalX
        apples[i].velocityY -= impulse * normalY * 0.45
        apples[j].velocityY += impulse * normalY * 0.45

        let tangentX = -normalY
        let tangentY = normalX
        let tangentSpeed = relativeVelocityX * tangentX + relativeVelocityY * tangentY
        let spinImpulse = tangentSpeed * 0.02 + impulse * normalX * 0.012
        apples[i].rotationSpeed -= spinImpulse
        apples[j].rotationSpeed += spinImpulse

        let groundedI = apples[i].y <= apples[i].floorY + 0.5
        let groundedJ = apples[j].y <= apples[j].floorY + 0.5
        if groundedI && apples[i].phase != .resting {
            apples[i].velocityY = max(apples[i].velocityY, CGFloat.random(in: 22...36))
        }
        if groundedJ && apples[j].phase != .resting {
            apples[j].velocityY = max(apples[j].velocityY, CGFloat.random(in: 22...36))
        }

        if apples[i].phase == .resting && abs(apples[i].velocityX) > 10 {
            apples[i].settleWobbleTime = 0
        }
        if apples[j].phase == .resting && abs(apples[j].velocityX) > 10 {
            apples[j].settleWobbleTime = 0
        }

        apples[i].rotationSpeed = max(-18, min(18, apples[i].rotationSpeed))
        apples[j].rotationSpeed = max(-18, min(18, apples[j].rotationSpeed))
    }

    func crabHitRect() -> CGRect {
        let s = SCALE
        let ox: CGFloat = 10 * s
        let oy: CGFloat = 4 * s
        let legRows = CGFloat(claudeView.currentLegs.count)
        let bottom = oy - legRows * s
        let top = oy + CGFloat(bodyGrid.count) * s + claudeView.bodyBob + claudeView.legYBob
        return CGRect(
            x: claudeView.frame.origin.x + ox,
            y: claudeView.frame.origin.y + bottom,
            width: 10 * s,
            height: max(s, top - bottom)
        )
    }

    func crabHitRectInScreen() -> CGRect? {
        guard let window else { return nil }
        return window.convertToScreen(crabHitRect()).insetBy(dx: -2, dy: -2)
    }

    func appleRectInScreen(_ apple: AppleState) -> CGRect? {
        guard let window else { return nil }
        let windowRect = apple.view.convert(apple.view.bounds, to: nil)
        return window.convertToScreen(windowRect).insetBy(dx: -2, dy: -2)
    }

    func throwApple(at index: Int, from screenPoint: CGPoint) {
        let appleCenterX = apples[index].x
        let direction: CGFloat
        if abs(screenPoint.x - appleCenterX) < 4 {
            direction = Bool.random() ? 1 : -1
        } else {
            direction = screenPoint.x < appleCenterX ? 1 : -1
        }

        apples[index].phase = .falling
        apples[index].bounceCount = 0
        apples[index].velocityX = direction * CGFloat.random(in: 720...980)
        apples[index].velocityY = CGFloat.random(in: 1250...1550)
        apples[index].rotationSpeed = CGFloat.random(in: 12...18) * (direction > 0 ? 1 : -1)
        apples[index].floorY = appleFloorY(forX: apples[index].x, currentY: apples[index].y)

        // Reset seek delay — the apple position will change while it's airborne/bouncing.
        // Mascot waits for it to settle before chasing.
        if isSeekingApples {
            appleSeekStartTime = CACurrentMediaTime()
            appleSeekDelay = TimeInterval.random(in: 1.5...2.5)
            appleSeekTargetID = nil
            appleSeekHopTriggers.removeAll()
            autoTargetX = nil
        }
    }

    func handleAppleClick(at screenPoint: CGPoint) -> Bool {
        for i in apples.indices.reversed() {
            guard let appleRect = appleRectInScreen(apples[i]) else { continue }
            guard appleRect.contains(screenPoint) else { continue }
            throwApple(at: i, from: screenPoint)
            return true
        }
        return false
    }

    func handleCrabClick(at screenPoint: CGPoint) -> Bool {
        guard let hitRect = crabHitRectInScreen(), hitRect.contains(screenPoint) else { return false }
        guard isFullyAwake() else { return false }

        lastActivityTime = CACurrentMediaTime()
        recentInteractionCount += 1
        startInPlaceJump()
        return true
    }

    func handleMouseClick(at screenPoint: CGPoint) {
        if handleAppleClick(at: screenPoint) {
            return
        }
        if handleCrabClick(at: screenPoint) {
            return
        }
        handleWakeClick(at: screenPoint)
    }

    func handleWakeClick(at screenPoint: CGPoint) {
        guard isAsleep else { return }
        guard let hitRect = crabHitRectInScreen(), hitRect.contains(screenPoint) else { return }
        let now = CACurrentMediaTime()

        isAsleep = false
        wakingUp = true
        lastActivityTime = now
        lastMouseMoveTime = now
        mouseSettled = false
        moodSystem.onWokenUp()
    }
}
