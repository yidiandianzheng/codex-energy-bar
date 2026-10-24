import SwiftUI

struct EnergyPanelSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                if reduceTransparency {
                    shape.fill(EnergyVisualStyle.panelBackground)
                } else {
                    EnergyPanelMaterial()
                        .overlay(colorScheme == .dark ? Color.black.opacity(0.10) : Color.white.opacity(0.52))
                }
            }
            .overlay {
                shape.strokeBorder(Color.primary.opacity(contrast == .increased ? 0.3 : 0.09), lineWidth: 0.5)
            }
            .clipShape(shape)
    }
}

extension View {
    func energyPanelSurface(cornerRadius: CGFloat) -> some View {
        modifier(EnergyPanelSurfaceModifier(cornerRadius: cornerRadius))
    }
}
