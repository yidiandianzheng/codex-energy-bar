import SwiftUI

enum EnergyVisualStyle {
    static let compactCornerRadius: CGFloat = 10
    static let panelCornerRadius: CGFloat = 26
    static let cardCornerRadius: CGFloat = 16
    static let rowCornerRadius: CGFloat = 12
    static let panelInset: CGFloat = 20
    static let cardInset: CGFloat = 18
    static let spacingTiny: CGFloat = 4
    static let spacingSmall: CGFloat = 8
    static let spacingMedium: CGFloat = 12
    static let spacingLarge: CGFloat = 16
    static let headerHeight: CGFloat = 72

    // Monochrome hierarchy: weight highlights data; symbols and copy communicate status.
    static let computeAccent = Color.primary
    static let modelAccent = computeAccent
    static let warningAccent = Color.primary
    static let panelBackground = Color(nsColor: .windowBackgroundColor)
    static let cardFill = Color(nsColor: .controlBackgroundColor).opacity(0.82)
    static let subtleFill = Color.primary.opacity(0.035)
    static let elevatedFill = Color.primary.opacity(0.055)
    static let hoverFill = Color.primary.opacity(0.06)
    static let selectedFill = Color.primary.opacity(0.065)
    static let hairline = Color.primary.opacity(0.07)
    static let strongHairline = Color.primary.opacity(0.10)
    /// Outline for account status chips: shape and weight carry the state, not hue.
    static let statusChipStroke = Color.primary.opacity(0.16)

    static let quickAnimation = Animation.easeOut(duration: 0.14)
    static let contentAnimation = Animation.easeInOut(duration: 0.20)
    static let selectionAnimation = Animation.interactiveSpring(response: 0.28, dampingFraction: 0.9)
}
