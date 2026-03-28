import Cocoa

// MARK: - Mascot Theme System
// Manages the mascot's color tint. Hue-shifts the base blue palette.

final class MascotTheme {
    static let shared = MascotTheme()

    struct Preset {
        let name: String
        let hueShift: CGFloat // degrees, 0 = original blue
    }

    static let presets: [Preset] = [
        Preset(name: "Blue",           hueShift: 0),    // base: 214°
        Preset(name: "Teal",           hueShift: -34),  // → 180°
        Preset(name: "Green",          hueShift: -94),  // → 120°
        Preset(name: "Yellow",         hueShift: -154), // → 60°
        Preset(name: "Orange (Default)", hueShift: 176),  // → 30°
        Preset(name: "Red",            hueShift: 146),  // → 0°
        Preset(name: "Pink",           hueShift: 106),  // → 320°
        Preset(name: "Purple",         hueShift: 56),   // → 270°
        Preset(name: "Monochrome",     hueShift: 1000), // special sentinel
    ]

    private(set) var hueShift: CGFloat = 0

    // Computed colors — call these instead of global constants
    private(set) var bodyColor: NSColor = AppConstants.baseBodyColor
    private(set) var screenColor: NSColor = AppConstants.baseScreenColor
    private(set) var shadowColor: NSColor = AppConstants.baseShadowColor

    private init() {
        let saved = UserDefaults.standard.double(forKey: "mascotHueShift")
        // Default to orange (176) if no preference saved yet
        if saved == 0 && !UserDefaults.standard.bool(forKey: "mascotHueShiftSet") {
            hueShift = 176  // orange
        } else {
            hueShift = CGFloat(saved)
        }
        recomputeColors()
    }

    func setHueShift(_ shift: CGFloat) {
        hueShift = shift
        UserDefaults.standard.set(Double(shift), forKey: "mascotHueShift")
        UserDefaults.standard.set(true, forKey: "mascotHueShiftSet")
        recomputeColors()
    }

    private func recomputeColors() {
        if hueShift == 1000 {
            // Monochrome mode
            bodyColor = NSColor(white: 0.35, alpha: 1)
            screenColor = NSColor(white: 0.75, alpha: 1)
            shadowColor = NSColor(white: 0.25, alpha: 1)
        } else {
            bodyColor = AppConstants.baseBodyColor.hueRotated(by: hueShift)
            screenColor = AppConstants.baseScreenColor.hueRotated(by: hueShift)
            shadowColor = AppConstants.baseShadowColor.hueRotated(by: hueShift)
        }
    }
}

// MARK: - NSColor Hue Rotation

extension NSColor {
    func hueRotated(by degrees: CGFloat) -> NSColor {
        guard degrees != 0 else { return self }

        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let rgb = usingColorSpace(.sRGB) ?? self
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)

        let newHue = (h + degrees / 360).truncatingRemainder(dividingBy: 1)
        return NSColor(hue: newHue < 0 ? newHue + 1 : newHue, saturation: s, brightness: b, alpha: a)
    }
}
