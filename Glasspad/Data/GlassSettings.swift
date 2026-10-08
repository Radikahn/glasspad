import SwiftUI
import Observation

/// How the window looks, persisted in UserDefaults.
@Observable
final class GlassSettings {
    /// Tint color in HSB, each 0...1.
    var hue: Double { didSet { save(hue, "hue") } }
    var saturation: Double { didSet { save(saturation, "saturation") } }
    var brightness: Double { didSet { save(brightness, "brightness") } }
    /// How strongly the tint colors the glass.
    var tintLevel: Double { didSet { save(tintLevel, "tintLevel") } }
    /// 0 is a solid window, 0.5 frosted glass, 1 fully clear.
    var transparency: Double { didSet { save(transparency, "transparency") } }
    var showsScrollBar: Bool { didSet { save(showsScrollBar, "showsScrollBar") } }

    /// The original dark purple frosted glass, scroll bar on.
    private enum Default {
        static let hue = 0.741
        static let saturation = 0.725
        static let brightness = 0.40
        static let tintLevel = 0.22
        static let transparency = 0.5
        static let showsScrollBar = true
    }

    init() {
        hue = Self.load("hue") ?? Default.hue
        saturation = Self.load("saturation") ?? Default.saturation
        brightness = Self.load("brightness") ?? Default.brightness
        tintLevel = Self.load("tintLevel") ?? Default.tintLevel
        transparency = Self.load("transparency") ?? Default.transparency
        showsScrollBar = Self.load("showsScrollBar") ?? Default.showsScrollBar
    }

    func reset() {
        hue = Default.hue
        saturation = Default.saturation
        brightness = Default.brightness
        tintLevel = Default.tintLevel
        transparency = Default.transparency
        showsScrollBar = Default.showsScrollBar
    }

    func tint(dimmed factor: Double = 1) -> Color {
        Color(hue: hue, saturation: saturation, brightness: brightness * factor)
    }

    /// The frosted blur fades out across the clear half of the transparency range...
    var blurOpacity: Double { min(1, 2 - 2 * transparency) }

    /// ...and a solid backing fades in across the opaque half.
    var solidOpacity: Double { max(0, 1 - 2 * transparency) }

    private static func load<T>(_ key: String) -> T? {
        UserDefaults.standard.object(forKey: "glass." + key) as? T
    }

    private func save(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: "glass." + key)
    }
}
