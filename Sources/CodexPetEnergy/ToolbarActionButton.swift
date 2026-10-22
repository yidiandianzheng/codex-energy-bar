import SwiftUI

struct ToolbarActionButton: View {
    let title: String
    let symbol: String
    var isLoading = false
    let action: () -> Void
    @State<Bool> private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Label(title, systemImage: symbol).labelStyle(.iconOnly)
                        .font(EnergyTypography.Icon.standard)
                }
            }
            .frame(width: 28, height: 28)
            .foregroundStyle(.secondary)
            .background(hovered ? EnergyVisualStyle.hoverFill : .clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(EnergyPressStyle())
        .disabled(isLoading)
        .help(isLoading ? "正在刷新" : title)
        .accessibilityLabel(title)
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : EnergyVisualStyle.quickAnimation, value: hovered)
    }
}
