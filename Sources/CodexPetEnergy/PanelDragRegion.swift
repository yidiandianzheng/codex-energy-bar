import AppKit
import SwiftUI

/// Marks the real header layout without taking keyboard, hover or accessibility events.
struct PanelDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> PanelDragRegionView {
        let view = PanelDragRegionView()
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ view: PanelDragRegionView, context: Context) {}
}

final class PanelDragRegionView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}
