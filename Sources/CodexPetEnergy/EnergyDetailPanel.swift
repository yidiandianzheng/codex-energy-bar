import SwiftUI

struct EnergyDetailPanel: View {
    let summary: ProjectUsageDaySummary
    let isLoading: Bool
    let error: String?
    var codexTokens: Int? = nil
    var accountReadings: [BalanceReading] = []
    var todayUsage: TodayUsageSnapshot = .empty

    var body: some View {
        Group {
            if let error, isLoading {
                PanelEmptyState(title: "日志读取失败", systemImage: "exclamationmark.triangle", description: error)
            } else if isLoading {
                PanelEmptyState(
                    title: "正在读取今日项目",
                    systemImage: "arrow.triangle.2.circlepath",
                    description: "首次扫描在后台进行，完成后会自动更新。"
                )
            } else {
                ProjectUsageContent(summary: summary, codexTokens: codexTokens,
                                    accountReadings: accountReadings, todayUsage: todayUsage)
            }
        }
        .padding(.horizontal, EnergyVisualStyle.panelInset)
        .padding(.bottom, EnergyVisualStyle.panelInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
