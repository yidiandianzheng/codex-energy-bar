import AppKit
import SwiftUI

struct EnergyPanelMaterial: NSViewRepresentable {
    /// Fades the whole frosted layer so the desktop shows through it. The
    /// blur itself keeps running, only the resulting pixels are dimmed.
    var opacity: Double = 1.0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.alphaValue = CGFloat(min(max(opacity, 0), 1))
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.alphaValue = CGFloat(min(max(opacity, 0), 1))
    }
}
