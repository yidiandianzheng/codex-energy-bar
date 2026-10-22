import SwiftUI

struct CompactQuotaButton: View {
    let limits: [QuotaLimitReading]
    let error: String?
    let action: () -> Void
    @State<Bool> private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Circle().fill(Color.secondary)
                        .frame(width: 4, height: 4).accessibilityHidden(true)
                    Text(featured?.title ?? "账户额度").lineLimit(1)
                    if limits.count > 1 { Text("+\(limits.count - 1)") }
                    Spacer(minLength: 2)
                    Text(resetCaption).font(EnergyTypography.Mini.caption).lineLimit(1)
                        .minimumScaleFactor(0.8)
                }.font(EnergyTypography.Mini.label).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(featured?.remainingPercent.map(String.init) ?? "—")
                        .font(EnergyTypography.Mini.value)
                        .foregroundStyle(.primary)
                    if featured?.remainingPercent != nil {
                        Text("%").font(EnergyTypography.Mini.unit).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 5).contentShape(Rectangle())
            .background(hovered ? EnergyVisualStyle.hoverFill : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .background(CompactActionRegion(target: .quota))
        .buttonStyle(EnergyPressStyle()).onHover { hovered = $0 }
        .animation(reduceMotion ? nil : EnergyVisualStyle.quickAnimation, value: hovered)
        .help("单击查看额度，按住拖动 · \(EnergyLogic.compactResetDateText(featured?.resetsAt)) 重置").accessibilityLabel("查看账户额度")
        .accessibilityValue("\(featured?.title ?? "账户额度")，剩余 \(featured?.remainingPercent.map { "\($0)%" } ?? "暂不可用")，\(error ?? EnergyLogic.shortResetText(until: featured?.resetsAt))")
    }
    private var resetCaption: String {
        guard error == nil else { return "同步失败" }
        guard featured?.resetsAt != nil else { return "待同步" }
        return EnergyLogic.shortResetText(until: featured?.resetsAt)
            .replacingOccurrences(of: "约", with: "")
            .replacingOccurrences(of: "后重置", with: "后")
    }
    private var featured: QuotaLimitReading? { limits.first { $0.id == "codex-primary" } ?? limits.first }
}
