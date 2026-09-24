import SwiftUI

/// Semantic color tokens for Hlopya design system
enum HlopColors {
    // MARK: - Brand / Accent
    static let primary = Color.accentColor

    // MARK: - Recording
    static let recordingDot = Color.red
    static let recordingBadge = Color.red
    static let recordingBorder = Color.red.opacity(0.3)
    static let recordingTint = Color.red.opacity(0.15)
    static let recordingPulse = Color.red.opacity(0.08)

    // MARK: - Status
    static let statusDone = Color.green
    static let statusMe = Color.green
    static let statusSTT = Color.cyan
    static let statusThem = Color.cyan
    static let statusRoom = Color.purple
    static let statusNew = Color.orange
    static let statusWarning = Color.orange
    static let statusProcessing = Color.purple

    // MARK: - Speakers

    /// Me = green, in-room voices (Room N) = purple family, remote voices (Them / Them N) = cyan family
    static func speaker(_ raw: String) -> Color {
        if raw == "Me" || raw == "Vadim" { return statusMe }
        let palette: [Color] = raw.hasPrefix("Room")
            ? [statusRoom, .pink, .brown, .yellow]
            : [.cyan, .blue, .teal, .indigo, .mint]
        let n = Int(raw.split(separator: " ").last ?? "") ?? 1
        return palette[(max(n, 1) - 1) % palette.count]
    }

    // MARK: - Surface
    static let surfaceGlass = Color.clear // glass effect handles this
    static let surfaceSolid = Color(nsColor: .windowBackgroundColor)
    static let surfaceElevated = Color(nsColor: .controlBackgroundColor)
    static let surfaceOverlay = Color(nsColor: .controlBackgroundColor).opacity(0.5)

    // MARK: - Text (map to system)
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)
}
