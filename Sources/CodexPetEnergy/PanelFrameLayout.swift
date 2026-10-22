import CoreGraphics

enum PanelFrameLayout {
    static func clamped(_ proposed: CGRect, to visible: CGRect) -> CGRect {
        let maxX = max(visible.minX, visible.maxX - proposed.width)
        let maxY = max(visible.minY, visible.maxY - proposed.height)
        return CGRect(
            x: min(max(proposed.minX, visible.minX), maxX),
            y: min(max(proposed.minY, visible.minY), maxY),
            width: proposed.width,
            height: proposed.height
        )
    }
}
