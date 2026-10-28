import Foundation

enum UsageLevel: Equatable {
    case ample, tight, critical, unknown, unavailable
    var title: String {
        switch self {
        case .ample: "充裕"
        case .tight: "偏紧"
        case .critical: "告急"
        case .unknown: "未定额"
        case .unavailable: "不可用"
        }
    }
    var isWarning: Bool { self == .critical || self == .tight }
}
struct UsageAdvice: Equatable {
    let recommendedID: String?
    let headline: String
    let detail: String
    let compactText: String
    let levels: [String: UsageLevel]
    static let unavailable = UsageAdvice(recommendedID: nil, headline: "暂无可用建议",
        detail: "等待新鲜且可用的账户读数。", compactText: "暂无可用建议", levels: [:])
    func level(for id: String) -> UsageLevel { levels[id] ?? .unavailable }
}

enum AIUsageAdvisor {
    private struct Candidate {
        let id: String
        let title: String
        let level: UsageLevel
        let score: Double
        /// Full sentence, including the recovery time.
        let reason: String
        /// One-line version for the Mini strip: recovery time stays in `detail`.
        let compactReason: String
    }
    static func advise(readings: [BalanceReading], now: Date = .now) -> UsageAdvice {
        var levels: [String: UsageLevel] = [:]
        var candidates: [Candidate] = []
        for reading in readings {
            let candidate = candidate(for: reading, now: now)
            levels[reading.id] = candidate?.level ?? .unavailable
            if let candidate { candidates.append(candidate) }
        }
        // 积分账户没有可跨账户比较的配额分母，只作为余额展示；它们不进入推荐池。
        let ranked = candidates.filter { $0.level != .critical && $0.level != .unknown }
        let critical = candidates.filter { $0.level == .critical }
        let pool = ranked.isEmpty ? critical : ranked
        guard let best = pool.max(by: { $0.score < $1.score }) else {
            let detail = candidates.contains { $0.level == .unknown }
                ? "只有积分余额可读；积分账户不参与跨账户推荐，请查看账户状态。"
                : "账户额度耗尽、读取失败或数据已过期，请查看账户状态。"
            return UsageAdvice(recommendedID: nil, headline: "暂无可用建议", detail: detail, compactText: "暂无可用建议", levels: levels)
        }
        let headline = best.level == .critical ? "可用额度偏低" : "推荐\(best.title)"
        return UsageAdvice(recommendedID: best.id, headline: headline,
            detail: "\(best.title)：\(best.reason)", compactText: "\(headline) · \(best.compactReason)", levels: levels)
    }
    static func level(for reading: BalanceReading, now: Date = .now) -> UsageLevel {
        candidate(for: reading, now: now)?.level ?? .unavailable
    }
    private static func candidate(for reading: BalanceReading, now: Date) -> Candidate? {
        guard reading.isFresh(at: now) else { return nil }
        if reading.id == "deepseek" {
            guard let money = reading.numericValue, money.isFinite, money > 0, let currency = reading.currency else { return nil }
            // Different currencies are never compared using CNY thresholds.
            let isCNY = currency == "CNY"
            let level: UsageLevel = isCNY ? (money >= 30 ? .ample : money >= 10 ? .tight : .critical) : .tight
            let balance = "余额 \(reading.unitPrefix ?? currency + " ")\(reading.valueText ?? "—")"
            return Candidate(id: reading.id, title: reading.title, level: level,
                score: isCNY ? min(20, money) : 10,
                reason: balance, compactReason: balance)
        }
        // 千问办公、Qoder CN 与 Trae CN 是积分余额：套餐百分比只说明"这一池用了多少"，
        // 不能当作可用余量横向比较（498/498 = 100% 并不代表额度充裕）。统一标为
        // 未定额，只展示余额；推荐池会跳过它们。
        if ["qwenwork", "qoder", "trae"].contains(reading.id) {
            guard let value = reading.valueText else { return nil }
            let balance = "积分 \(value)"
            return Candidate(id: reading.id, title: reading.title, level: .unknown, score: 0,
                             reason: balance, compactReason: balance)
        }
        // Reward and enterprise pools are independent, not constraints on personal quota.
        let windows = reading.id == "doubao" ? reading.windows.filter { !$0.id.hasPrefix("INC-") && !$0.id.hasPrefix("ENT-") } : reading.windows
        if reading.id == "doubao", windows.isEmpty { return nil }
        let limiting = windows.min { $0.remainingPercent < $1.remainingPercent }
        guard let percent = limiting?.remainingPercent ?? reading.percent, percent > 0 else { return nil }
        // A reset timestamp passing does not prove that the account has recovered.
        let level: UsageLevel = percent >= 30 ? .ample : percent >= 10 ? .tight : .critical
        let preference: Double = reading.id == "doubao" ? 12 : reading.id == "codex" ? 8 : 4
        let label = limiting.map(compactWindowLabel)
            ?? (reading.id == "workbuddy" || reading.id == "workbuddyintl" || reading.id == "dumate"
                ? "积分" : "额度")
        let compactReason = "\(label)剩 \(percent)%"
        let reason = compactReason + resetText(limiting?.resetAt, now: now)
        return Candidate(id: reading.id, title: reading.title, level: level,
            score: Double(percent) + preference, reason: reason, compactReason: compactReason)
    }
    /// "账户 · 5小时" is useful in the account detail list but too long for the
    /// one-line recommendation strip; the window duration alone is enough there.
    private static func compactWindowLabel(_ window: BalanceWindowReading) -> String {
        let prefix = "账户 · "
        return window.title.hasPrefix(prefix) ? String(window.title.dropFirst(prefix.count)) : window.title
    }
    private static func resetText(_ reset: Date?, now: Date) -> String {
        guard let reset else { return "" }
        let interval = reset.timeIntervalSince(now)
        guard interval > 0 else { return "，恢复待确认" }
        if interval < 3600 { return "，约 \(max(1, Int(interval / 60))) 分钟后恢复" }
        if interval < 86400 { return "，约 \(Int(interval / 3600)) 小时后恢复" }
        return "，约 \(Int(interval / 86400)) 天后恢复"
    }
}
