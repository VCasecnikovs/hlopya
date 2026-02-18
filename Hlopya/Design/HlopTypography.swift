import SwiftUI

/// Typography scale for Hlopya design system.
/// 6 standard sizes on a 4px baseline grid.
enum HlopTypography {
    static let caption  = Font.system(size: 10)
    static let footnote = Font.system(size: 11)
    static let body     = Font.system(size: 13)
    static let callout  = Font.system(size: 14)
    static let title3   = Font.system(size: 16, weight: .semibold)
    static let title    = Font.system(size: 20, weight: .bold)

    // Monospaced variants for timestamps and timers
    static let monoCaption  = Font.system(size: 10, design: .monospaced)
    static let monoFootnote = Font.system(size: 11, design: .monospaced)
    static let monoBody     = Font.system(size: 13, weight: .medium, design: .monospaced)
    static let monoTimer    = Font.system(size: 14, weight: .medium, design: .monospaced)
}

// MARK: - View Extensions

extension View {
    func hlopTitle() -> some View {
        self.font(HlopTypography.title)
    }

    func hlopTitle3() -> some View {
        self.font(HlopTypography.title3)
    }

    func hlopCallout() -> some View {
        self.font(HlopTypography.callout)
    }

    func hlopBody() -> some View {
        self.font(HlopTypography.body)
    }

    func hlopFootnote() -> some View {
        self.font(HlopTypography.footnote)
    }

    func hlopCaption() -> some View {
        self.font(HlopTypography.caption)
    }
}
