import SwiftUI
import UIKit
import TVGuideCore

/// Colours match the Android app (navy + gold). Dynamic: light and dark variants.
enum Palette {
    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
    static let background = dyn(0xF8F9FC, 0x10141C)
    static let surface = dyn(0xFFFFFF, 0x161B26)
    static let surfaceVariant = dyn(0xE3E6EE, 0x232A38)
    static let primary = dyn(0x7A5200, 0xFFC247)
    static let primaryContainer = dyn(0xFFDEA0, 0x3A2D00)
    static let secondaryContainer = dyn(0xD8E4FF, 0x1F3560)
    static let onSurfaceVariant = dyn(0x424754, 0xC3C8D6)
    static let outline = dyn(0x707584, 0x8C93A3)
    static let warning = dyn(0xB3261E, 0xFFB4AB)
    static let warningContainer = dyn(0xF9DEDC, 0x4A1F1B)
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

enum Fmt {
    static let time: DateFormatter = { let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f }()
    static let dayTime: DateFormatter = { let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("EEE h:mm a"); return f }()
    static let full: DateFormatter = { let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f }()
    static func time(_ ms: Int64) -> String { time.string(from: Date(timeIntervalSince1970: TimeInterval(ms) / 1000)) }
    static func dayTime(_ ms: Int64) -> String { dayTime.string(from: Date(timeIntervalSince1970: TimeInterval(ms) / 1000)) }
    static func range(_ p: Program) -> String { "\(time(p.startMillis)) – \(time(p.stopMillis))" }
}
