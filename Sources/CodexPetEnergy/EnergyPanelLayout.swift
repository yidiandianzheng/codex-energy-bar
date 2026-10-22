import CoreGraphics

enum EnergyPanelLayout {
    static let expandedSize = CGSize(width: 420, height: 500)
    static let compactBaseSize = CGSize(width: 208, height: 62)
    static let countdownRowHeight: CGFloat = 22

    static func compactBaseSize(showsCountdown: Bool) -> CGSize {
        CGSize(width: compactBaseSize.width, height: compactBaseSize.height + (showsCountdown ? countdownRowHeight : 0))
    }

    static func size(
        for mode: EnergyPanelMode,
        compactSize: CompactPanelSize = .load(),
        showsCountdown: Bool = false
    ) -> CGSize {
        let scale = compactSize.scale
        guard mode == .compact else {
            return CGSize(width: expandedSize.width * scale, height: expandedSize.height * scale)
        }
        let base = compactBaseSize(showsCountdown: showsCountdown)
        return CGSize(
            width: base.width * scale,
            height: base.height * scale
        )
    }
}
