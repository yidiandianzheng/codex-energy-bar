import Foundation

struct RateLimitResetCreditsSummary: Codable, Equatable {
    let availableCount: Int
    // nil means the server returned only a count; [] means no detail rows.
    let credits: [RateLimitResetCredit]?
}

struct RateLimitResetCredit: Codable, Equatable, Identifiable {
    let id: String
    let resetType: String
    let status: String
    let grantedAt: TimeInterval
    let expiresAt: TimeInterval?
    let title: String?
    let description: String?

    var displayTitle: String {
        if resetType == "codexRateLimits" { return "完全重置" }
        if let title, !title.isEmpty { return title }
        return resetType == "codexRateLimits" ? "完全重置" : "限额重置"
    }

    func expirationText(now: Date = .now) -> String {
        guard let expiresAt else { return "无到期时间" }
        let date = Date(timeIntervalSince1970: expiresAt)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "M月d日 HH:mm"
        let prefix = date <= now ? "已于" : "将于"
        return "\(prefix) \(formatter.string(from: date))（GMT+8）到期"
    }
}
