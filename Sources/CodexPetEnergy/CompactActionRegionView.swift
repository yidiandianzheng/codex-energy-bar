import AppKit

final class CompactActionRegionView: NSView {
    var target: EnergyPanelMode = .quota
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
