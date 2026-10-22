import AppKit

final class EnergyFloatingPanel: NSPanel {
    var collapse: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { collapse?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { collapse?() } else { super.keyDown(with: event) }
    }
}
