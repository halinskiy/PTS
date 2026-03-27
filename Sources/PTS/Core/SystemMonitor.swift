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

    // Callbacks
    var onTypingSpeedChanged: ((Float) -> Void)?
    var onCPUChanged: ((Float) -> Void)?
    var onScreenshot: (() -> Void)?
    var onAppSwitch: ((String) -> Void)?

    // MARK: - Start/Stop

    func startMonitoring() {
        startKeyMonitoring()
        startCPUMonitoring()
        startNotificationMonitoring()
        startAppSwitchMonitoring()
    }

    func stopMonitoring() {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
        cpuTimer?.invalidate()
        cpuTimer = nil
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
                self?.onAppSwitch?(app.localizedName ?? "Unknown")
            }
        }
    }

    deinit {
        stopMonitoring()
    }
}
