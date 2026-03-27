import Cocoa

let SCALE: CGFloat = 3

// Base palette (constants — used by MascotTheme for hue rotation)
enum AppConstants {
    static let baseBodyColor = NSColor(red: 0.20, green: 0.45, blue: 0.85, alpha: 1)
    static let baseScreenColor = NSColor(red: 0.45, green: 0.90, blue: 1.00, alpha: 1)
    static let baseShadowColor = NSColor(red: 0.15, green: 0.35, blue: 0.70, alpha: 1)
}

// Active colors — read from theme (hue-shifted)
var bodyColor: NSColor { MascotTheme.shared.bodyColor }
var screenColor: NSColor { MascotTheme.shared.screenColor }
var shadowColor: NSColor { MascotTheme.shared.shadowColor }
let eyeColor = NSColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1)

let SHADOW_FLOOR_MARGIN: CGFloat = 24
let SHADOW_VIEW_HEIGHT: CGFloat = 6 * SCALE + SHADOW_FLOOR_MARGIN

// Claude Mascot Body (10x7)
// 1 = Body, 2 = Screen
let bodyGrid: [[Int]] = [
    [0, 1, 1, 1, 1, 1, 1, 1, 1, 0], // Top
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 1], // Sides
    [1, 1, 2, 2, 2, 2, 2, 2, 1, 1], // Screen
    [1, 1, 2, 2, 2, 2, 2, 2, 1, 1], // Screen
    [1, 1, 2, 2, 2, 2, 2, 2, 1, 1], // Screen
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 1], // Bottom Body
    [0, 1, 1, 1, 1, 1, 1, 1, 1, 0], // Bottom Edge
]

let legsIdle: [[Int]] = [
    [0, 1, 0, 0, 0, 0, 0, 0, 1, 0],
    [0, 1, 0, 0, 0, 0, 0, 0, 1, 0],
]

let legsWalk: [[Int]] = [
    [1, 0, 0, 0, 0, 0, 0, 0, 0, 1],
    [1, 0, 0, 0, 0, 0, 0, 0, 0, 1],
]

let legsSquish: [[Int]] = [
    [1, 0, 0, 0, 0, 0, 0, 0, 0, 1],
    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
]

let legsRising: [[Int]] = [
    [0, 0, 1, 0, 0, 0, 0, 1, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
]

let legsFalling: [[Int]] = [
    [0, 1, 0, 0, 0, 0, 0, 0, 1, 0],
    [0, 1, 0, 0, 0, 0, 0, 0, 1, 0],
]

let legsLand: [[Int]] = [
    [1, 0, 0, 0, 0, 0, 0, 0, 0, 1],
    [1, 0, 0, 0, 0, 0, 0, 0, 0, 1],
]

let legsLandRecover: [[Int]] = [
    [1, 0, 0, 0, 0, 0, 0, 0, 0, 1],
    [0, 1, 0, 0, 0, 0, 0, 0, 1, 0],
]

// Apple Constants (Original)
let APPLE_SCALE: CGFloat = 1.5
let APPLE_PADDING: CGFloat = 5
let appleColors: [Int: NSColor] = [
    1: NSColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1),
    2: NSColor(red: 0.16, green: 0.67, blue: 0.38, alpha: 1),
    3: NSColor(red: 0.95, green: 0.02, blue: 0.00, alpha: 1),
    4: NSColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1),
    5: NSColor(red: 0.74, green: 0.02, blue: 0.03, alpha: 1),
]

let appleGrid: [[Int]] = [
    [0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0],
    [0, 0, 0, 0, 0, 1, 0, 1, 2, 2, 2, 2, 1, 0, 0],
    [0, 0, 0, 0, 0, 0, 1, 2, 2, 2, 2, 2, 2, 1, 0],
    [0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0],
    [0, 1, 1, 1, 0, 1, 1, 1, 5, 5, 5, 1, 1, 0, 0],
    [0, 1, 3, 3, 1, 1, 3, 5, 5, 5, 5, 5, 1, 1, 0],
    [1, 3, 4, 3, 3, 3, 3, 3, 3, 5, 5, 5, 5, 1, 0],
    [1, 4, 3, 3, 3, 3, 3, 3, 3, 5, 5, 5, 5, 1, 0],
    [1, 3, 3, 3, 3, 3, 3, 3, 3, 5, 5, 5, 5, 1, 0],
    [1, 3, 3, 3, 3, 3, 3, 3, 3, 5, 5, 5, 5, 1, 0],
    [1, 3, 3, 3, 3, 3, 3, 3, 3, 5, 5, 5, 5, 1, 0],
    [0, 1, 3, 3, 3, 3, 3, 3, 3, 5, 5, 5, 1, 0, 0],
    [0, 0, 1, 5, 3, 3, 3, 3, 5, 5, 5, 1, 0, 0, 0],
    [0, 0, 0, 1, 1, 5, 5, 5, 5, 1, 1, 0, 0, 0, 0],
    [0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0],
]
