import SwiftUI

struct CompactRadarButton: View {
    let snapshot: ResetRadarSnapshot?
    let loading: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Button(action: action) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if let snapshot, let probability = snapshot.probability(now: context.date) {
                        Text(snapshot.probabilityTitle(now: context.date))
                            .font(EnergyTypography.Mini.caption)
                            .foregroundStyle(snapshot.forecastIsFresh(now: context.date) ? Color.secondary : EnergyVisualStyle.warningAccent)
                        Text("\(probability)%")
                            .font(EnergyTypography.Mini.signal)
                            .monospacedDigit().fixedSize()
                            .foregroundStyle(snapshot.forecastIsFresh(now: context.date) ? EnergyVisualStyle.computeAccent : .primary)
                        Text(snapshot.compactForecastDetail(now: context.date))
                            .font(EnergyTypography.Mini.caption)
                            .monospacedDigit()
                            .foregroundStyle(Color.secondary)
                            .lineLimit(1).minimumScaleFactor(1)
                    } else {
                        Image(systemName: "dot.radiowaves.left.and.right").font(EnergyTypography.Mini.caption)
                        Text(snapshot?.compactText(now: context.date) ?? (loading ? "重置雷达 · 同步中" : "重置雷达 · 暂无数据"))
                            .font(EnergyTypography.Mini.label).lineLimit(1).minimumScaleFactor(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(EnergyTypography.Icon.tiny)
                }
                .foregroundStyle(snapshot?.forecastIsFresh(now: context.date) == true ? EnergyVisualStyle.computeAccent : .secondary)
                .padding(.horizontal, 8).frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .background(hovered ? EnergyVisualStyle.hoverFill : .clear)
            }
            .buttonStyle(.plain).onHover { hovered = $0 }
            .background(CompactActionRegion(target: .radar))
            .help("单击查看重置消息与预测依据，按住可拖动。时间为北京时间；来源预告与概率独立，实际到账以账户额度为准。")
            .accessibilityLabel("查看重置雷达与预测依据")
            .accessibilityValue(snapshot?.compactText(now: context.date) ?? "暂无数据")
        }
    }
}
