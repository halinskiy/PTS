import Foundation

// MARK: - Tamagotchi-style Mood System

final class MoodSystem {
    // Core needs (0...1)
    var energy: Float = 0.8
    var happiness: Float = 0.7
    var curiosity: Float = 0.5
    var hunger: Float = 0.0 // grows over time, apples reduce it

    // Derived mood
    var overallMood: Mood {
        if energy < 0.15 { return .exhausted }
        if hunger > 0.8 { return .hungry }
        if happiness > 0.8 && energy > 0.5 { return .ecstatic }
        if happiness > 0.6 { return .happy }
        if curiosity > 0.7 && energy > 0.4 { return .curious }
        if happiness < 0.3 { return .sad }
        if energy < 0.3 { return .tired }
        return .content
    }

    enum Mood: String {
        case ecstatic  // Very happy, bouncy
        case happy     // Normal happy
        case content   // Neutral
        case curious   // Wants to explore
        case tired     // Low energy
        case exhausted // Very low energy
        case hungry    // Wants apples
        case sad       // Low happiness

        var walkSpeedMultiplier: Float {
            switch self {
            case .ecstatic: return 1.3
            case .happy: return 1.1
            case .content: return 1.0
            case .curious: return 1.15
            case .tired: return 0.7
            case .exhausted: return 0.5
            case .hungry: return 0.9
            case .sad: return 0.8
            }
        }

        var preferredExpression: FaceExpression {
            switch self {
            case .ecstatic: return .excited
            case .happy: return .happy
            case .content: return .neutral
            case .curious: return .thinking
            case .tired: return .sleepy
            case .exhausted: return .sleepy
            case .hungry: return .sad
            case .sad: return .sad
            }
        }

        var jumpFrequency: Float {
            switch self {
            case .ecstatic: return 0.3 // 30% chance to random jump
            case .happy: return 0.1
            case .curious: return 0.2
            default: return 0.0
            }
        }

        var idleAnimationVariety: Int {
            switch self {
            case .ecstatic: return 4
            case .happy: return 3
            case .curious: return 3
            case .content: return 2
            default: return 1
            }
        }
    }

    // MARK: - Update

    func update(dt: Float, context: SystemContext) {
        // Energy decays slowly over time
        energy = max(0, energy - dt * 0.0008)

        // Interactions restore energy
        energy = min(1, energy + context.recentInteractions * 0.05)

        // Hunger grows over time
        hunger = min(1, hunger + dt * 0.001)

        // Eating apples reduces hunger and increases happiness
        if context.applesEatenRecently > 0 {
            hunger = max(0, hunger - Float(context.applesEatenRecently) * 0.3)
            happiness = min(1, happiness + Float(context.applesEatenRecently) * 0.15)
            energy = min(1, energy + Float(context.applesEatenRecently) * 0.05)
        }

        // Typing interaction affects curiosity
        if context.typingSpeed > 3 {
            curiosity = min(1, curiosity + dt * 0.01)
            energy = min(1, energy + dt * 0.002)
        }

        // Idle decay
        if context.isIdle {
            curiosity = max(0, curiosity - dt * 0.003)
            happiness = max(0, happiness - dt * 0.0005)
        }

        // Being petted (clicked) increases happiness
        if context.wasPetted {
            happiness = min(1, happiness + 0.1)
            energy = min(1, energy + 0.05)
        }

        // Being thrown decreases happiness slightly
        if context.wasThrown {
            happiness = max(0, happiness - 0.05)
            energy = min(1, energy + 0.1) // But energizing!
        }

        // CPU affects energy (empathy with the machine)
        if context.cpuUsage > 0.8 {
            energy = max(0, energy - dt * 0.002)
        }

        // Screenshot = posing boost
        if context.screenshotDetected {
            happiness = min(1, happiness + 0.2)
        }

        // Natural happiness recovery toward baseline
        let happinessBaseline: Float = 0.5
        happiness += (happinessBaseline - happiness) * dt * 0.001
    }

    // MARK: - Events

    func onAppleEaten() {
        hunger = max(0, hunger - 0.25)
        happiness = min(1, happiness + 0.1)
    }

    func onPetted() {
        happiness = min(1, happiness + 0.15)
        energy = min(1, energy + 0.05)
    }

    func onThrown() {
        happiness = max(0, happiness - 0.05)
        energy = min(1, energy + 0.1)
    }

    func onWokenUp() {
        energy = min(1, energy + 0.3)
        happiness = max(0, happiness - 0.05) // Slightly annoyed
    }

    func onSlept(duration: TimeInterval) {
        let restBonus = Float(min(duration, 30) / 30) * 0.5
        energy = min(1, energy + restBonus)
    }
}

// MARK: - System Context (passed to MoodSystem each frame)

struct SystemContext {
    var typingSpeed: Float = 0
    var cpuUsage: Float = 0
    var isIdle: Bool = true
    var recentInteractions: Float = 0
    var applesEatenRecently: Int = 0
    var wasPetted: Bool = false
    var wasThrown: Bool = false
    var screenshotDetected: Bool = false
}
