import SwiftUI

struct CompactCountdownButton: View {
    let snapshot: ResetRadarSnapshot?
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Button(action: action) {
                HStack(spacing: 5) {
                    Image(systemName: "timer").font(EnergyTypography.Icon.compact)
                        .foregroundStyle(.secondary)
                    if let target = snapshot?.countdownTarget(now: context.date), target > context.date {
                        Text("来源预告倒计时")
                            .font(EnergyTypography.Mini.label).foregroundStyle(.secondary).fixedSize()
                    }
                    Text(snapshot?.countdownValue(now: context.date) ?? "预告待更新")
                        .font(EnergyTypography.Mini.signal)
                        .foregroundStyle(.primary)
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(EnergyVisualStyle.computeAccent)
                .padding(.horizontal, 8).frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .background(hovered ? EnergyVisualStyle.hoverFill : .clear)
            }
            .buttonStyle(.plain).onHover { hovered = $0 }
            .background(CompactActionRegion(target: .radar))
            .help("按来源预告时刻倒数；单击查看依据，按住拖动窗口。实际到账仍需确认。")
            .accessibilityLabel("来源预告倒计时，查看预告依据")
            .accessibilityValue(snapshot?.countdownText(now: context.date) ?? "预告待更新")
        }
    }
}
