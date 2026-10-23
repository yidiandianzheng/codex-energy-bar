import AppKit

final class CompactActionRegionView: NSView {
    var target: CompactActionTarget = .quota
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
