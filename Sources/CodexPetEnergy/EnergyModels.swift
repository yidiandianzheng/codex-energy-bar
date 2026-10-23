import Foundation

enum EnergyTone: Equatable {
    case green
    case yellow
    case red
    case unavailable
}

struct EnergyReading: Equatable {
    let remainingPercent: Int?
    let resetsAt: Date?

    static let unavailable = EnergyReading(remainingPercent: nil, resetsAt: nil)
}

struct AccountQuotaReadings: Equatable {
    let weekly: EnergyReading
    let spark: EnergyReading

    static let unavailable = AccountQuotaReadings(weekly: .unavailable, spark: .unavailable)
}

struct ProjectUsageReading: Identifiable, Equatable {
    let directory: String
    let projectName: String
    let totals: ProjectUsageTotals
    let lastActivity: Date

    var id: String { directory }
}

struct ProjectUsageTotals: Equatable {
    let inputTokens: Int
    let outputTokens: Int
    let reasoningTokens: Int
    let cachedInputTokens: Int
    let turnCount: Int
    let maximumTurnTokens: Int

    var totalTokens: Int { inputTokens + outputTokens }

    static let zero = ProjectUsageTotals(
        inputTokens: 0,
        outputTokens: 0,
        reasoningTokens: 0,
        cachedInputTokens: 0,
        turnCount: 0,
        maximumTurnTokens: 0
    )

    func adding(_ other: ProjectUsageTotals) -> ProjectUsageTotals {
        ProjectUsageTotals(
            inputTokens: inputTokens + other.inputTokens,
            outputTokens: outputTokens + other.outputTokens,
            reasoningTokens: reasoningTokens + other.reasoningTokens,
            cachedInputTokens: cachedInputTokens + other.cachedInputTokens,
            turnCount: turnCount + other.turnCount,
            maximumTurnTokens: max(maximumTurnTokens, other.maximumTurnTokens)
        )
    }
}

struct RateLimitWindow: Codable, Equatable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: TimeInterval?
}

struct RateLimitSnapshot: Codable, Equatable {
    let limitId: String?
    let limitName: String?
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?

    init(limitId: String?, limitName: String? = nil, primary: RateLimitWindow?, secondary: RateLimitWindow?) {
        self.limitId = limitId
        self.limitName = limitName
        self.primary = primary
        self.secondary = secondary
    }
}

struct RateLimitReadResult: Codable, Equatable {
    let rateLimits: RateLimitSnapshot
    let rateLimitsByLimitId: [String: RateLimitSnapshot]?
    let rateLimitResetCredits: RateLimitResetCreditsSummary?

    init(rateLimits: RateLimitSnapshot, rateLimitsByLimitId: [String: RateLimitSnapshot]?,
         rateLimitResetCredits: RateLimitResetCreditsSummary? = nil) {
        self.rateLimits = rateLimits
        self.rateLimitsByLimitId = rateLimitsByLimitId
        self.rateLimitResetCredits = rateLimitResetCredits
    }
}

enum EnergyLogic {
    static func remainingPercent(fromUsedPercent usedPercent: Double) -> Int {
        guard usedPercent.isFinite else { return 0 }
        return Int(min(max((100 - usedPercent).rounded(), 0), 100))
    }

    static func tone(for remainingPercent: Int?) -> EnergyTone {
        guard let remainingPercent else { return .unavailable }
        if remainingPercent >= 50 { return .green }
        if remainingPercent >= 20 { return .yellow }
        return .red
    }

    static func reading(from window: RateLimitWindow?) -> EnergyReading {
        guard let window, window.usedPercent.isFinite, (0...100).contains(window.usedPercent) else { return .unavailable }
        return EnergyReading(
            remainingPercent: remainingPercent(fromUsedPercent: window.usedPercent),
            resetsAt: window.resetsAt.flatMap { $0.isFinite && abs($0) < 253_402_300_800 ? Date(timeIntervalSince1970: $0) : nil }
        )
    }

    static func accountReadings(from snapshot: RateLimitSnapshot) -> AccountQuotaReadings {
        // ChatGPT's Codex menu exposes these in the same order: the primary
        // weekly account window, then the GPT-5.3-Codex-Spark model window.
        AccountQuotaReadings(
            weekly: reading(from: snapshot.primary),
            spark: reading(from: snapshot.secondary)
        )
    }

    static func accountReadings(from result: RateLimitReadResult) -> AccountQuotaReadings {
        let sparkSnapshot = result.rateLimitsByLimitId?["codex_bengalfox"]
            ?? result.rateLimitsByLimitId?.values.first(where: {
                ($0.limitName ?? "").localizedCaseInsensitiveContains("GPT-5.3-Codex-Spark")
            })
        let weekly = reading(from: result.rateLimits.primary)
        let receivedSpark = reading(from: sparkSnapshot?.primary)
        // Codex presents both limits under the same weekly reset cycle. The
        // model bucket may arrive later than the account bucket, so keep the
        // reset time visible without inventing a model percentage.
        let spark = EnergyReading(
            remainingPercent: receivedSpark.remainingPercent,
            resetsAt: receivedSpark.resetsAt
        )
        return AccountQuotaReadings(weekly: weekly, spark: spark)
    }

    static func quotaLimits(from result: RateLimitReadResult) -> [QuotaLimitReading] {
        var buckets = result.rateLimitsByLimitId ?? [:]
        let rootID = result.rateLimits.limitId ?? "codex"
        if buckets[rootID] == nil { buckets[rootID] = result.rateLimits }
        return buckets.keys.sorted().flatMap { id -> [QuotaLimitReading] in
            guard let snapshot = buckets[id] else { return [] }
            let name = id == "codex" ? "账户额度" : (snapshot.limitName ?? id)
            return [("primary", snapshot.primary), ("secondary", snapshot.secondary)].compactMap { key, window in
                guard let window else { return nil }
                let title = id == "codex"
                    ? (window.windowDurationMins == 10_080 ? "周额度" : "账户 · \(windowDurationText(window.windowDurationMins))")
                    : "\(name) · \(windowDurationText(window.windowDurationMins))"
                return QuotaLimitReading(
                    id: "\(id)-\(key)", title: title,
                    remainingPercent: reading(from: window).remainingPercent,
                    resetsAt: reading(from: window).resetsAt,
                    windowDurationMins: window.windowDurationMins
                )
            }
        }
    }

    static func mergingSparseUpdate(_ update: RateLimitSnapshot, into current: RateLimitReadResult) -> RateLimitReadResult {
        var buckets = current.rateLimitsByLimitId ?? [:]
        if let id = update.limitId {
            let old = buckets[id]
            buckets[id] = RateLimitSnapshot(
                limitId: id,
                limitName: update.limitName ?? old?.limitName,
                primary: update.primary ?? old?.primary,
                secondary: update.secondary ?? old?.secondary
            )
        } else if let name = update.limitName,
                  let id = buckets.first(where: {
                      ($0.value.limitName ?? "").localizedCaseInsensitiveCompare(name) == .orderedSame
                  })?.key,
                  let old = buckets[id] {
            buckets[id] = RateLimitSnapshot(
                limitId: old.limitId ?? id,
                limitName: name,
                primary: update.primary ?? old.primary,
                secondary: update.secondary ?? old.secondary
            )
        } else if update.limitName == nil {
            return current
        }
        let root = update.limitId == current.rateLimits.limitId
            ? RateLimitSnapshot(
                limitId: update.limitId,
                limitName: update.limitName ?? current.rateLimits.limitName,
                primary: update.primary ?? current.rateLimits.primary,
                secondary: update.secondary ?? current.rateLimits.secondary
            )
            : current.rateLimits
        return RateLimitReadResult(rateLimits: root, rateLimitsByLimitId: buckets, rateLimitResetCredits: current.rateLimitResetCredits)
    }

    static func compactResetDateText(_ reset: Date?, timeZone: TimeZone = .current) -> String {
        guard let reset else { return "—" }
        let raw = preciseResetDateText(reset, timeZone: timeZone)
        guard let space = raw.firstIndex(of: " ") else { return raw }
        let date = raw[..<space]
        guard let slash = date.firstIndex(of: "/") else { return raw }
        let month = date[..<slash]
        let day = date[date.index(after: slash)...]
        let time = raw[raw.index(after: space)...]
        return "\(month)月\(day)日 \(time)"
    }

    static func statusBarResetDateText(_ reset: Date?, timeZone: TimeZone = .current) -> String {
        guard let reset else { return "—" }
        return preciseResetDateText(reset, timeZone: timeZone)
    }

    static func remainingDays(
        until reset: Date?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int? {
        guard let reset else { return nil }
        return max(0, calendar.dateComponents([.day], from: now, to: reset).day ?? 0)
    }

    static func resetCountdownText(until reset: Date?, now: Date = .now, timeZone: TimeZone = .current) -> String {
        guard let reset else { return "重置时间暂不可用" }
        let seconds = max(0, Int(reset.timeIntervalSince(now).rounded()))
        if seconds < 48 * 60 * 60 {
            return "约\(seconds / 3_600)小时\((seconds % 3_600) / 60)分"
        }
        return "\(compactResetDateText(reset, timeZone: timeZone)) · 约\(max(1, seconds / 86_400))天后"
    }

    static func shortResetText(until reset: Date?, now: Date = .now) -> String {
        guard let reset else { return "重置时间未知" }
        let interval = reset.timeIntervalSince(now)
        guard interval.isFinite, interval > 0 else { return "恢复待确认" }
        if interval < 3_600 { return "约\(max(1, Int(ceil(interval / 60))))分钟" }
        if interval < 48 * 3_600 { return "约\(Int(ceil(interval / 3_600)))小时" }
        return "约\(Int(ceil(min(interval / 86_400, 3_650_000))))天后重置"
    }

    static func windowDurationText(_ minutes: Int?) -> String {
        guard let minutes else { return "未知" }
        if minutes % 1_440 == 0 { return "\(minutes / 1_440)天" }
        if minutes % 60 == 0 { return "\(minutes / 60)小时" }
        return "\(minutes)分钟"
    }

    private static func preciseResetDateText(_ reset: Date, timeZone: TimeZone) -> String {
        reset.formatted(
            Date.FormatStyle(
                date: .omitted,
                time: .omitted,
                locale: Locale(identifier: "zh_CN"),
                calendar: Calendar(identifier: .gregorian),
                timeZone: timeZone
            )
            .month(.defaultDigits)
            .day(.defaultDigits)
            .hour(.twoDigits(amPM: .omitted))
            .minute(.twoDigits)
            .second(.twoDigits)
        )
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
