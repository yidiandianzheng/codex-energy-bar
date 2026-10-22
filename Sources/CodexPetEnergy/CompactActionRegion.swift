import AppKit
import SwiftUI

/// A noninteractive layout marker. The SwiftUI Button retains keyboard/AX actions.
struct CompactActionRegion: NSViewRepresentable {
    let target: EnergyPanelMode

    func makeNSView(context: Context) -> CompactActionRegionView {
        let view = CompactActionRegionView()
        view.setAccessibilityElement(false)
        view.target = target
        return view
    }

    func updateNSView(_ view: CompactActionRegionView, context: Context) {
        view.target = target
    }
}
