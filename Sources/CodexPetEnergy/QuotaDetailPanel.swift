import SwiftUI

struct QuotaDetailPanel: View {
    let limits: [QuotaLimitReading]
    let resetCredits: RateLimitResetCreditsSummary?
    let lastUpdated: Date?
    let refreshError: String?

    var body: some View {
        VStack(spacing: 12) {
            if limits.isEmpty && resetCredits == nil {
                PanelEmptyState(title: lastUpdated == nil ? "正在连接账户" : "暂无可用额度",
                    systemImage: "gauge", description: refreshError ?? "等待 Codex 返回账户额度，未返回的模型额度不会占位。")
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(limits) { limit in
                            QuotaLimitRow(reading: limit, subtitle: "\(EnergyLogic.windowDurationText(limit.windowDurationMins))周期",
                                systemImage: "gauge.with.dots.needle.50percent", identityColor: EnergyVisualStyle.computeAccent)
                        }
                        QuotaResetCreditsCard(summary: resetCredits)
                    }
                }
            }
            Text(refreshError ?? "账户额度与本地 Token 独立计量")
                .font(EnergyTypography.Detail.caption).foregroundStyle(refreshError == nil ? Color.secondary : EnergyVisualStyle.warningAccent)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, EnergyVisualStyle.panelInset)
        .padding(.bottom, EnergyVisualStyle.panelInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
