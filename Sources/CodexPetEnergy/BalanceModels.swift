import Foundation

/// One account row on the balance page. The same struct carries success,
/// loading, unconfigured and failure states so that a single source going down
/// never hides the others.
struct BalanceReading: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String
    let valueText: String?
    let unitPrefix: String?
    let unitSuffix: String?
    let caption: String?
    let detail: String?
    let percent: Int?
    /// Structured "how much is already spent" figure, when the provider exposes
    /// one. Kept apart from `detail` so the usage page never parses prose.
    var usedText: String? = nil
    let windows: [BalanceWindowReading]
    var state: BalanceState
    let sourceURL: URL?
    var updatedAt: Date?
    /// Raw source values; calculations never parse formatted UI strings.
    var numericValue: Double? = nil
    var numericUsedValue: Double? = nil
    var currency: String? = nil
    var sourceIdentity: String? = nil
    var lastAttemptAt: Date? = nil

    var hasReading: Bool { valueText != nil && updatedAt != nil }
    var freshnessInterval: TimeInterval { id == Self.codexID ? 180 : 900 }
    func isFresh(at now: Date = .now) -> Bool {
        guard case .ok = state, let updatedAt else { return false }
        return now.timeIntervalSince(updatedAt) >= -60 && now.timeIntervalSince(updatedAt) <= freshnessInterval
    }
    func evaluated(at now: Date) -> Self {
        var result = self
        if case .ok = state, !isFresh(at: now) { result.state = .stale("数据已过期，显示上次读数") }
        return result
    }
    var stateMessage: String? {
        switch state {
        case .ok: nil
        case .loading: "正在读取"
        case .failed(let text), .unconfigured(let text), .stale(let text): text
        }
    }
    func retainingLastSuccess(_ previous: Self?) -> Self {
        guard case .failed(let message) = state, let previous, previous.hasReading,
              sourceIdentity == nil || previous.sourceIdentity == sourceIdentity else { return self }
        var result = previous
        result.state = .stale(message + (sourceIdentity == nil ? "；当前身份未确认，显示上次账户读数" : "；显示上次读数"))
        result.lastAttemptAt = lastAttemptAt ?? .now
        return result
    }
}

enum BalanceState: Equatable {
    case loading
    case ok
    case unconfigured(String)
    case failed(String)
    case stale(String)
}

struct BalanceWindowReading: Identifiable, Equatable {
    let id: String
    let title: String
    let remainingPercent: Int
    let resetAt: Date?
    /// Marks the window whose percentage is promoted to the account's headline
    /// value, so the compact cell can surface the other window as a second line.
    /// Filled with the current (shortest) window, e.g. 5h over 7d.
    var isPrimary: Bool = false

    /// Compact label for the 5-hour / 7-day windows, e.g. "5h", "7d".
    var shortTag: String {
        if title.contains("当前时段") { return "5h" }
        let digits = title.filter(\.isNumber)
        if title.contains("小时") { return "\(digits.isEmpty ? "5" : digits)h" }
        if title.contains("天") { return "\(digits.isEmpty ? "7" : digits)d" }
        if title.contains("周") { return "7d" }
        if title.contains("月") { return "1m" }
        return title
    }
}

enum BalanceProvider: String, CaseIterable, Identifiable {
    case deepseek
    case doubao
    case workbuddy
    case qwenwork

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deepseek: "DeepSeek"
        case .doubao: "豆包"
        case .workbuddy: "WorkBuddy"
        case .qwenwork: "千问办公"
        }
    }

    var systemImage: String {
        switch self {
        case .deepseek: "sparkles"
        case .doubao: "bubble.left.and.bubble.right"
        case .workbuddy: "briefcase"
        case .qwenwork: "wand.and.stars"
        }
    }

    var sourceURL: URL? {
        switch self {
        case .deepseek: URL(string: "https://platform.deepseek.com/usage")
        case .doubao: URL(string: "https://www.doubao.com/chat/")
        case .workbuddy: URL(string: "https://www.workbuddy.cn/profile/plan")
        case .qwenwork: URL(string: "https://qwenwork.cn")
        }
    }

    func placeholder() -> BalanceReading {
        BalanceReading(
            id: id,
            title: title,
            systemImage: systemImage,
            valueText: nil,
            unitPrefix: nil,
            unitSuffix: nil,
            caption: "正在读取…",
            detail: nil,
            percent: nil,
            windows: [],
            state: .loading,
            sourceURL: sourceURL,
            updatedAt: nil
        )
    }

    func unconfigured(_ message: String) -> BalanceReading {
        BalanceReading(
            id: id,
            title: title,
            systemImage: systemImage,
            valueText: nil,
            unitPrefix: nil,
            unitSuffix: nil,
            caption: "未配置",
            detail: message,
            percent: nil,
            windows: [],
            state: .unconfigured(message),
            sourceURL: sourceURL,
            updatedAt: nil
        )
    }

    func failed(_ message: String) -> BalanceReading {
        BalanceReading(
            id: id,
            title: title,
            systemImage: systemImage,
            valueText: nil,
            unitPrefix: nil,
            unitSuffix: nil,
            caption: "读取失败",
            detail: message,
            percent: nil,
            windows: [],
            state: .failed(message),
            sourceURL: sourceURL,
            updatedAt: nil
        )
    }
}

enum BalanceFormatting {
    /// Money arrives as a decimal string (e.g. "6.06"). Keep two fraction
    /// digits so the row never shows a bare integer that hides the cents.
    static func money(_ raw: String) -> String? {
        guard let value = Decimal(string: raw.trimmingCharacters(in: .whitespaces)) else { return nil }
        return format(value, fractionLength: 2)
    }

    /// Credits arrive as long decimal strings (e.g. "195.12000212"). Two
    /// fraction digits keep the row readable; trailing zeros dropped. The
    /// 千问办公 balance is shown with one decimal place.
    static func credits(_ raw: String, fractionLength: Int = 2) -> String? {
        guard let value = Decimal(string: raw.trimmingCharacters(in: .whitespaces)) else { return nil }
        return format(value, fractionLength: fractionLength, trimmingTrailingZeros: true)
    }

    static func percent(_ remaining: Double) -> Int {
        guard remaining.isFinite else { return 0 }
        return Int(min(max(remaining.rounded(), 0), 100))
    }

    private static func format(_ value: Decimal, fractionLength: Int, trimmingTrailingZeros: Bool = false) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = fractionLength
        formatter.minimumFractionDigits = trimmingTrailingZeros ? 0 : fractionLength
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }
}

extension BalanceReading {
    static let codexID = "codex"

    /// Surface the current (shortest) account window as the headline, keeping
    /// the longer window — and every other window — in `windows` for detail.
    ///
    /// The 5-hour window answers "what can this session spend right now", while
    /// the weekly window is a longer reserve. Showing the weekly percentage as
    /// the headline hid the near-term limit, so the shortest window is promoted
    /// instead. The usage advisor still judges a quota by its tightest window,
    /// so the recommendation never treats a large weekly reserve as safe when
    /// the current window is nearly spent.
    static func codex(limits: [QuotaLimitReading], now: Date = .now) -> BalanceReading {
        let icon = "gauge.with.dots.needle.50percent"
        let accountWindows = limits.filter { $0.id.hasPrefix("\(codexID)-") }
        let pool = accountWindows.isEmpty ? limits : accountWindows
        let knownWindows = pool.filter { $0.remainingPercent != nil }
        let limit = knownWindows.min {
            ($0.windowDurationMins ?? .max) < ($1.windowDurationMins ?? .max)
        } ?? knownWindows.first ?? pool.first
        guard let limit else {
            return BalanceReading(
                id: codexID, title: "Codex", systemImage: icon,
                valueText: nil, unitPrefix: nil, unitSuffix: nil,
                caption: "等待 Codex 返回额度", detail: nil,
                percent: nil, windows: [], state: .loading,
                sourceURL: nil, updatedAt: nil
            )
        }
        guard let percent = limit.remainingPercent else {
            return BalanceReading(
                id: codexID, title: "Codex", systemImage: icon,
                valueText: nil, unitPrefix: nil, unitSuffix: nil,
                caption: "额度暂不可用", detail: nil,
                percent: nil, windows: [], state: .failed("额度暂不可用"),
                sourceURL: nil, updatedAt: nil
            )
        }
        let windows = pool
            .sorted { ($0.windowDurationMins ?? .max) < ($1.windowDurationMins ?? .max) }
            .compactMap { window -> BalanceWindowReading? in
                guard let value = window.remainingPercent else { return nil }
                return BalanceWindowReading(
                    id: window.id, title: window.title, remainingPercent: value,
                    resetAt: window.resetsAt, isPrimary: window.id == limit.id
                )
            }
        return BalanceReading(
            id: codexID, title: "Codex", systemImage: icon,
            valueText: String(percent), unitPrefix: nil, unitSuffix: "%",
            caption: "\(limit.title)剩余",
            detail: resetText(limit.resetsAt, now: now),
            percent: percent,
            windows: windows.isEmpty
                ? [BalanceWindowReading(id: limit.id, title: limit.title,
                                        remainingPercent: percent, resetAt: limit.resetsAt, isPrimary: true)]
                : windows,
            state: pool.contains(where: { $0.remainingPercent == nil }) ? .stale("部分额度窗口未知，请刷新") : .ok,
            sourceURL: nil, updatedAt: now
        )
    }

    private static func resetText(_ reset: Date?, now: Date) -> String {
        guard let reset else { return "暂无重置时间" }
        let interval = reset.timeIntervalSince(now)
        guard interval > 0 else { return "即将重置" }
        if interval < 3600 { return "\(max(1, Int(interval / 60))) 分钟后重置" }
        if interval < 86_400 { return "\(Int(interval / 3600)) 小时后重置" }
        return "\(Int(interval / 86_400)) 天后重置"
    }
}

// Cash has no quota denominator. Only actual quota percentages have a progress bar.
extension BalanceReading {
    var referencePercent: Int? { percent }
}
