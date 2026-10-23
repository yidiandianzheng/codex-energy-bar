import SwiftUI

struct PanelDragMark: View {
    var body: some View {
        Image(systemName: "circle.grid.2x2.fill")
            .font(EnergyTypography.Icon.small).foregroundStyle(.tertiary)
            .frame(width: 14).frame(maxHeight: .infinity)
            .contentShape(Rectangle()).help("按住拖动算力环").accessibilityHidden(true)
    }
}
