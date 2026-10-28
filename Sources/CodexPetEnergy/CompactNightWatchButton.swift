import SwiftUI

/// Mini 条上的一键 AI 通宵（夜间 AI 通宵模式）。开启后系统保持唤醒、屏幕立即关闭，
/// AI 后台任务继续运行。这一行常驻，避免模式入口被收进菜单；再次点击同一行关闭。
struct CompactNightWatchButton: View {
    let isActive: Bool
    let elapsedText: String?
    var notice: String? = nil
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: isActive ? "moon.fill" : "moon")
                    .font(EnergyTypography.Icon.compact)
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
                    .accessibilityHidden(true)
                Text("AI 通宵")
                    .font(EnergyTypography.Mini.caption)
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
                    .fixedSize()
                Text(isActive ? (elapsedText ?? "已开启") : (notice ?? "关屏后 AI 继续跑"))
                    .font(EnergyTypography.Mini.caption)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text(isActive ? "关闭" : "开启")
                    .font(EnergyTypography.Mini.label)
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(isActive ? EnergyVisualStyle.elevatedFill : Color.clear)
                    )
                    .overlay(
                        Capsule().stroke(EnergyVisualStyle.statusChipStroke, lineWidth: 0.5)
                    )
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(hovered ? EnergyVisualStyle.hoverFill : .clear)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .background(CompactActionRegion(target: .nightWatch))
        .help(helpText)
        .accessibilityLabel(isActive ? "关闭 AI 通宵" : "开启 AI 通宵")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        if isActive { return "系统保持唤醒，屏幕可以关闭" }
        return notice ?? "关屏后 AI 后台任务继续运行"
    }

    private var helpText: String {
        if isActive {
            return "AI 通宵已开启：系统保持唤醒，屏幕可以关闭，AI 后台任务继续运行。点击关闭。建议连接电源；使用电池且电量不高于 15% 时会自动关闭；合上 MacBook 上盖仍会休眠，请保持开盖。"
        }
        return "开启后系统保持唤醒并立即关闭显示器，AI 后台任务继续运行；再次点击关闭。建议连接电源；使用电池且电量不高于 15% 时会自动关闭；合上 MacBook 上盖仍会休眠，请保持开盖。"
    }
}
