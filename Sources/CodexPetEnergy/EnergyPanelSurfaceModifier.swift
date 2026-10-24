import SwiftUI

/// How much of the desktop the floating window lets through.
///
/// `.panel` is the expanded dashboard: the user opened it on purpose and reads
/// dense figures there, so the background stays opaque enough to guarantee
/// contrast. `.glance` is the Mini bar, which sits on top of whatever the user
/// is doing all day — it only needs to be readable, never to hide the work
/// behind it, so the tint drops and the material itself fades.
enum EnergyPanelSurfaceStyle {
    case panel
    case glance
}

struct EnergyPanelSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    var style: EnergyPanelSurfaceStyle = .panel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var tint: Double {
        if colorScheme == .dark { return style == .glance ? 0.04 : 0.10 }
        return style == .glance ? 0.26 : 0.52
    }

    /// The blur layer itself fades on the glance surface; the frosted edge that
    /// separates the bar from the desktop comes from the hairline border and a
    /// soft shadow instead of from a heavier tint.
    private var materialOpacity: Double { style == .glance ? 0.78 : 1.0 }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                if reduceTransparency {
                    // Accessibility beats aesthetics: never guess at contrast.
                    shape.fill(EnergyVisualStyle.panelBackground)
                } else {
                    EnergyPanelMaterial(opacity: materialOpacity)
                        .overlay(colorScheme == .dark ? Color.black.opacity(tint) : Color.white.opacity(tint))
                }
            }
            .overlay {
                shape.strokeBorder(Color.primary.opacity(contrast == .increased ? 0.3 : 0.09), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(style == .glance ? 0.10 : 0.16), radius: style == .glance ? 5 : 8, x: 0, y: 1)
            .clipShape(shape)
    }
}

extension View {
    func energyPanelSurface(cornerRadius: CGFloat, style: EnergyPanelSurfaceStyle = .panel) -> some View {
        modifier(EnergyPanelSurfaceModifier(cornerRadius: cornerRadius, style: style))
    }
}
