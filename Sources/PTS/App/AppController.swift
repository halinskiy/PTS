import Cocoa
import Carbon.HIToolbox

enum AutonomousPhase { case walking, sleeping }

final class AppController: NSObject, NSApplicationDelegate {
    let debugEnabled: Bool
    var window: NSWindow!
    var aboutWindowController: AboutWindowController?
    var accessibilityPrePromptShownThisLaunch = false
    var accessibilityPromptRequestedThisLaunch = false
    var accessibilityPollTimer: Timer?
    var releaseCheckTimer: Timer?
    var claudeView: ClaudeView!
    var shadowView: ShadowView!

    // MARK: - New Architecture Components
    let mascot = MascotEntity()
    let stateMachine = MascotStateMachine()
    let windowTracker = WindowTracker()
    let systemMonitor = SystemMonitor()
    let moodSystem = MoodSystem()
    let progressionSystem = ProgressionSystem()
    var particleSystem: ParticleSystem!
    var inputHandler: InputHandler!
    weak var interactiveView: InteractiveContentView?

    // Legacy bridge properties (delegate to mascot)
    var crabX: CGFloat {
        get { mascot.x }
        set { mascot.x = newValue }
    }
    var crabY: CGFloat {
        get { mascot.y }
        set { mascot.y = newValue }
    }
    var walkSpeed: CGFloat {
        get { mascot.walkSpeed }
        set { mascot.walkSpeed = newValue }
    }
    var lastTime: TimeInterval = 0
    var walkTimer: CGFloat {
        get { mascot.walkTimer }
        set { mascot.walkTimer = newValue }
    }
    var breatheTimer: CGFloat {
        get { mascot.breatheTimer }
        set { mascot.breatheTimer = newValue }
    }
    var settleTimer: CGFloat {
        get { mascot.settleTimer }
        set { mascot.settleTimer = newValue }
    }
    var rawLookDir: CGFloat {
        get { mascot.rawLookDir }
        set { mascot.rawLookDir = newValue }
    }
    var lookDirVelocity: CGFloat {
        get { mascot.lookDirVelocity }
        set { mascot.lookDirVelocity = newValue }
    }
    var eyeLookStep: CGFloat {
        get { mascot.eyeLookStep }
        set { mascot.eyeLookStep = newValue }
    }
    let settleDuration: CGFloat = 0.35
    let drowsyDelay: TimeInterval = 3.0
    let sleepDelay: TimeInterval = 5.0
    var lastActivityTime: TimeInterval {
        get { mascot.lastActivityTime }
        set { mascot.lastActivityTime = newValue }
    }
    var blinkTimer: CGFloat = 0
    var wakingUp: Bool {
        get { mascot.wakingUp }
        set { mascot.wakingUp = newValue }
    }
    var isAsleep: Bool {
        get { mascot.isAsleep }
        set { mascot.isAsleep = newValue }
    }

    var dockLeft: CGFloat = 0
    var dockRight: CGFloat = 0
    var dockFloorY: CGFloat = 0
    var groundFloorY: CGFloat = 0
    var screenLeft: CGFloat = 0
    var screenRight: CGFloat = 0
    var activeWindowFrame: NSRect? = nil  // frontmost window (WindowTracker — for climbing decisions)
    var windowFloorY: CGFloat = 0         // floor of frontmost window (jump target)
    var petWindowFrame: NSRect? = nil     // window pet is physically sitting on
    var petWindowFloorY: CGFloat = 0      // floor Y of petWindowFrame (for stickiness)

    var level: CrabLevel {
        get { mascot.level }
        set { mascot.level = newValue }
    }
    var jumpPhase: JumpPhase {
        get { mascot.jumpPhase }
        set { mascot.jumpPhase = newValue }
    }
    var jumpTimer: CGFloat {
        get { mascot.jumpTimer }
        set { mascot.jumpTimer = newValue }
    }
    var jumpStartY: CGFloat {
        get { mascot.jumpStartY }
        set { mascot.jumpStartY = newValue }
    }
    var jumpEndY: CGFloat {
        get { mascot.jumpEndY }
        set { mascot.jumpEndY = newValue }
    }
    var jumpDirection: CGFloat {
        get { mascot.jumpDirection }
        set { mascot.jumpDirection = newValue }
    }
    var currentJumpHorizontalDistance: CGFloat {
        get { mascot.currentJumpHorizontalDistance }
        set { mascot.currentJumpHorizontalDistance = newValue }
    }
    var landingTravelDirection: CGFloat {
        get { mascot.landingTravelDirection }
        set { mascot.landingTravelDirection = newValue }
    }
    var climbingOnLeft: Bool {
        get { mascot.climbingOnLeft }
        set { mascot.climbingOnLeft = newValue }
    }

    let squishDur: CGFloat = 0.07
    let airDur: CGFloat = 0.28
    let landDur: CGFloat = 0.08
    let jumpArcHeight: CGFloat = 60
    let jumpHorizontalDistance: CGFloat = 180

    var autoTargetX: CGFloat? {
        get { mascot.autoTargetX }
        set { mascot.autoTargetX = newValue }
    }
    let autoThresh: CGFloat = 5
    let settleDelay: TimeInterval = 0.52
    var lastMouseMoveTime: TimeInterval {
        get { mascot.lastMouseMoveTime }
        set { mascot.lastMouseMoveTime = newValue }
    }
    var mouseSettled: Bool {
        get { mascot.mouseSettled }
        set { mascot.mouseSettled = newValue }
    }
    var pendingTargetX: CGFloat? {
        get { mascot.pendingTargetX }
        set { mascot.pendingTargetX = newValue }
    }
    var isSeekingApples: Bool {
        get { mascot.isSeekingApples }
        set { mascot.isSeekingApples = newValue }
    }
    var appleSeekStartTime: TimeInterval {
        get { mascot.appleSeekStartTime }
        set { mascot.appleSeekStartTime = newValue }
    }
    var appleSeekDelay: TimeInterval {
        get { mascot.appleSeekDelay }
        set { mascot.appleSeekDelay = newValue }
    }
    var appleSeekTargetID: ObjectIdentifier? {
        get { mascot.appleSeekTargetID }
        set { mascot.appleSeekTargetID = newValue }
    }
    var appleSeekHopTriggers: [CGFloat] {
        get { mascot.appleSeekHopTriggers }
        set { mascot.appleSeekHopTriggers = newValue }
    }

    var spriteW: CGFloat { mascot.spriteW }
    var spriteH: CGFloat { mascot.spriteH }
    var lastDockCheck: TimeInterval = 0
    var lastWindowCheck: TimeInterval = 0
    var lastVisibleWindowsCheck: TimeInterval = 0
    var prevDockFloorY: CGFloat? = nil
    var visibleWindowFrames: [NSRect] = []
    let dockCheckInterval: TimeInterval = 2.0
    let windowCheckInterval: TimeInterval = 0.5 // Faster with AXObserver fallback
    var dockVisible = true

    // MARK: - Autonomous roaming
    var isAutonomousMode = false
    var autonomousPhase: AutonomousPhase = .walking
    var autonomousPhaseStartTime: TimeInterval = 0
    var lastUserActivityTime: TimeInterval = 0
    var autonomousNextTargetTime: TimeInterval = 0

    var statusItem: NSStatusItem!
    var accessibilityMenuItem: NSMenuItem?
    var feedMenuItem: NSMenuItem?
    var aboutMenuItem: NSMenuItem?
    var checkForUpdatesMenuItem: NSMenuItem?
    var petNameMenuItem: NSMenuItem?
    var autoWalkDelayMenuItem: NSMenuItem?
    var globalMouseMonitor: Any?
    var localMouseMonitor: Any?
    var accessibilityFeaturesActive = false
    var updateTimer: Timer?
    var feedHotKeyRef: EventHotKeyRef?
    var hotKeyHandlerRef: EventHandlerRef?
    var lastDebugSnapshot = ""
    var lastDebugSnapshotTime: TimeInterval = 0
    var lastAppSwitchBundleID: String?
    var displayLink: AnyObject?

    var apples: [AppleState] = []
    let appleGravity: CGFloat = -1200
    let appleSize: CGFloat = CGFloat(appleGrid.count) * APPLE_SCALE + APPLE_PADDING * 2
    let appleContactSeparation: CGFloat = 0.70
    let appleContactRowTolerance: CGFloat = 0.5

    // MARK: - Mood/System reaction state
    var lastMoodUpdateTime: TimeInterval = 0
    let moodUpdateInterval: TimeInterval = 0.5
    var systemContext = SystemContext()
    var lastParticleZTime: TimeInterval = 0
    var lastExpressionAnimTime: TimeInterval = 0
    var applesEatenThisFrame = 0
    var recentInteractionCount: Float = 0
    var lastReactionTime: TimeInterval = 0

    // MARK: - Cursor tracking
    var prevCursorX: CGFloat = 0
    var prevCursorY: CGFloat = 0
    var cursorSpeed: CGFloat = 0
    var cursorIdleNearPetTimer: CGFloat = 0

    // MARK: - Anti-oscillation
    var windowClimbCooldown: TimeInterval = 0

    // MARK: - App body language
    enum AppBehavior { case none, watching, coding, vibing }
    var activeAppBehavior: AppBehavior = .none
    var appBehaviorTimer: CGFloat = 0

    // MARK: - Window inertia
    var windowInertiaVelocity: CGVector = .zero
    var windowInertiaDecay: CGFloat = 0.85

    init(debugEnabled: Bool = false) {
        self.debugEnabled = debugEnabled
        super.init()
        setupStateMachine()
        setupSystemCallbacks()
    }

    // MARK: - State Machine Setup

    private func setupStateMachine() {
        let idle = IdleState()
        idle.controller = self
        let walking = WalkingState()
        walking.controller = self
        let sleeping = SleepingState()
        sleeping.controller = self
        let wakingUp = WakingUpState()
        wakingUp.controller = self
        let dragged = DraggedState()
        dragged.controller = self
        let thrown = ThrownState()
        thrown.controller = self

        let wallClimb = WallClimbState()
        wallClimb.controller = self

        stateMachine.register(idle, for: StateKey.idle)
        stateMachine.register(walking, for: StateKey.walking)
        stateMachine.register(sleeping, for: StateKey.sleeping)
        stateMachine.register(wakingUp, for: StateKey.wakingUp)
        stateMachine.register(dragged, for: StateKey.dragged)
        stateMachine.register(thrown, for: StateKey.thrown)
        stateMachine.register(wallClimb, for: StateKey.wallClimb)
    }

    // MARK: - System Monitor Callbacks

    private func setupSystemCallbacks() {
        systemMonitor.onTypingSpeedChanged = { [weak self] speed in
            guard let self = self else { return }
            if speed > 5 && !self.mascot.isAsleep && !self.mascot.isDragged {
                if self.mascot.effectiveExpression != .excited {
                    self.mascot.setExpression(.excited, duration: 2.0)
                }
            }
        }

        systemMonitor.onScreenshot = { [weak self] in
            guard let self = self else { return }
            if !self.mascot.isAsleep {
                self.mascot.setExpression(.happy, duration: 3.0)
                self.particleSystem?.emitStar(at: CGPoint(x: self.mascot.x, y: self.mascot.y + self.mascot.spriteH))
            }
        }

        systemMonitor.onCPUChanged = { [weak self] cpu in
            guard let self = self else { return }
            if cpu > 0.8 && !self.mascot.isAsleep && !self.mascot.isDragged {
                let now = CACurrentMediaTime()
                if now - self.lastReactionTime > 5 {
                    self.lastReactionTime = now
                    self.mascot.setExpression(.scared, duration: 2.0)
                    self.particleSystem?.emitSweat(at: CGPoint(x: self.mascot.x, y: self.mascot.y + self.mascot.spriteH * 0.7))
                }
            }
        }

        // MARK: Battery reaction
        systemMonitor.onLowPowerModeChanged = { [weak self] isLowPower in
            guard let self = self, !self.mascot.isAsleep else { return }
            if isLowPower {
                self.mascot.setExpression(.sad, duration: 2.0)
                self.particleSystem?.emitSweat(at: CGPoint(x: self.mascot.x, y: self.mascot.y + self.mascot.spriteH * 0.7))
            } else {
                self.mascot.setExpression(.happy, duration: 2.0)
                self.particleSystem?.emitStar(at: CGPoint(x: self.mascot.x, y: self.mascot.y + self.mascot.spriteH))
            }
        }

        // MARK: Dark mode reaction
        systemMonitor.onDarkModeChanged = { [weak self] in
            guard let self = self, !self.mascot.isAsleep else { return }
            self.mascot.setExpression(.surprised, duration: 1.5)
        }

        // MARK: App-specific reactions
        systemMonitor.onAppSwitch = { [weak self] appName, bundleID in
            guard let self = self else { return }
            guard !self.mascot.isAsleep && !self.mascot.isDragged && !self.mascot.isThrown else { return }
            let now = CACurrentMediaTime()
            guard now - self.lastReactionTime > 3 else { return }
            guard let bundleID = bundleID, bundleID != self.lastAppSwitchBundleID else { return }
            self.lastAppSwitchBundleID = bundleID

            // Claude Code in terminal override
            let terminalIDs: Set<String> = ["com.apple.Terminal", "com.googlecode.iterm2",
                                            "dev.warp.Warp-Stable", "co.zeit.hyper"]
            if terminalIDs.contains(bundleID) && self.systemMonitor.isClaudeRunning {
                self.lastReactionTime = now
                self.mascot.setExpression(.thinking, duration: 3.0)
                self.particleSystem?.emitStar(at: CGPoint(x: self.mascot.x, y: self.mascot.y + self.mascot.spriteH * 0.8))
                return
            }

            // App reaction table: bundleID → (expression, duration, particle)
            let reactions: [(Set<String>, FaceExpression, CGFloat, Bool)] = [
                // Dev tools → excited
                (["com.apple.dt.Xcode", "com.microsoft.VSCode",
                  "com.todesktop.230313mzl4w4u92", "com.cursor.Cursor"], .excited, 2.0, true),
                // Browsers → thinking
                (["com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox",
                  "company.thebrowser.Browser"], .thinking, 1.5, false),
                // Communication → happy + heart
                (["com.tinyspeck.slackmacgap", "com.hnc.Discord", "ru.keepcoder.Telegram",
                  "com.facebook.archon.developerID"], .happy, 2.0, true),
                // Terminal → thinking
                (terminalIDs, .thinking, 2.0, false),
                // Music → happy
                (["com.apple.Music", "com.spotify.client"], .happy, 2.5, false),
            ]

            // App body language mapping
            let browserIDs: Set<String> = ["com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox",
                                           "company.thebrowser.Browser"]
            let editorIDs: Set<String> = ["com.apple.dt.Xcode", "com.microsoft.VSCode",
                                          "com.todesktop.230313mzl4w4u92", "com.cursor.Cursor"]
            let musicIDs: Set<String> = ["com.apple.Music", "com.spotify.client"]

            if editorIDs.contains(bundleID) {
                self.activeAppBehavior = .coding
            } else if browserIDs.contains(bundleID) {
                self.activeAppBehavior = .watching
            } else if musicIDs.contains(bundleID) {
                self.activeAppBehavior = .vibing
            } else {
                self.activeAppBehavior = .none
            }
            self.appBehaviorTimer = 0

            for (ids, expression, duration, hasParticle) in reactions {
                if ids.contains(bundleID) {
                    self.lastReactionTime = now
                    self.mascot.setExpression(expression, duration: duration)
                    if hasParticle {
                        let pt = CGPoint(x: self.mascot.x, y: self.mascot.y + self.mascot.spriteH * 0.8)
                        if expression == .happy {
                            self.particleSystem?.emitHeart(at: pt)
                        } else {
                            self.particleSystem?.emitStar(at: pt)
                        }
                    }
                    break
                }
            }
        }

        // MARK: Notification banner reaction
        systemMonitor.onNotificationBanner = { [weak self] in
            guard let self = self else { return }
            guard !self.mascot.isDragged else { return }
            let now = CACurrentMediaTime()
            guard now - self.lastReactionTime > 2 else { return }
            self.lastReactionTime = now

            if self.level == .window && !self.mascot.isThrown && self.jumpPhase == .none {
                // On window → fall off scared
                self.mascot.velocityX = CGFloat.random(in: -200...200)
                self.mascot.velocityY = 500
                self.mascot.setExpression(.scared, duration: 2.0)
                self.mascot.noWindowLandingUntil = now + 2.5
                self.windowClimbCooldown = now + 2.5
                self.stateMachine.forceTransition(to: StateKey.thrown, mascot: self.mascot)
            } else if !self.mascot.isThrown && self.jumpPhase == .none {
                // On ground/dock → startled jump
                self.mascot.setExpression(.surprised, duration: 2.0)
                self.startInPlaceJump()
                self.particleSystem?.emitStar(at: CGPoint(x: self.mascot.x, y: self.mascot.y + self.mascot.spriteH))
            }

            // Wake up if sleeping
            if self.mascot.isAsleep {
                self.mascot.isAsleep = false
                self.mascot.wakingUp = false
                self.mascot.lastActivityTime = now
            }
        }

        // onWindowMoved disabled — AX tracks wrong windows from other Spaces.
        // Window movement detection handled by visibleWindowFrames polling (petWindowFrame rect check).
        windowTracker.onWindowMoved = { _, _ in }

        windowTracker.onWindowChanged = { [weak self] frame in
            guard let self = self else { return }
            // visibleWindowFrames.first is the single source of truth for activeWindowFrame
            _ = frame
        }

        windowTracker.onWindowResized = { _ in }
    }
}
