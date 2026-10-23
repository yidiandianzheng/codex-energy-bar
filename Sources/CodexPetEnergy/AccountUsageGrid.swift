import SwiftUI

/// Per-account usage strip on the "今日用量" page.
///
/// It only prints figures each provider actually exposes: Codex has local token
/// logs, 豆包 publishes the current window's remaining percentage, WorkBuddy
/// reports spent credits and DeepSeek just has a balance. No token number is
/// invented for the latter three — that is why the caption states the data
/// boundary and why sampling is required before "today's spend" can be shown.
struct AccountUsageGrid: View {
    let codexTokens: Int?
    let readings: [BalanceReading]
    var todayUsage: TodayUsageSnapshot = .empty

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("今日各 AI 用量").font(EnergyTypography.Detail.section)
                Spacer()
                Text("各自口径").font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 0) {
                cell(codex)
                divider
                cell(deepseek)
                divider
                cell(doubao)
                divider
                cell(workbuddy)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 10)
            .energyCardSurface()
            Text("今日用量按本机累计：Codex 今日 Token、DeepSeek 今日余额减少、WorkBuddy 今日观测值（身份未确认时未知）；豆包只提供窗口剩余，显示本时段已用。")
                .font(EnergyTypography.Detail.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private struct Entry {
        let title: String
        let value: String
        let note: String
    }

    private func cell(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.title)
                .font(EnergyTypography.Detail.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(1)
            Text(entry.value)
                .font(EnergyTypography.Detail.gridValue)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(entry.note)
                .fixedSize(horizontal: false, vertical: true)
                .font(EnergyTypography.Detail.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }

    private var divider: some View {
        Rectangle().fill(EnergyVisualStyle.hairline).frame(width: 1, height: 34)
    }

    private var codex: Entry {
        Entry(
            title: "Codex",
            value: codexTokens.map(TokenFormatting.compact) ?? "—",
            note: "今日 Token · 本机"
        )
    }

    private var deepseek: Entry {
        let reading = reading("deepseek")
        let balance = reading?.valueText.map { (reading?.unitPrefix ?? "") + $0 } ?? "—"
        let spent = todayUsage.valueText(for: "deepseek") ?? "—"
        if let reading, case .stale = reading.state {
            return Entry(title: "DeepSeek", value: "—", note: "上次余额 " + balance)
        }
        return Entry(title: "DeepSeek", value: spent, note: spent == "—" ? "采样不足" : "今日 · 余额 \(balance)")
    }

    private var doubao: Entry {
        guard let reading = reading("doubao") else {
            return Entry(title: "豆包", value: "—", note: "未读取")
        }
        if case .stale = reading.state {
            return Entry(title: "豆包", value: "—", note: "上次剩余 \(reading.percent.map { "\($0)%" } ?? "—")")
        }
        let used: String
        if let percent = reading.percent {
            used = "\(max(0, 100 - percent))%"
        } else {
            used = reading.valueText.map { "\($0)%" } ?? "—"
        }
        let remaining = reading.percent.map { "剩 \($0)%" } ?? ""
        return Entry(title: "豆包", value: used, note: remaining.isEmpty ? "本时段已用" : "本时段已用 · \(remaining)")
    }

    private var workbuddy: Entry {
        guard let reading = reading("workbuddy") else {
            return Entry(title: "WorkBuddy", value: "—", note: "未运行")
        }
        if case .stale = reading.state {
            return Entry(title: "WorkBuddy", value: "—", note: "上次积分 " + (reading.valueText ?? "—"))
        }
        let spent = todayUsage.valueText(for: "workbuddy") ?? "—"
        let remaining = reading.percent.map { "余 \($0)%" } ?? ""
        return Entry(
            title: "WorkBuddy",
            value: spent,
            note: spent == "—" ? "今日观测未知" : (remaining.isEmpty ? "今日积分" : "今日积分 · \(remaining)")
        )
    }

    private func reading(_ id: String) -> BalanceReading? {
        readings.first { $0.id == id && $0.hasReading }
    }
}
