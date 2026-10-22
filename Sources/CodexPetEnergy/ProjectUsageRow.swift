import SwiftUI

struct ProjectUsageRow: View {
    let rank: Int
    let project: ProjectUsageReading
    let maxTokens: Int
    @State<Bool> private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(String(format: "%02d", rank)).font(EnergyTypography.Detail.caption.monospacedDigit())
                    .foregroundStyle(EnergyVisualStyle.computeAccent).frame(width: 26, height: 26)
                    .background(EnergyVisualStyle.computeAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.projectName).font(EnergyTypography.Detail.section).lineLimit(1)
                    Text("\(project.totals.turnCount) 条记录 · \(project.lastActivity.formatted(.dateTime.hour().minute()))")
                        .font(EnergyTypography.Detail.caption).foregroundStyle(.secondary).lineLimit(1)
                }.layoutPriority(1)
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(TokenFormatting.compact(project.totals.totalTokens))
                        .font(EnergyTypography.Detail.rowValue)
                    Text("\(Int((share * 100).rounded()))%")
                        .font(EnergyTypography.Detail.caption.monospacedDigit()).foregroundStyle(.secondary)
                }.fixedSize(horizontal: true, vertical: false)
                Image(systemName: "chevron.right").font(EnergyTypography.Icon.compact)
                    .foregroundStyle(.tertiary).opacity(hovered ? 1 : 0.5).accessibilityHidden(true)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(EnergyVisualStyle.hairline)
                    Capsule().fill(EnergyVisualStyle.computeAccent.opacity(0.65))
                        .frame(width: proxy.size.width * share)
                }
            }.frame(height: 3)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: share)
        }
        .padding(.horizontal, 10).padding(.vertical, 12)
        .background(hovered ? EnergyVisualStyle.hoverFill : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle()).onHover { hovered = $0 }
        .animation(reduceMotion ? nil : EnergyVisualStyle.quickAnimation, value: hovered)
        .help("\(project.directory)\n输入 \(TokenFormatting.exact(project.totals.inputTokens)) · 输出 \(TokenFormatting.exact(project.totals.outputTokens))")
        .accessibilityElement(children: .ignore).accessibilityLabel("第 \(rank) 名，\(project.projectName)")
        .accessibilityValue("总 Token \(TokenFormatting.exact(project.totals.totalTokens))，占今日总量 \(Int((share * 100).rounded()))%")
    }
    private var share: Double { maxTokens > 0 ? Double(project.totals.totalTokens) / Double(maxTokens) : 0 }
}
