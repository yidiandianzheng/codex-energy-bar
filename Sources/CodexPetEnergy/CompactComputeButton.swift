import SwiftUI

struct CompactComputeButton: View {
    let todayTokens: Int?
    let error: String?
    let action: () -> Void
    @State<Bool> private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Label(error == nil ? "今日 Token" : "同步失败", systemImage: "chart.bar.xaxis")
                    .font(EnergyTypography.Mini.label).foregroundStyle(.secondary).lineLimit(1)
                Text(todayTokens.map(TokenFormatting.compact) ?? (error == nil ? "…" : "—"))
                    .font(EnergyTypography.Mini.value)
                    .foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(width: 68, alignment: .leading).frame(maxHeight: .infinity)
            .padding(.horizontal, 5).contentShape(Rectangle())
            .background(hovered ? EnergyVisualStyle.hoverFill : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .background(CompactActionRegion(target: .projects))
        .buttonStyle(EnergyPressStyle()).onHover { hovered = $0 }
        .animation(reduceMotion ? nil : EnergyVisualStyle.quickAnimation, value: hovered)
        .help("单击查看今日 Token，按住拖动").accessibilityLabel("查看今日算力")
        .accessibilityValue(todayTokens.map { "本机项目今日共 \(TokenFormatting.exact($0)) Token" } ?? "正在读取本机项目 Token")
    }
}
