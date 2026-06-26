import SwiftUI

// Design tokens extracted verbatim from the redesign mockups (WhisperBox Redesign.dc.html).
// The app runs dark-only; these are the source of truth for the UI.

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

enum Theme {
    // Surfaces
    static let window  = Color(hex: 0x1C1C1E)
    static let bar     = Color(hex: 0x191919)   // sidebar / title bar
    static let card    = Color(hex: 0x232325)   // content cards
    static let panel   = Color(hex: 0x151517)   // nested/darker panels (live transcript, segments)
    static let sheet   = Color(hex: 0x202022)   // detail sheet
    static let control = Color(hex: 0x2C2C2E)   // secondary buttons, keycaps
    static let chip    = Color(hex: 0x262628)

    // Borders (white at low opacity)
    static let border       = Color.white.opacity(0.07)
    static let borderSubtle = Color.white.opacity(0.05)
    static let hairline     = Color.white.opacity(0.04)

    // Text
    static let textPrimary   = Color(hex: 0xF5F5F7)
    static let textSecondary = Color(hex: 0x8E8E93)
    static let textTertiary  = Color(hex: 0x636366)
    static let bodyText      = Color(hex: 0xD8D8DC)

    // Accent + semantic
    static let accent     = Color(hex: 0x2F80FF)   // fills, progress, primary buttons, selection
    static let accentText = Color(hex: 0x5E9DFF)   // timestamps, icons, accent labels
    static let red        = Color(hex: 0xFF453A)   // recording
    static let redDim     = Color(hex: 0xFF6961)   // error text / destructive outline
    static let green      = Color(hex: 0x30D158)   // success
    static let gray       = Color(hex: 0xAEAEB2)

    // Geometry
    static let cardRadius: CGFloat   = 12
    static let buttonRadius: CGFloat = 9
    static let chipRadius: CGFloat   = 999

    // Status → badge colors (text, background)
    static func statusColors(_ status: JobStatus) -> (Color, Color) {
        switch status {
        case .running, .pending: return (accentText, accent.opacity(0.16))
        case .success:           return (green, green.opacity(0.15))
        case .error:             return (redDim, red.opacity(0.15))
        case .cancelled:         return (gray, gray.opacity(0.20))
        case .paused:            return (gray, gray.opacity(0.20))
        }
    }
}
