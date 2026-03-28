import Foundation

// MARK: - Tamagotchi Progression & Trust System

final class ProgressionSystem {
    private let defaults = UserDefaults.standard

    // Lifetime stats
    private(set) var daysAlive: Int = 0
    private(set) var totalInteractions: Int = 0
    private(set) var applesEaten: Int = 0
    private(set) var timesThrown: Int = 0
    private(set) var distanceWalked: CGFloat = 0

    // Trust: 0-100, gates behaviors
    private(set) var trustLevel: Float = 30

    // Computed trust tiers
    var petApproachesCursor: Bool { trustLevel > 30 }   // sniff behavior
    var petSeeksUser: Bool { trustLevel > 50 }           // walks toward active window
    var easyPetting: Bool { trustLevel > 70 }            // 1 click for love instead of 3
    var closeFollow: Bool { trustLevel > 90 }            // follows cursor closer

    init() { load() }

    // MARK: - Events

    func recordInteraction() {
        totalInteractions += 1
        trustLevel = min(100, trustLevel + 1.5)
        save()
    }

    func recordPetting() {
        totalInteractions += 1
        trustLevel = min(100, trustLevel + 2.5)
        save()
    }

    func recordThrow(hard: Bool) {
        timesThrown += 1
        trustLevel = max(0, trustLevel - (hard ? 3 : 1))
        save()
    }

    func recordAppleEaten() {
        applesEaten += 1
        trustLevel = min(100, trustLevel + 0.5)
        save()
    }

    func recordDistanceWalked(_ dx: CGFloat) {
        distanceWalked += abs(dx)
        // Save every ~500px to avoid excessive writes
        if Int(distanceWalked) % 500 < 2 {
            defaults.set(Double(distanceWalked), forKey: "pts.distanceWalked")
        }
    }

    /// Call once per hour for natural trust decay
    func hourlyDecay() {
        trustLevel = max(0, trustLevel - 0.3)
        save()
    }

    // MARK: - Persistence

    private func save() {
        defaults.set(totalInteractions, forKey: "pts.totalInteractions")
        defaults.set(applesEaten, forKey: "pts.applesEaten")
        defaults.set(timesThrown, forKey: "pts.timesThrown")
        defaults.set(Double(distanceWalked), forKey: "pts.distanceWalked")
        defaults.set(Double(trustLevel), forKey: "pts.trustLevel")

        // Track first launch date for daysAlive
        if defaults.object(forKey: "pts.firstLaunch") == nil {
            defaults.set(Date(), forKey: "pts.firstLaunch")
        }
    }

    private func load() {
        totalInteractions = defaults.integer(forKey: "pts.totalInteractions")
        applesEaten = defaults.integer(forKey: "pts.applesEaten")
        timesThrown = defaults.integer(forKey: "pts.timesThrown")
        distanceWalked = CGFloat(defaults.double(forKey: "pts.distanceWalked"))
        trustLevel = Float(defaults.double(forKey: "pts.trustLevel"))
        if trustLevel == 0 && totalInteractions == 0 { trustLevel = 30 } // default for new pet

        if let firstLaunch = defaults.object(forKey: "pts.firstLaunch") as? Date {
            daysAlive = Calendar.current.dateComponents([.day], from: firstLaunch, to: Date()).day ?? 0
        }
    }
}
