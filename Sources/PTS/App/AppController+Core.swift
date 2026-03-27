import Cocoa

extension AppController {
    func debugLog(_ message: String) {
        guard debugEnabled else { return }
        print("[PTS] \(message)")
        fflush(stdout)
    }

    func debugSnapshot(now: TimeInterval) {
        guard debugEnabled else { return }
        guard now - lastDebugSnapshotTime >= 0.25 else { return }

        let autoTarget = autoTargetX.map { String(format: "%.1f", $0) } ?? "nil"
        let nearestApple = nearestAppleIndex().map { index in
            let apple = apples[index]
            return String(format: "idx=%d x=%.1f y=%.1f phase=%@", index, apple.x, apple.y, String(describing: apple.phase))
        } ?? "none"
        let snapshot = String(
            format: "state level=%@ jump=%@ seek=%@ asleep=%@ waking=%@ x=%.1f y=%.1f auto=%@ apples=%d nearest=%@",
            String(describing: level),
            String(describing: jumpPhase),
            isSeekingApples.description,
            isAsleep.description,
            wakingUp.description,
            crabX,
            crabY,
            autoTarget,
            apples.count,
            nearestApple
        )

        guard snapshot != lastDebugSnapshot else { return }
        lastDebugSnapshot = snapshot
        lastDebugSnapshotTime = now
        debugLog(snapshot)
    }

    func isDockObscured(screen: NSScreen) -> Bool {
        let screenFrame = screen.frame

        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }
        if frontApp.bundleIdentifier == "com.apple.dock" ||
            frontApp.bundleIdentifier == "com.apple.finder" {
            return false
        }

        let pid = frontApp.processIdentifier
        let options = CGWindowListOption([.optionOnScreenOnly, .excludeDesktopElements])
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        let pidKey = kCGWindowOwnerPID as String
        let boundsKey = "kCGWindowBounds"
        let layerKey = kCGWindowLayer as String

        for window in windows {
            guard let windowPid = window[pidKey] as? Int32, windowPid == pid,
                  let layer = window[layerKey] as? Int, layer == 0,
                  let bounds = window[boundsKey] as? [String: CGFloat],
                  let width = bounds["Width"], let height = bounds["Height"] else {
                continue
            }

            if width >= screenFrame.width - 1 && height >= screenFrame.height - 1 {
                return true
            }
        }

        return false
    }

    func refreshDockBounds() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame

        dockVisible = !isDockObscured(screen: screen)
        window?.alphaValue = dockVisible ? 1 : 0

        let dock = DockInfo.get(screen: screen)
        let halfBody: CGFloat = 5 * SCALE
        let feetOffset: CGFloat = 2 * SCALE  // distance from sprite origin to foot bottom

        dockLeft = dock.x + halfBody
        dockRight = dock.x + dock.width - halfBody
        screenLeft = screenFrame.origin.x + halfBody + 10
        screenRight = screenFrame.origin.x + screenFrame.width - halfBody - 10
        groundFloorY = -feetOffset
        dockFloorY = dock.height - feetOffset

        let windowHeight = screenFrame.height
        window?.setFrame(
            NSRect(
                x: screenFrame.origin.x,
                y: screenFrame.origin.y,
                width: screenFrame.width,
                height: windowHeight
            ),
            display: false
        )

        if let contentView = window?.contentView {
            contentView.frame.size = NSSize(width: screenFrame.width, height: windowHeight)
        }

        // Don't snap Y — let physics handle transitions naturally
    }

    func refreshWindowBounds() {
        guard let windowInfo = WindowInfo.getActive() else {
            activeWindowFrame = nil
            return
        }

        activeWindowFrame = windowInfo.frame
        windowFloorY = computeWindowFloorY(for: windowInfo.frame)
    }

    func computeWindowFloorY(for frame: NSRect) -> CGFloat {
        let feetOffset: CGFloat = 2 * SCALE
        return frame.maxY - feetOffset
    }

    func currentMinX() -> CGFloat {
        switch level {
        case .dock: return dockLeft
        case .ground: return screenLeft
        case .window: return activeWindowFrame?.minX ?? screenLeft
        }
    }

    func currentMaxX() -> CGFloat {
        switch level {
        case .dock: return dockRight
        case .ground: return screenRight
        case .window: return activeWindowFrame?.maxX ?? screenRight
        }
    }

    func nearestAppleIndex(chaseableOnly: Bool = false) -> Int? {
        let candidates = apples.indices.filter { !chaseableOnly || apples[$0].phase != .falling }
        return candidates.min { lhs, rhs in
            let leftDist = appleSeekDistance(to: apples[lhs])
            let rightDist = appleSeekDistance(to: apples[rhs])
            if leftDist == rightDist {
                return apples[lhs].x < apples[rhs].x
            }
            return leftDist < rightDist
        }
    }

    func nearestAppleX(chaseableOnly: Bool = false) -> CGFloat? {
        guard let index = nearestAppleIndex(chaseableOnly: chaseableOnly) else { return nil }
        return apples[index].x
    }

    func currentAppleSeekIndex() -> Int? {
        if let targetID = appleSeekTargetID,
           let lockedIndex = apples.firstIndex(where: { ObjectIdentifier($0.view) == targetID }) {
            let lockedApple = apples[lockedIndex]
            if lockedApple.phase != .falling || nearestAppleIndex(chaseableOnly: true) == nil {
                return lockedIndex
            }
        }

        let preferredIndex = nearestAppleIndex(chaseableOnly: true) ?? nearestAppleIndex()
        guard let index = preferredIndex else {
            appleSeekTargetID = nil
            appleSeekHopTriggers.removeAll()
            return nil
        }

        let apple = apples[index]
        let targetID = ObjectIdentifier(apple.view)
        if appleSeekTargetID != targetID {
            appleSeekTargetID = targetID

            let hopCount = Int.random(in: 0...3)
            let distance = abs(apple.x - crabX)
            if hopCount == 0 || distance < 70 {
                appleSeekHopTriggers.removeAll()
            } else {
                let minTrigger: CGFloat = 35
                let maxTrigger = max(minTrigger + 5, distance - 20)
                appleSeekHopTriggers = (0..<hopCount)
                    .map { _ in CGFloat.random(in: minTrigger...maxTrigger) }
                    .sorted(by: >)
            }
        }

        return index
    }

    func currentAppleSeekTargetX() -> CGFloat? {
        guard let index = currentAppleSeekIndex() else { return nil }
        let apple = apples[index]
        return appleSeekTargetX(for: apple)
    }

    func appleSeekDistance(to apple: AppleState) -> CGFloat {
        let appleLevel = levelForApple(apple)
        if appleLevel == level {
            return abs(apple.x - crabX)
        }

        let leftPath = abs(crabX - dockLeft) + abs(apple.x - dockLeft)
        let rightPath = abs(crabX - dockRight) + abs(apple.x - dockRight)
        return min(leftPath, rightPath) + jumpHorizontalDistance * 0.35
    }

    func appleSeekTargetX(for apple: AppleState) -> CGFloat {
        let appleLevel = levelForApple(apple)
        if appleLevel == level {
            return apple.x
        }

        let leftPath = abs(crabX - dockLeft) + abs(apple.x - dockLeft)
        let rightPath = abs(crabX - dockRight) + abs(apple.x - dockRight)
        if level == .dock && appleLevel == .ground {
            return leftPath <= rightPath ? dockLeft - 2 : dockRight + 2
        }
        return leftPath <= rightPath ? dockLeft + 2 : dockRight - 2
    }

    func canLandHop(on level: CrabLevel, direction: CGFloat) -> Bool {
        let landingX = crabX + direction * jumpHorizontalDistance
        switch level {
        case .dock:
            return landingX >= dockLeft && landingX <= dockRight
        case .ground:
            return landingX >= screenLeft && landingX <= screenRight
        case .window:
            return landingX >= (activeWindowFrame?.minX ?? 0) && landingX <= (activeWindowFrame?.maxX ?? 0)
        }
    }

    func isAppleHopTooCloseToDockEdge(direction: CGFloat) -> Bool {
        guard level == .dock else { return false }

        let hopEdgeMargin = jumpHorizontalDistance * 0.45
        let landingX = crabX + direction * jumpHorizontalDistance
        let minSafeX = dockLeft + hopEdgeMargin
        let maxSafeX = dockRight - hopEdgeMargin
        return crabX < minSafeX || crabX > maxSafeX || landingX < minSafeX || landingX > maxSafeX
    }

    func pathCrossesDockOnGround(from startX: CGFloat, to targetX: CGFloat) -> Bool {
        let pathMinX = min(startX, targetX)
        let pathMaxX = max(startX, targetX)
        return pathMaxX >= dockLeft && pathMinX <= dockRight
    }

    func dockEntryDirection(for targetX: CGFloat) -> CGFloat {
        // When approaching from the ground, always enter from the side the crab is
        // already on. Otherwise it can jump onto the dock from the opposite edge,
        // land near an exit, and immediately jump back down into a loop.
        if crabX < dockLeft {
            return 1
        }
        if crabX > dockRight {
            return -1
        }

        let leftApproachX = dockLeft - 2
        let rightApproachX = dockRight + 2
        let leftCost = abs(crabX - leftApproachX) + abs(targetX - dockLeft)
        let rightCost = abs(crabX - rightApproachX) + abs(targetX - dockRight)
        if abs(leftCost - rightCost) < 0.5 {
            return abs(crabX - leftApproachX) <= abs(crabX - rightApproachX) ? 1 : -1
        }
        return leftCost < rightCost ? 1 : -1
    }

    func dockEntryApproachX(for targetX: CGFloat) -> CGFloat {
        let entryDir = dockEntryDirection(for: targetX)
        return entryDir > 0 ? dockLeft - 2 : dockRight + 2
    }

    func currentAppleSeekTargetLevel() -> CrabLevel? {
        guard let index = nearestAppleIndex(chaseableOnly: true) ?? nearestAppleIndex() else { return nil }
        return levelForApple(apples[index])
    }

    func shouldStartAppleHop(remainingDistance: CGFloat, direction: CGFloat) -> Bool {
        guard isSeekingApples, let nextTrigger = appleSeekHopTriggers.first else { return false }
        guard remainingDistance > autoThresh * 2 else { return false }
        guard remainingDistance <= nextTrigger else { return false }
        guard canLandHop(on: level, direction: direction) else { return false }
        guard !isAppleHopTooCloseToDockEdge(direction: direction) else { return false }

        appleSeekHopTriggers.removeFirst()
        return true
    }

    func beginAppleSeek(now: TimeInterval) {
        isSeekingApples = true
        appleSeekStartTime = now
        appleSeekDelay = TimeInterval.random(in: 1.0...2.0)
        appleSeekTargetID = nil
        appleSeekHopTriggers.removeAll()
        isAsleep = false
        wakingUp = claudeView.sitAmount > 0.05 || claudeView.eyeClose > 0.05
        autoTargetX = nil
        lastActivityTime = now
        lastMouseMoveTime = now
        mouseSettled = false
        pendingTargetX = NSEvent.mouseLocation.x
        debugLog(String(format: "beginAppleSeek x=%.1f y=%.1f apples=%d", crabX, crabY, apples.count))
    }

    func resetWalkAnimation() {
        settleTimer = 0
        walkTimer = 0
        claudeView.legFrame = 0
        claudeView.currentLegs = legsIdle
        claudeView.isWalking = false
        claudeView.walkFacing = 0
    }

    func endAppleSeek(now: TimeInterval) {
        isSeekingApples = false
        appleSeekTargetID = nil
        appleSeekHopTriggers.removeAll()
        autoTargetX = nil
        resetWalkAnimation()
        lastActivityTime = now
        lastMouseMoveTime = now
        mouseSettled = false
        pendingTargetX = NSEvent.mouseLocation.x
        debugLog(String(format: "endAppleSeek x=%.1f y=%.1f apples=%d", crabX, crabY, apples.count))
    }

    func lookTargetX(fallback mouseX: CGFloat) -> CGFloat {
        if let groundedAppleX = groundedAppleLookTargetX() {
            return groundedAppleX
        }
        if isSeekingApples {
            if let targetID = appleSeekTargetID,
               let trackedApple = apples.first(where: { ObjectIdentifier($0.view) == targetID }) {
                return trackedApple.x
            }
            if let index = currentAppleSeekIndex() {
                return apples[index].x
            }
            return crabX
        }
        return mouseX
    }

    func groundedAppleLookTargetX() -> CGFloat? {
        let groundedThreshold: CGFloat = 0.5

        if let targetID = appleSeekTargetID,
           let trackedApple = apples.first(where: { ObjectIdentifier($0.view) == targetID }),
           trackedApple.y <= trackedApple.floorY + groundedThreshold {
            return trackedApple.x
        }

        guard let groundedApple = apples
            .filter({ $0.y <= $0.floorY + groundedThreshold })
            .min(by: { abs($0.x - crabX) < abs($1.x - crabX) }) else {
            return nil
        }
        return groundedApple.x
    }

    func dockAppleFloorY() -> CGFloat {
        dockFloorY - APPLE_PADDING
    }

    func groundAppleFloorY() -> CGFloat {
        groundFloorY - APPLE_PADDING
    }

    func levelForApple(_ apple: AppleState) -> CrabLevel {
        let appleFloor = dockAppleFloorY()
        let groundFloor = groundAppleFloorY()
        let windowFloor = windowFloorY - APPLE_PADDING
        
        let dDock = abs(apple.floorY - appleFloor)
        let dGround = abs(apple.floorY - groundFloor)
        let dWindow = abs(apple.floorY - windowFloor)
        
        if dWindow < dDock && dWindow < dGround { return .window }
        return dDock < dGround ? .dock : .ground
    }

    func appleHorizontalBounds() -> ClosedRange<CGFloat> {
        let appleHalf = appleSize / 2
        let width = window.contentView?.bounds.width ?? (screenRight + appleHalf)
        return appleHalf...(width - appleHalf)
    }

    func appleTopYLimit() -> CGFloat {
        let height = window.contentView?.bounds.height ?? 0
        return max(0, height - appleSize)
    }

    func appleCrossedDockTop(fromX previousX: CGFloat, y previousY: CGFloat, toX x: CGFloat, y currentY: CGFloat) -> Bool {
        let dockFloor = dockAppleFloorY()
        let crossedDockBand = max(previousX, x) >= dockLeft && min(previousX, x) <= dockRight
        let crossedDockTop = previousY >= dockFloor && currentY <= dockFloor
        return crossedDockBand && crossedDockTop
    }

    func appleFloorY(forX x: CGFloat, currentY: CGFloat, previousX: CGFloat? = nil, previousY: CGFloat? = nil) -> CGFloat {
        let dockFloor = dockAppleFloorY()
        let groundFloor = groundAppleFloorY()

        if let previousX, let previousY,
           appleCrossedDockTop(fromX: previousX, y: previousY, toX: x, y: currentY) {
            return dockFloor
        }

        let overDock = x >= dockLeft && x <= dockRight
        let aboveDockTop = currentY >= dockFloor
        return overDock && aboveDockTop ? dockFloor : groundFloor
    }

    func constrainAppleAgainstDock(_ index: Int, previousX: CGFloat? = nil) {
        let dockFloor = dockAppleFloorY()
        let groundFloor = groundAppleFloorY()
        guard apples[index].floorY <= groundFloor + 0.5 else { return }
        guard apples[index].y < dockFloor - 0.5 else { return }

        let appleHalf = appleSize / 2
        let leftBarrier = dockLeft - appleHalf
        let rightBarrier = dockRight + appleHalf
        guard apples[index].x > leftBarrier && apples[index].x < rightBarrier else { return }

        let targetX: CGFloat
        if let previousX {
            if previousX <= leftBarrier {
                targetX = leftBarrier
            } else if previousX >= rightBarrier {
                targetX = rightBarrier
            } else {
                targetX = abs(apples[index].x - leftBarrier) < abs(apples[index].x - rightBarrier) ? leftBarrier : rightBarrier
            }
        } else {
            targetX = abs(apples[index].x - leftBarrier) < abs(apples[index].x - rightBarrier) ? leftBarrier : rightBarrier
        }

        apples[index].x = targetX
        apples[index].velocityX = (targetX == leftBarrier ? -1 : 1) * max(18, abs(apples[index].velocityX) * 0.45)
        apples[index].rotationSpeed += apples[index].velocityX * 0.01
        apples[index].settleWobbleTime = 0
    }

    // MARK: - Dynamic Mouse Interactivity

    func updateMouseInteractivity() {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation

        // While dragging — always interactive
        if mascot.isDragged || (interactiveView?.isCurrentlyDragging == true) {
            window.ignoresMouseEvents = false
            return
        }

        // Check if cursor is near mascot (generous margin)
        let margin: CGFloat = 20
        var isNearMascot = false
        if let mascotScreenRect = crabHitRectInScreen()?.insetBy(dx: -margin, dy: -margin),
           mascotScreenRect.contains(mouse) {
            window.ignoresMouseEvents = false
            isNearMascot = true
        }

        // Update hover state
        let wasHovered = mascot.isHovered
        mascot.isHovered = isNearMascot && !mascot.isDragged && !mascot.isThrown && !mascot.isSqueezing
        if mascot.isHovered && !wasHovered {
            mascot.hoverStartTime = CACurrentMediaTime()
        }

        if isNearMascot { return }

        // Check if cursor is near any apple
        for apple in apples {
            if let appleRect = appleRectInScreen(apple)?.insetBy(dx: -10, dy: -10),
               appleRect.contains(mouse) {
                window.ignoresMouseEvents = false
                return
            }
        }

        // Nothing nearby — pass through
        window.ignoresMouseEvents = true
    }

    func isFullyAwake() -> Bool {
        let now = CACurrentMediaTime()
        let idleTime = now - lastActivityTime
        return !isAsleep
            && !wakingUp
            && jumpPhase == .none
            && idleTime <= drowsyDelay
            && claudeView.sitAmount < 0.05
            && claudeView.eyeClose < 0.05
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
