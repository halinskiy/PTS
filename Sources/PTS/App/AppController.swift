import Cocoa
import Carbon.HIToolbox

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
    var activeWindowFrame: NSRect? = nil
    var windowFloorY: CGFloat = 0

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
    let autoThresh: CGFloat = 15
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
    let dockCheckInterval: TimeInterval = 2.0
    let windowCheckInterval: TimeInterval = 0.5 // Faster with AXObserver fallback
    var dockVisible = true

    var statusItem: NSStatusItem!
    var accessibilityMenuItem: NSMenuItem?
    var feedMenuItem: NSMenuItem?
    var aboutMenuItem: NSMenuItem?
    var globalMouseMonitor: Any?
    var localMouseMonitor: Any?
    var accessibilityFeaturesActive = false
    var updateTimer: Timer?
    var feedHotKeyRef: EventHotKeyRef?
    var hotKeyHandlerRef: EventHandlerRef?
    var lastDebugSnapshot = ""
    var lastDebugSnapshotTime: TimeInterval = 0

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

        stateMachine.register(idle, for: StateKey.idle)
        stateMachine.register(walking, for: StateKey.walking)
        stateMachine.register(sleeping, for: StateKey.sleeping)
        stateMachine.register(wakingUp, for: StateKey.wakingUp)
        stateMachine.register(dragged, for: StateKey.dragged)
        stateMachine.register(thrown, for: StateKey.thrown)
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

        windowTracker.onWindowMoved = { [weak self] frame, delta in
            guard let self = self else { return }
            self.activeWindowFrame = frame
            self.windowFloorY = self.computeWindowFloorY(for: frame)

            guard self.level == .window else { return }
            guard !self.mascot.isDragged && !self.mascot.isThrown else { return }

            let displacement = sqrt(delta.dx * delta.dx + delta.dy * delta.dy)

            // Detach threshold: if window teleports too far, mascot falls off
            if displacement > 80 {
                self.mascot.velocityX = -delta.dx * 0.5
                self.mascot.velocityY = 200
                self.mascot.setExpression(.scared)
                self.stateMachine.forceTransition(to: StateKey.thrown, mascot: self.mascot)
                // Wake up if sleeping
                if self.mascot.isAsleep {
                    self.mascot.isAsleep = false
                    self.mascot.wakingUp = false
                }
                return
            }

            // Ride the window — follow its movement
            self.mascot.x += delta.dx
            self.mascot.y += delta.dy

            // Wake up startled if sleeping and window moves significantly
            if self.mascot.isAsleep && displacement > 5 {
                self.mascot.isAsleep = false
                self.mascot.wakingUp = true
                self.mascot.lastActivityTime = CACurrentMediaTime()
                self.mascot.setExpression(.surprised, duration: 2.0)
                self.particleSystem?.emitStar(at: CGPoint(x: self.mascot.x, y: self.mascot.y + self.mascot.spriteH))
            }

            // If window moves down fast, mascot bounces off temporarily
            if delta.dy < -25 && !self.mascot.isAsleep {
                // Actual mini-throw: pet hops up off the window surface
                let bounceStrength = min(400, -delta.dy * 3)
                self.mascot.velocityX = 0
                self.mascot.velocityY = bounceStrength
                self.mascot.setExpression(.surprised)
                self.stateMachine.forceTransition(to: StateKey.thrown, mascot: self.mascot)
                return
            }

            // Horizontal inertia: slide opposite to window's movement
            if abs(delta.dx) > 10 {
                self.windowInertiaVelocity.dx = -delta.dx * 0.25
                if abs(delta.dx) > 60 {
                    self.mascot.setExpression(.surprised, duration: 1.0)
                    self.mascot.landingShakeTimer = 0.15
                }
            }

            // Keep mascot within window bounds
            if let wf = self.activeWindowFrame {
                self.mascot.x = max(wf.minX + 10, min(wf.maxX - 10, self.mascot.x))
            }
        }

        windowTracker.onWindowChanged = { [weak self] frame in
            guard let self = self else { return }
            let wasOnWindow = self.level == .window
            let hadWindow = self.activeWindowFrame != nil
            self.activeWindowFrame = frame

            if let frame = frame {
                self.windowFloorY = self.computeWindowFloorY(for: frame)
            }

            // Pet was standing on a window that changed (alt-tab, close, minimize)
            if wasOnWindow && !self.mascot.isDragged && !self.mascot.isThrown {
                if frame == nil {
                    // Window disappeared — fall surprised, then seek new active window
                    self.mascot.velocityX = 0
                    self.mascot.velocityY = 0
                    self.mascot.setExpression(.scared)
                    self.mascot.seekActiveWindow = true
                    self.stateMachine.forceTransition(to: StateKey.thrown, mascot: self.mascot)
                } else if hadWindow {
                    // Window changed to a different one (alt-tab) — fall off and seek it
                    self.mascot.velocityX = 0
                    self.mascot.velocityY = 50  // small upward pop
                    self.mascot.setExpression(.surprised)
                    self.mascot.seekActiveWindow = true
                    self.stateMachine.forceTransition(to: StateKey.thrown, mascot: self.mascot)
                }
                if self.mascot.isAsleep {
                    self.mascot.isAsleep = false
                    self.mascot.wakingUp = false
                }
            }
        }

        windowTracker.onWindowResized = { [weak self] frame in
            guard let self = self else { return }
            self.activeWindowFrame = frame
            self.windowFloorY = self.computeWindowFloorY(for: frame)

            guard self.level == .window else { return }
            guard !self.mascot.isDragged && !self.mascot.isThrown else { return }

            // Keep mascot within resized window bounds
            let clampedX = max(frame.minX + 10, min(frame.maxX - 10, self.mascot.x))
            if clampedX != self.mascot.x {
                self.mascot.x = clampedX
            }

            // Update Y to new window floor (window height may have changed)
            self.mascot.y = self.windowFloorY

            // React to resize — surprised wobble
            if !self.mascot.isAsleep {
                self.mascot.setExpression(.surprised, duration: 0.8)
                self.mascot.landingShakeTimer = 0.15
            } else {
                // Wake up if resized significantly
                self.mascot.isAsleep = false
                self.mascot.wakingUp = true
                self.mascot.lastActivityTime = CACurrentMediaTime()
                self.mascot.setExpression(.surprised, duration: 1.5)
            }
        }
    }
}
