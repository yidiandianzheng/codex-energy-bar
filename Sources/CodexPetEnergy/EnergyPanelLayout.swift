import CoreGraphics

enum EnergyPanelLayout {
    static let expandedSize = CGSize(width: 420, height: 500)
    /// Up to five account cells plus the drag mark. Wide enough for "186.8"
    /// and "¥35.9" at the 20 pt headline without shrinking the type; client-only
    /// accounts auto-hide, so five cells are the transient all-open case.
    static let compactBaseSize = CGSize(width: 320, height: 110)
    static let countdownRowHeight: CGFloat = 22
    static let pricingRowHeight: CGFloat = 22
    /// Account row: title + headline + quota-window line, with enough slack
    /// that scaled rendering never rounds the hit regions past the window.
    static let compactAccountRowHeight: CGFloat = 66

    static func compactBaseSize(showsCountdown: Bool, showsPricing: Bool = false) -> CGSize {
        let rows = (showsPricing ? pricingRowHeight : 0) + (showsCountdown ? countdownRowHeight : 0)
        return CGSize(width: compactBaseSize.width, height: compactBaseSize.height + rows)
    }

    static func size(
        for mode: EnergyPanelMode,
        compactSize: CompactPanelSize = .load(),
        showsCountdown: Bool = false,
        showsPricing: Bool = false
    ) -> CGSize {
        let scale = compactSize.scale
        guard mode == .compact else {
            return CGSize(width: expandedSize.width * scale, height: expandedSize.height * scale)
        }
        let base = compactBaseSize(showsCountdown: showsCountdown, showsPricing: showsPricing)
        return CGSize(
            width: base.width * scale,
            height: base.height * scale
        )
    }
}
