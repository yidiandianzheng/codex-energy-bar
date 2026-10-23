import SwiftUI

/// Recommendation strip in the compact bar. Tapping opens the balance page so
/// the full reasoning and per-account levels are one click away.
struct CompactAdviceButton: View {
    let advice: UsageAdvice
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(EnergyTypography.Icon.tiny)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(advice.compactText)
                    .font(EnergyTypography.Mini.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(EnergyTypography.Icon.tiny)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(hovered ? EnergyVisualStyle.hoverFill : .clear)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .background(CompactActionRegion(target: .balance))
        .help("本地规则给出的使用建议：\(advice.detail)")
        .accessibilityLabel("查看使用建议")
        .accessibilityValue(advice.compactText)
    }
}

/// Compact entry to today's local Token page.
struct CompactTokenButton: View {
    let todayTokens: Int?
    let error: String?
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text("今日")
                    .font(EnergyTypography.Mini.caption)
                    .foregroundStyle(.secondary)
                Text(todayTokens.map(TokenFormatting.compact) ?? (error == nil ? "…" : "—"))
                    .font(EnergyTypography.Mini.signal)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(1)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(hovered ? EnergyVisualStyle.hoverFill : .clear)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .background(CompactActionRegion(target: .projects))
        .help("单击查看今日 Token，按住拖动")
        .accessibilityLabel("查看今日用量")
        .accessibilityValue(todayTokens.map { "本机项目今日共 \(TokenFormatting.exact($0)) Token" } ?? "正在读取本机项目 Token")
    }
}
