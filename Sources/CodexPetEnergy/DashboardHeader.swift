import SwiftUI

struct DashboardHeader: View {
    let lastUpdated: Date?
    let isRefreshing: Bool
    let refreshError: String?
    let sourceTitle: String
    let refresh: () -> Void
    let showMore: () -> Void
    let collapse: () -> Void
    var version: AppVersionInfo = .current

    var body: some View {
        HStack(spacing: 11) {
            HStack(spacing: 11) {
                AppBrandIcon().frame(width: 36, height: 36).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("算力环").font(EnergyTypography.Detail.title)
                    HStack(spacing: 5) {
                        Image(systemName: refreshError == nil ? "circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(.secondary)
                            .font(refreshError == nil ? EnergyTypography.Icon.statusDot : EnergyTypography.Icon.small)
                            .frame(width: 8, height: 8).accessibilityHidden(true)
                        Text(statusText).font(EnergyTypography.Detail.caption).foregroundStyle(refreshError == nil ? Color.secondary : EnergyVisualStyle.warningAccent)
                            .lineLimit(1).help(statusText)
                    }
                    Text(version.summaryText)
                        .font(EnergyTypography.Detail.meta)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .help(version.helpText)
                        .accessibilityLabel(version.helpText)
                }
                Spacer(minLength: 4)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .background(PanelDragRegion())
            .help("按住此处拖动窗口")
            HStack(spacing: 1) {
                ToolbarActionButton(title: "刷新当前页", symbol: "arrow.clockwise", isLoading: isRefreshing, action: refresh)
                ToolbarActionButton(title: "更多设置", symbol: "ellipsis", action: showMore)
                ToolbarActionButton(title: "收起面板", symbol: "chevron.down", action: collapse)
            }
        }
        .padding(.horizontal, EnergyVisualStyle.panelInset)
        .frame(height: EnergyVisualStyle.headerHeight)
    }
    private var statusText: String {
        if isRefreshing { return "正在同步\(sourceTitle)" }
        if let refreshError { return refreshError }
        guard let lastUpdated else { return "正在读取\(sourceTitle)" }
        return "\(sourceTitle) · \(lastUpdated.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "zh_CN"), timeZone: TimeZone(identifier: "Asia/Shanghai")!))) 更新"
    }
}
