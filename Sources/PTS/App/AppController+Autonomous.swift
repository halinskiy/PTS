import Cocoa

// MARK: - Autonomous roaming + pet name

extension AppController {

    // How many seconds of no mouse movement before autonomous mode kicks in.
    // Stored as a Double in UserDefaults under "mascotAutoWalkDelay".
    // -1 = disabled, 0 (not set) = default 300 s.
    var autonomousIdleThreshold: TimeInterval {
        let saved = UserDefaults.standard.double(forKey: "mascotAutoWalkDelay")
        if saved < 0 { return -1 }          // Never
        return 10.0                         // always 10s — pet should be active
    }

    // MARK: Lifecycle

    func updateAutonomousMode(now: TimeInterval) {
        let threshold = autonomousIdleThreshold
        guard threshold > 0 else { return }   // disabled

        if !isAutonomousMode {
            guard now - lastUserActivityTime >= threshold else { return }
            guard window != nil, !mascot.isDragged else { return }
            enterAutonomousMode(now: now)
            return
        }

        // If pet is on a hidden window (buried under others) for too long, escape to ground
        if level == .window, let petWin = petWindowFrame, mascot.isAsleep {
            let petIsVisible = isPetWindowOnTop(petWin)
            if !petIsVisible {
                mascot.hiddenOnWindowTimer += CGFloat(now - (mascot.lastVisibleTime > 0 ? mascot.lastVisibleTime : now))
                mascot.lastVisibleTime = now
                if mascot.hiddenOnWindowTimer > 60 {
                    // Escape: wake up, jump to ground, start exploring
                    mascot.isAsleep = false
                    mascot.wakingUp = false
                    mascot.hiddenOnWindowTimer = 0
                    petWindowFrame = nil
                    level = .ground
                    crabY = groundFloorY
                    lastActivityTime = now
                    mascot.setExpression(.surprised, duration: 1.5)
                    if !isAutonomousMode { enterAutonomousMode(now: now) }
                    autonomousPhase = .walking
                    autonomousPhaseStartTime = now
                    autonomousNextTargetTime = now + 0.5
                    return
                }
            } else {
                mascot.hiddenOnWindowTimer = 0
                mascot.lastVisibleTime = now
            }
        } else {
            mascot.hiddenOnWindowTimer = 0
            mascot.lastVisibleTime = now
        }

        switch autonomousPhase {
        case .walking:
            if now - autonomousPhaseStartTime >= 300 {
                // Before sleeping: go to the active window if not already there
                if level != .window, let aw = activeWindowFrame {
                    // Walk toward active window to sleep on it
                    autoTargetX = aw.midX
                    lastActivityTime = now
                    // Give 30s to reach the window, then force sleep
                    if now - autonomousPhaseStartTime >= 330 {
                        autonomousPhase = .sleeping
                        autonomousPhaseStartTime = now
                        autoTargetX = nil
                    }
                    return
                }
                // Already on a window or no window available — sleep here
                autonomousPhase = .sleeping
                autonomousPhaseStartTime = now
                autoTargetX = nil
                return
            }
            // Keep mascot awake during the roam phase
            lastActivityTime = now

            // Pick a new random destination when idle
            if autoTargetX == nil, !isSeekingApples, !mascot.isDragged, !mascot.isThrown, jumpPhase == .none {
                if now >= autonomousNextTargetTime {
                    pickAutonomousWalkTarget(now: now)
                }
            }

        case .sleeping:
            if now - autonomousPhaseStartTime >= 60 {  // sleep only 1 minute
                // 3% chance to breed (spawn a clone) — max 3 instances
                if Float.random(in: 0...1) < 0.03 {
                    spawnCloneIfAllowed()
                }
                // Wake up and start a new roam phase
                autonomousPhase = .walking
                autonomousPhaseStartTime = now
                autonomousNextTargetTime = now + Double.random(in: 1.0...3.0)
                if isAsleep {
                    isAsleep = false
                    wakingUp = true
                    lastActivityTime = now
                    mascot.setExpression(.neutral)
                }
            }
            // In sleep phase: do NOT refresh lastActivityTime
            // updateVisuals will animate the mascot to sleep naturally
        }
    }

    func pickAutonomousWalkTarget(now: TimeInterval) {
        guard screenRight > screenLeft + 40 else { return }
        autonomousNextTargetTime = now + Double.random(in: 3.0...6.0)

        // Cancel stale apple seeking
        if isSeekingApples { endAppleSeek(now: now) }
        for i in (0..<apples.count).reversed() where apples[i].isPhantom {
            apples[i].view.removeFromSuperview()
            apples.remove(at: i)
        }

        let roll = Double.random(in: 0...1)

        if level == .window, let petWin = petWindowFrame {
            // ON A WINDOW: only leave after 10s on this window
            let timeOnWindow = now - mascot.windowLandedAt
            if roll < 0.25 && timeOnWindow > 10 {
                // 25% leave (only after 10s) — target outside bounds
                let exit = Bool.random()
                    ? petWin.minX - CGFloat.random(in: 40...200)
                    : petWin.maxX + CGFloat.random(in: 40...200)
                autoTargetX = exit
            } else if roll < 0.40 {
                // 15% sit on edge
                autoTargetX = Bool.random() ? petWin.minX + 5 : petWin.maxX - 5
            } else {
                // 60% walk on window
                autoTargetX = CGFloat.random(in: petWin.minX + 20...petWin.maxX - 20)
            }
        } else {
            // ON GROUND/DOCK: 50% climb to active window, 20% dock, 30% ground
            if roll < 0.50, let win = activeWindowFrame, win.width > 80 {
                let nearestEdge = abs(crabX - win.minX) < abs(crabX - win.maxX) ? win.minX : win.maxX
                autoTargetX = nearestEdge
            } else if roll < 0.70 && level != .dock && dockRight > dockLeft + 20 {
                autoTargetX = CGFloat.random(in: dockLeft + 10...dockRight - 10)
            } else {
                autoTargetX = CGFloat.random(in: screenLeft...screenRight)
            }
        }
    }

    func enterAutonomousMode(now: TimeInterval) {
        isAutonomousMode = true
        autonomousPhase = .walking
        autonomousPhaseStartTime = now
        autonomousNextTargetTime = now + Double.random(in: 0.5...2.0)
        // Wake up the mascot if it was sleeping normally
        if isAsleep {
            isAsleep = false
            wakingUp = true
            lastActivityTime = now
        }
    }

    func exitAutonomousMode(now: TimeInterval) {
        guard isAutonomousMode else {
            lastUserActivityTime = now
            return
        }
        isAutonomousMode = false
        autoTargetX = nil
        lastUserActivityTime = now
        lastActivityTime = now
        if isAsleep {
            isAsleep = false
            wakingUp = true
            lastActivityTime = now
        }
    }

    // MARK: - Pet name

    var petName: String { UserDefaults.standard.string(forKey: "mascotPetName") ?? "" }

    func savePetName(_ name: String) {
        if name.isEmpty {
            UserDefaults.standard.removeObject(forKey: "mascotPetName")
        } else {
            UserDefaults.standard.set(name, forKey: "mascotPetName")
        }
        refreshPetNameMenuItem()
        // Also update status button tooltip
        statusItem?.button?.toolTip = name.isEmpty ? nil : name
    }

    func refreshPetNameMenuItem() {
        let name = petName
        petNameMenuItem?.title = name.isEmpty ? "Name your pet…" : name
        statusItem?.button?.toolTip = name.isEmpty ? nil : name
    }

    @objc func namePetAction() {
        let alert = NSAlert()
        let current = petName
        alert.messageText = current.isEmpty ? "Name your pet" : "Rename your pet"
        alert.informativeText = "The name will appear in the menu bar."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        tf.stringValue = current
        tf.placeholderString = "Enter a name…"
        alert.accessoryView = tf

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let name = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            savePetName(name)
        }
    }

    // MARK: - Auto-walk delay menu

    @objc func setAutoWalkDelay(_ sender: NSMenuItem) {
        UserDefaults.standard.set(Double(sender.tag), forKey: "mascotAutoWalkDelay")
        updateAutoWalkMenuCheckmarks()
        if isAutonomousMode { exitAutonomousMode(now: CACurrentMediaTime()) }
        lastUserActivityTime = CACurrentMediaTime()
    }

    func updateAutoWalkMenuCheckmarks() {
        guard let submenu = autoWalkDelayMenuItem?.submenu else { return }
        let saved = UserDefaults.standard.double(forKey: "mascotAutoWalkDelay")
        // 0 = not-yet-set → default is 300 s
        let active: Double = saved == 0 ? 300 : saved
        for item in submenu.items where !item.isSeparatorItem {
            item.state = Double(item.tag) == active ? .on : .off
        }
    }

    // MARK: - Window visibility check

    /// Returns true if the pet's window is the topmost at the pet's position
    // MARK: - Phantom Apples (invisible navigation lures)

    func dropPhantomApple() {
        guard window != nil else { return }
        let topWindows = Array(visibleWindowFrames.prefix(4)).filter { $0.width > 100 && $0.height > 80 }

        let appleView = AppleView(frame: NSRect(x: 0, y: 0, width: appleSize, height: appleSize))
        appleView.wantsLayer = true
        appleView.layer?.backgroundColor = NSColor.clear.cgColor
        appleView.alphaValue = 0  // invisible
        window.contentView?.addSubview(appleView)

        var apple = AppleState(view: appleView)
        apple.isPhantom = true
        apple.phase = .resting  // already settled
        apple.bounceCount = 99  // prevent re-bouncing

        let roll = Float.random(in: 0...1)
        if roll < 0.5, let win = topWindows.randomElement() {
            // Place on top of a window
            apple.x = CGFloat.random(in: win.minX + 20...win.maxX - 20)
            apple.y = computeWindowFloorY(for: win) - APPLE_PADDING
            apple.floorY = apple.y
        } else if roll < 0.7 && dockRight > dockLeft + 20 {
            // Place on dock
            apple.x = CGFloat.random(in: dockLeft + 10...dockRight - 10)
            apple.y = dockFloorY - APPLE_PADDING
            apple.floorY = apple.y
        } else {
            // Place on ground
            apple.x = CGFloat.random(in: screenLeft + 50...screenRight - 50)
            apple.y = groundFloorY - APPLE_PADDING
            apple.floorY = apple.y
        }

        apples.append(apple)
    }

    func isPetWindowOnTop(_ petWin: NSRect) -> Bool {
        // Check if any window in visibleWindowFrames is ABOVE petWin at the pet's X position
        // visibleWindowFrames is ordered from front to back (CGWindowList order)
        for f in visibleWindowFrames {
            // Skip the pet's own window
            if abs(f.midX - petWin.midX) < 50 && abs(f.midY - petWin.midY) < 50 { return true }
            // If another window covers the pet's position, pet is hidden
            if f.contains(CGPoint(x: mascot.x, y: mascot.y + mascot.spriteH * 0.5)) {
                return false  // another window is in front
            }
        }
        return true  // no window covers the pet
    }

    // MARK: - Breeding (self-replication)

    func spawnCloneIfAllowed() {
        DispatchQueue.global(qos: .utility).async {
            // Count existing PTS instances
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            task.arguments = ["-x", "PTS"]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice
            try? task.run()
            task.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let count = output.components(separatedBy: "\n").filter { !$0.isEmpty }.count

            guard count < 3 else { return } // max 3 instances

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                // Brief split animation
                self.mascot.setExpression(.excited, duration: 1.5)
                self.claudeView.scaleX = 1.3
                self.particleSystem?.emitStar(at: CGPoint(x: self.mascot.x, y: self.mascot.y + self.mascot.spriteH))

                // Launch clone after short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if let appURL = Bundle.main.bundleURL as URL? {
                        NSWorkspace.shared.openApplication(
                            at: appURL,
                            configuration: NSWorkspace.OpenConfiguration()
                        ) { _, _ in }
                    }
                }
            }
        }
    }
}
