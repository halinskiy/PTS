import Cocoa

// MARK: - Autonomous roaming + pet name

extension AppController {

    // How many seconds of no mouse movement before autonomous mode kicks in.
    // Stored as a Double in UserDefaults under "mascotAutoWalkDelay".
    // -1 = disabled, 0 (not set) = default 300 s.
    var autonomousIdleThreshold: TimeInterval {
        let saved = UserDefaults.standard.double(forKey: "mascotAutoWalkDelay")
        if saved < 0 { return -1 }          // Never
        return saved > 0 ? saved : 300.0    // default 5 min
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

        switch autonomousPhase {
        case .walking:
            if now - autonomousPhaseStartTime >= 60 {
                // Switch to sleep phase
                autonomousPhase = .sleeping
                autonomousPhaseStartTime = now
                autoTargetX = nil
                // Do NOT refresh lastActivityTime — let updateVisuals trigger sleep naturally
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
            if now - autonomousPhaseStartTime >= 120 {
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
        autonomousNextTargetTime = now + Double.random(in: 5.0...15.0)

        // 15% chance: pick a window edge to sit on (seek cozy spot)
        if Double.random(in: 0...1) < 0.15 {
            let candidates = visibleWindowFrames.filter { $0.width > 100 }
            if let win = candidates.randomElement() {
                // Pick left or right edge
                autoTargetX = Bool.random() ? win.minX + 8 : win.maxX - 8
                return
            }
        }

        let roll = Double.random(in: 0...1)

        // 40% — pick a point on a visible window (excluding current one)
        if roll < 0.40 {
            let candidates = visibleWindowFrames.filter { f in
                guard f.width > 80 else { return false }
                if level == .window, let petWin = petWindowFrame {
                    return abs(f.midX - petWin.midX) > 80  // not the same window
                }
                return true
            }
            if let win = candidates.randomElement() {
                let margin: CGFloat = 30
                let lo = win.minX + margin
                let hi = win.maxX - margin
                if lo < hi {
                    autoTargetX = CGFloat.random(in: lo...hi)
                    return
                }
            }
        }

        // 20% — target dock (if not already there and dock is visible)
        if roll < 0.60 && level != .dock && dockRight > dockLeft + 20 {
            autoTargetX = CGFloat.random(in: dockLeft + 10...dockRight - 10)
            return
        }

        // 40% — random ground position
        autoTargetX = CGFloat.random(in: screenLeft...screenRight)
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
