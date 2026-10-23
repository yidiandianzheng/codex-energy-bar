import SwiftUI

/// Each account retains its native unit; a failed source never hides other rows.
struct AccountOverviewPanel: View {
    let readings: [BalanceReading]
    let advice: UsageAdvice
    let todayUsage: TodayUsageSnapshot
    let lastUpdated: Date?
    let refreshError: String?
    let isLoading: Bool
    let select: (String) -> Void
    @State private var explainsData = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(advice.headline).font(EnergyTypography.Detail.section)
                    Text(advice.detail).font(EnergyTypography.Detail.body).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Text("账户 / 状态").frame(width: 94, alignment: .leading)
                        Text("剩余").frame(maxWidth: .infinity, alignment: .trailing)
                        Text("用量").frame(width: 78, alignment: .trailing)
                        Text("恢复").frame(width: 68, alignment: .trailing)
                    }
                    .font(EnergyTypography.Detail.caption).foregroundStyle(.secondary).padding(.bottom, 10)
                    ForEach(readings) { reading in
                        Divider()
                        Button { select(reading.id) } label: { row(reading) }
                            .buttonStyle(EnergyPressStyle())
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("查看\(reading.title)账户详情")
                            .accessibilityValue("\(status(reading))，剩余\(remaining(reading))，\(usage(reading))，恢复\(reset(reading))")
                    }
                }
                DisclosureGroup("数据说明", isExpanded: $explainsData) {
                    Text("Codex 为本机今日 Token；DeepSeek 为本机今日余额减少；豆包为本窗口已用百分比；WorkBuddy 为本机今日观测值，身份未确认时未知。各项独立计量，缺少样本显示 —。旧数据保留上次读数，不参与推荐。")
                        .font(EnergyTypography.Detail.caption).foregroundStyle(.secondary).padding(.top, 5)
                }.font(EnergyTypography.Detail.caption)
            }.padding(.horizontal, EnergyVisualStyle.panelInset).padding(.bottom, 18)
        }
    }

    private func row(_ reading: BalanceReading) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                Text(reading.title).font(EnergyTypography.Detail.label)
                Text(status(reading)).font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
            }.frame(width: 94, alignment: .leading)
            VStack(alignment: .trailing, spacing: 5) {
                Text(remaining(reading)).font(EnergyTypography.Detail.rowValue)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if let primary = reading.windows.first(where: \.isPrimary) ?? reading.windows.first {
                    Text(primary.shortTag).font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
                }
                if reading.id == BalanceReading.codexID,
                   let other = reading.windows.first(where: { !$0.isPrimary }), reading.windows.count > 1 {
                    Text("\(other.shortTag) 余\(other.remainingPercent)%")
                        .font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .trailing)
            VStack(alignment: .trailing, spacing: 5) {
                Text(usage(reading)).font(EnergyTypography.Detail.label).lineLimit(2)
                Text(usagePeriod(reading))
                    .font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
            }.frame(width: 78, alignment: .trailing)
            Text(reset(reading)).font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).frame(width: 68, alignment: .trailing)
        }.padding(.vertical, 15).frame(maxWidth: .infinity).contentShape(Rectangle())
            .help(reading.stateMessage ?? "查看\(reading.title)账户详情")
    }

    private func status(_ reading: BalanceReading) -> String {
        switch reading.state {
        case .loading: return "读取中"
        case .unconfigured: return "未配置"
        case .failed(let message): return message.contains("未运行") || message.contains("启动") ? "未运行" : "读取失败"
        case .stale: return "旧数据"
        case .ok: return advice.recommendedID == reading.id ? "推荐使用" : advice.level(for: reading.id).title
        }
    }

    private func remaining(_ reading: BalanceReading) -> String {
        guard reading.hasReading, let value = reading.valueText else { return "—" }
        return [reading.unitPrefix, value, reading.unitSuffix].compactMap { $0 }.joined()
    }

    private func usagePeriod(_ reading: BalanceReading) -> String {
        if case .stale = reading.state { return "上次数据" }
        if reading.id == "doubao" { return "本窗口" }
        if reading.hasReading && todayUsage.valueText(for: reading.id) == nil {
            return reading.id == "workbuddy" ? "今日观测未知" : "采样不足"
        }
        return "今日·本机"
    }

    private func usage(_ reading: BalanceReading) -> String {
        guard reading.hasReading else { return "—" }
        if case .stale = reading.state { return "—" }
        if reading.id == "doubao", let percent = reading.percent { return "\(max(0, 100 - percent))%" }
        guard let value = todayUsage.valueText(for: reading.id) else { return "—" }
        switch reading.id {
        case BalanceReading.codexID: return value + " Token"
        case "workbuddy": return value + " 积分"
        case "deepseek":
            let prefix = todayUsage.currencyPrefixes[reading.id] ?? reading.unitPrefix ?? ""
            return value.hasPrefix(prefix) || prefix.isEmpty ? value : prefix + value
        default: return value
        }
    }

    private func reset(_ reading: BalanceReading) -> String {
        guard reading.hasReading else { return "—" }
        if reading.id == "deepseek" { return "无周期" }
        guard let date = (reading.windows.first(where: \.isPrimary) ?? reading.windows.first)?.resetAt else { return "未提供" }
        return EnergyLogic.shortResetText(until: date)
    }
}
