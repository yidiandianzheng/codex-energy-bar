import SwiftUI

/// Per-account usage strip on the "今日用量" page.
///
/// It only prints figures each provider actually exposes: Codex has local token
/// logs, Gemini and 豆包 publish the current window's remaining percentage,
/// WorkBuddy, WorkBuddy AI, 百度搭子、千问办公、Qoder CN and Trae CN report
/// spent/remaining credits, and DeepSeek just has a balance. No token number is
/// invented for the rest — that is why the caption states the data boundary and
/// why sampling is required before "today's spend" can be shown.
///
/// Three columns keep the strip to four balanced rows for the ten accounts, so
/// the project list below it keeps most of the page.
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
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3),
                      alignment: .leading, spacing: 10) {
                cell(codex)
                cell(deepseek)
                cell(gemini)
                cell(doubao)
                cell(workbuddy)
                cell(workbuddyIntl)
                cell(dumate)
                cell(qwenwork)
                cell(qoder)
                cell(trae)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 8)
            .energyCardSurface()
            Text("今日用量按本机累计：Codex 今日 Token、DeepSeek 今日余额减少、WorkBuddy 与 WorkBuddy AI、百度搭子、千问办公、Qoder CN 与 Trae CN 今日观测值（身份或基线未确认时未知）；Gemini 与豆包只提供窗口百分比，显示本窗口已用。")
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
                .minimumScaleFactor(0.75)
            Text(entry.note)
                .fixedSize(horizontal: false, vertical: true)
                .font(EnergyTypography.Detail.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
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

    private var gemini: Entry {
        guard let reading = readings.first(where: { $0.id == "gemini" }) else {
            return Entry(title: "Gemini", value: "—", note: "未读取")
        }
        if !reading.hasReading {
            switch reading.state {
            case .loading: return Entry(title: "Gemini", value: "—", note: "读取中")
            case .unconfigured: return Entry(title: "Gemini", value: "—", note: "未登录")
            case .failed(let message):
                return Entry(title: "Gemini", value: "—",
                             note: message.contains("未运行") || message.contains("启动") ? "未运行" : "读取失败")
            default: return Entry(title: "Gemini", value: "—", note: "未读取")
            }
        }
        if case .stale = reading.state {
            return Entry(title: "Gemini", value: "—", note: "上次剩余 \(reading.percent.map { "\($0)%" } ?? "—")")
        }
        let used = reading.percent.map { "\(max(0, 100 - $0))%" } ?? "—"
        let weekly = reading.windows.first { $0.id == GeminiUsageParser.weeklyID }
        let note = weekly.map { "本窗口已用 · 周已用 \(max(0, 100 - $0.remainingPercent))%" } ?? "本窗口已用"
        return Entry(title: "Gemini", value: used, note: note)
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

    private var workbuddyIntl: Entry {
        guard let reading = reading("workbuddyintl") else {
            return Entry(title: "WorkBuddy AI", value: "—", note: "未运行")
        }
        if case .stale = reading.state {
            return Entry(title: "WorkBuddy AI", value: "—", note: "上次积分 " + (reading.valueText ?? "—"))
        }
        let spent = todayUsage.valueText(for: "workbuddyintl") ?? "—"
        let remaining = reading.percent.map { "余 \($0)%" } ?? ""
        return Entry(
            title: "WorkBuddy AI",
            value: spent,
            note: spent == "—" ? "今日观测未知" : (remaining.isEmpty ? "今日积分" : "今日积分 · \(remaining)")
        )
    }

    private var dumate: Entry {
        guard let reading = reading("dumate") else {
            return Entry(title: "百度搭子", value: "—", note: "未运行")
        }
        if case .stale = reading.state {
            return Entry(title: "百度搭子", value: "—", note: "上次积分 " + (reading.valueText ?? "—"))
        }
        let spent = todayUsage.valueText(for: "dumate") ?? "—"
        let remaining = reading.percent.map { "余 \($0)%" } ?? ""
        return Entry(
            title: "百度搭子",
            value: spent,
            note: spent == "—" ? "今日观测未知" : (remaining.isEmpty ? "今日积分" : "今日积分 · \(remaining)")
        )
    }

    private var qwenwork: Entry { creditsEntry("qwenwork", title: "千问办公") }
    private var qoder: Entry { creditsEntry("qoder", title: "Qoder CN") }
    private var trae: Entry { creditsEntry("trae", title: "Trae CN") }

    private func creditsEntry(_ id: String, title: String) -> Entry {
        guard let reading = readings.first(where: { $0.id == id }) else {
            return Entry(title: title, value: "—", note: "未读取")
        }
        if !reading.hasReading {
            switch reading.state {
            case .loading: return Entry(title: title, value: "—", note: "读取中")
            case .unconfigured: return Entry(title: title, value: "—", note: "未登录")
            case .failed(let message):
                return Entry(title: title, value: "—",
                             note: message.contains("未运行") || message.contains("启动") ? "未运行" : "读取失败")
            default: return Entry(title: title, value: "—", note: "未读取")
            }
        }
        if case .stale = reading.state {
            return Entry(title: title, value: "—", note: "上次积分 " + (reading.valueText ?? "—"))
        }
        let spent = todayUsage.valueText(for: id) ?? "—"
        return Entry(
            title: title,
            value: spent,
            note: spent == "—" ? "今日观测未知" : "今日积分"
        )
    }

    private func reading(_ id: String) -> BalanceReading? {
        readings.first { $0.id == id && $0.hasReading }
    }
}
