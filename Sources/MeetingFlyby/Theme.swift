import Cocoa

/// Shared visual language. Each character carries its own accent color, so picking a pet
/// re-tints the whole app — chips, links, banner — instead of everything being system blue.
enum Theme {
    static func accent(for character: String) -> NSColor {
        switch character {
        case "🐶": return NSColor(calibratedRed: 0.96, green: 0.62, blue: 0.16, alpha: 1) // amber
        case "🐱": return NSColor(calibratedRed: 1.00, green: 0.44, blue: 0.33, alpha: 1) // coral
        case "🐷": return NSColor(calibratedRed: 1.00, green: 0.42, blue: 0.62, alpha: 1) // bubblegum
        case "🐰": return NSColor(calibratedRed: 0.61, green: 0.49, blue: 0.87, alpha: 1) // lavender
        default:   return NSColor(calibratedRed: 1.00, green: 0.44, blue: 0.33, alpha: 1)
        }
    }

    /// A deeper shade of the same hue, for gradients and text on light fills.
    static func accentDeep(for character: String) -> NSColor {
        accent(for: character).blended(withFraction: 0.28, of: .black) ?? accent(for: character)
    }

    static var currentCharacter: String {
        UserDefaults.standard.string(forKey: "character") ?? "🐶"
    }

    static var accent: NSColor { accent(for: currentCharacter) }
    static var accentDeep: NSColor { accentDeep(for: currentCharacter) }

    /// Rounded system font — friendlier than the default, still native.
    static func rounded(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }
}
