import CoreGraphics

enum EnergyPanelLayout {
    /// Expanded dashboard. Every tab scrolls as a whole page, so this is the
    /// visible viewport rather than a content height: 540 pt keeps the account
    /// summary plus two or three project rows above the fold on the usage tab.
    static let expandedSize = CGSize(width: 420, height: 540)
    /// Account cells sit in a three-column grid so seven accounts (Codex plus
    /// six sources) never squeeze their titles. Width stays 320: three columns
    /// of ~100 pt hold "186.8" and "¥35.9" at the 20 pt headline without
    /// shrinking.
    static let compactBaseSize = CGSize(width: 320, height: 160)
    static let countdownRowHeight: CGFloat = 22
    static let pricingRowHeight: CGFloat = 22
    /// One account row: title + headline + quota-window line.
    static let compactAccountRowHeight: CGFloat = 58
    static let compactAccountColumns = 3
    /// Recommendation row (22) plus radar row (22).
    static let compactFooterHeight: CGFloat = 44

    static func accountRows(for accounts: Int) -> Int {
        let count = max(accounts, 1)
        return (count + compactAccountColumns - 1) / compactAccountColumns
    }

    static func compactBaseSize(accounts: Int = 6, showsCountdown: Bool, showsPricing: Bool = false) -> CGSize {
        let accountHeight = compactAccountRowHeight * CGFloat(accountRows(for: accounts))
        let extra = (showsPricing ? pricingRowHeight : 0) + (showsCountdown ? countdownRowHeight : 0)
        return CGSize(width: compactBaseSize.width, height: accountHeight + compactFooterHeight + extra)
    }

    static func size(
        for mode: EnergyPanelMode,
        accounts: Int = 6,
        compactSize: CompactPanelSize = .load(),
        showsCountdown: Bool = false,
        showsPricing: Bool = false
    ) -> CGSize {
        let scale = compactSize.scale
        guard mode == .compact else {
            return CGSize(width: expandedSize.width * scale, height: expandedSize.height * scale)
        }
        let base = compactBaseSize(accounts: accounts, showsCountdown: showsCountdown, showsPricing: showsPricing)
        return CGSize(
            width: base.width * scale,
            height: base.height * scale
        )
    }
}
