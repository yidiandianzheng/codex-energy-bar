import SwiftUI

struct DashboardTabPicker: View {
    let selection: EnergyPanelMode
    let select: (EnergyPanelMode) -> Void
    @Namespace private var selectionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// The pricing page is a sub-page of 总览; keep the parent tab highlighted
    /// so the picker never renders a selected-looking gap.
    private var effectiveSelection: EnergyPanelMode {
        EnergyPanelMode.dashboardModes.contains(selection) ? selection : .balance
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(EnergyPanelMode.dashboardModes, id: \.self) { mode in
                Button { select(mode) } label: {
                    Label(mode.title, systemImage: mode.systemImage)
                        .font(effectiveSelection == mode ? EnergyTypography.Detail.selectedTab : EnergyTypography.Detail.tab)
                        .foregroundStyle(effectiveSelection == mode ? EnergyVisualStyle.computeAccent : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 32).contentShape(Rectangle())
                        .background {
                            if effectiveSelection == mode {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.95))
                                    .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                                    .shadow(color: .black.opacity(0.07), radius: 2, y: 1)
                            }
                        }
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(effectiveSelection == mode ? .isSelected : [])
            }
        }.padding(3)
            .background(EnergyVisualStyle.subtleFill, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .animation(reduceMotion ? nil : EnergyVisualStyle.selectionAnimation, value: selection)
    }
}
