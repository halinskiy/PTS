import Cocoa
import Darwin

// MARK: - System Event Monitor

final class SystemMonitor {
    // Typing speed tracking
    private var keyEventMonitor: Any?
    private var keyTimestamps: [TimeInterval] = []
    private let keyWindowSize: TimeInterval = 2.0 // 2 second rolling window

    // CPU monitoring
    private var cpuTimer: Timer?
    private(set) var cpuUsage: Float = 0
    private var previousCPUInfo: host_cpu_load_info?

    // Notification tracking
    private var notificationObserver: Any?
    private(set) var recentNotificationCount = 0
    private var notificationResetTimer: Timer?

    // Screenshot detection
    private var screenshotObserver: Any?
    private(set) var screenshotDetected = false
    private var screenshotResetTimer: Timer?

    // Computed states
    var typingSpeed: Float {
        let now = CACurrentMediaTime()
        let recentKeys = keyTimestamps.filter { now - $0 < keyWindowSize }
        return Float(recentKeys.count) / Float(keyWindowSize)
    }

    var isTypingFast: Bool { typingSpeed > 5.0 } // >5 keys/sec
    var isCPUHigh: Bool { cpuUsage > 0.8 }
    var isCPULow: Bool { cpuUsage < 0.1 }
    var isIdle: Bool { typingSpeed < 0.5 && cpuUsage < 0.15 }

    // Claude Code process detection
    private var isClaudeActive = false
    private var claudeCheckTimer: Timer?
    var isClaudeRunning: Bool { isClaudeActive }

    // Battery & dark mode
    private(set) var isLowPowerMode = false
    private var batteryCheckTimer: Timer?
    private var darkModeObserver: NSObjectProtocol?

    // Notification banner detection
    private var notificationBannerTimer: Timer?
    private var lastNotificationWindowCount = 0
    private var notificationCooldown: TimeInterval = 0

    // Callbacks
    var onTypingSpeedChanged: ((Float) -> Void)?
    var onCPUChanged: ((Float) -> Void)?
    var onScreenshot: (() -> Void)?
    var onAppSwitch: ((String, String?) -> Void)?  // (appName, bundleIdentifier)
    var onNotificationBanner: (() -> Void)?
    var onLowPowerModeChanged: ((Bool) -> Void)?
    var onDarkModeChanged: (() -> Void)?

    // MARK: - Start/Stop

    /// Monitors that require Accessibility permission
    func startMonitoring() {
        startKeyMonitoring()
        startCPUMonitoring()
        startNotificationMonitoring()
        startAppSwitchMonitoring()
    }

    /// Monitors that work without Accessibility (CGWindowList, process checks, etc.)
    func startNonAXMonitoring() {
        startClaudeMonitoring()
        startBatteryMonitoring()
        startDarkModeMonitoring()
        startNotificationBannerMonitoring()
    }

    func stopMonitoring() {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
        cpuTimer?.invalidate()
        cpuTimer = nil
        claudeCheckTimer?.invalidate()
        claudeCheckTimer = nil
        batteryCheckTimer?.invalidate()
        batteryCheckTimer = nil
        notificationBannerTimer?.invalidate()
        notificationBannerTimer = nil
        if let obs = darkModeObserver {
            DistributedNotificationCenter.default().removeObserver(obs)
            darkModeObserver = nil
        }
        notificationResetTimer?.invalidate()
        screenshotResetTimer?.invalidate()

        if let obs = notificationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            notificationObserver = nil
        }
        if let obs = screenshotObserver {
            DistributedNotificationCenter.default().removeObserver(obs)
            screenshotObserver = nil
        }
    }

    // MARK: - Key Monitoring

    private func startKeyMonitoring() {
        keyEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }
            let now = CACurrentMediaTime()
            self.keyTimestamps.append(now)
            // Prune old timestamps
            self.keyTimestamps = self.keyTimestamps.filter { now - $0 < self.keyWindowSize }
            self.onTypingSpeedChanged?(self.typingSpeed)
        }
    }

    // MARK: - CPU Monitoring

    private func startCPUMonitoring() {
        cpuTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.updateCPU()
        }
        updateCPU()
    }

    private func updateCPU() {
        var numCPU: natural_t = 0
        var cpuLoadInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPU,
            &cpuLoadInfo,
            &numCPUInfo
        )

        guard result == KERN_SUCCESS, let info = cpuLoadInfo else { return }

        var totalUser: Int32 = 0
        var totalSystem: Int32 = 0
        var totalIdle: Int32 = 0

        for i in 0..<Int(numCPU) {
            let offset = Int(CPU_STATE_MAX) * i
            totalUser += info[offset + Int(CPU_STATE_USER)]
            totalSystem += info[offset + Int(CPU_STATE_SYSTEM)]
            totalIdle += info[offset + Int(CPU_STATE_IDLE)]
        }

        let total = Float(totalUser + totalSystem + totalIdle)
        if total > 0 {
            cpuUsage = Float(totalUser + totalSystem) / total
        }

        let size = vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.size)
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)

        onCPUChanged?(cpuUsage)
    }

    // MARK: - Notification Monitoring

    private func startNotificationMonitoring() {
        // Monitor for screenshot via distributed notification
        screenshotObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screencapture.didFinish"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.screenshotDetected = true
            self?.onScreenshot?()
            self?.screenshotResetTimer?.invalidate()
            self?.screenshotResetTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                self?.screenshotDetected = false
            }
        }
    }

    // MARK: - App Switch Monitoring

    private func startAppSwitchMonitoring() {
        notificationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.onAppSwitch?(app.localizedName ?? "Unknown", app.bundleIdentifier)
            }
        }
    }

    // MARK: - Battery Monitoring

    private func startBatteryMonitoring() {
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        batteryCheckTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let current = ProcessInfo.processInfo.isLowPowerModeEnabled
            if current != self.isLowPowerMode {
                self.isLowPowerMode = current
                self.onLowPowerModeChanged?(current)
            }
        }
    }

    // MARK: - Dark Mode Monitoring

    private func startDarkModeMonitoring() {
        darkModeObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onDarkModeChanged?()
        }
    }

    // MARK: - Notification Banner Detection

    private func startNotificationBannerMonitoring() {
        lastNotificationWindowCount = countNotificationWindows()
        notificationBannerTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let now = CACurrentMediaTime()
            let current = self.countNotificationWindows()
            if current > self.lastNotificationWindowCount && now > self.notificationCooldown {
                self.notificationCooldown = now + 3.0
                self.onNotificationBanner?()
            }
            self.lastNotificationWindowCount = current
        }
    }

    private func countNotificationWindows() -> Int {
        // Count all Notification Centre windows (any layer) — banner creates a new one
        let options = CGWindowListOption.optionOnScreenOnly
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return 0 }
        var count = 0
        for info in list {
            guard let owner = info[kCGWindowOwnerName as String] as? String else { continue }
            if owner.contains("Notification") { count += 1 }
        }
        return count
    }

    // MARK: - Claude Code Detection

    private func startClaudeMonitoring() {
        checkClaudeProcess()
        claudeCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkClaudeProcess()
        }
    }

    enum ClaudeActivity { case idle, thinking, coding }
    private(set) var claudeActivity: ClaudeActivity = .idle
    private var lastClaudeCheckModDate: Date?

    private func checkClaudeProcess() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            task.arguments = ["-f", "claude"]  // -f matches full command line (node claude, etc.)
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try? task.run()
            task.waitUntilExit()
            let running = task.terminationStatus == 0

            // Check ~/.claude/ directory for recent activity
            var activity: ClaudeActivity = .idle
            if running {
                let claudeDir = NSHomeDirectory() + "/.claude"
                if let attrs = try? FileManager.default.attributesOfItem(atPath: claudeDir),
                   let modDate = attrs[.modificationDate] as? Date {
                    let age = Date().timeIntervalSince(modDate)
                    if age < 3 {
                        activity = .coding   // very recent = actively generating
                    } else if age < 15 {
                        activity = .thinking // somewhat recent = thinking
                    } else {
                        activity = .thinking // running but idle
                    }
                } else {
                    activity = .thinking
                }
            }

            DispatchQueue.main.async {
                self?.isClaudeActive = running
                self?.claudeActivity = activity
            }
        }
    }

    deinit {
        stopMonitoring()
    }
}
