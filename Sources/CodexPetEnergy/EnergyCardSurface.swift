import SwiftUI

struct EnergyCardSurface: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background(EnergyVisualStyle.cardFill, in: RoundedRectangle(cornerRadius: EnergyVisualStyle.cardCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: EnergyVisualStyle.cardCornerRadius)
                    .strokeBorder(EnergyVisualStyle.strongHairline.opacity(contrast == .increased ? 3 : 0.6), lineWidth: 0.5)
            }
    }
}

extension View {
    func energyCardSurface() -> some View { modifier(EnergyCardSurface()) }
}
