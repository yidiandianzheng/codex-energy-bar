import Foundation

struct DailyUsageSample: Codable, Equatable {
    var value: Double
    var sampledAt: Date
    var identity: String
    var currency: String?
}

/// Version 2 does not import unverified totals or baselines from the old ledger.
struct DailyUsageLedger: Codable, Equatable {
    var dayKey: String = ""
    var samples: [String: DailyUsageSample] = [:]
    var moneySpent: [String: Double] = [:]
    var pointsSpent: [String: Double] = [:]
    var currencies: [String: String] = [:]
    var identities: [String: String] = [:]
    var coverageStart: [String: Date] = [:]

    mutating func roll(to now: Date) {
        let day = DailyUsageStore.dayKey(now)
        guard dayKey != day else { return }
        self = DailyUsageLedger(dayKey: day)
    }

    mutating func breakContinuity(for id: String) { samples[id] = nil }

    mutating func record(_ reading: BalanceReading, now: Date) {
        roll(to: now)
        let id = reading.id
        guard id == "deepseek" || id == "workbuddy" else { return }
        if let identity = reading.sourceIdentity, let previous = identities[id], identity != previous {
            moneySpent[id] = nil; pointsSpent[id] = nil; samples[id] = nil; coverageStart[id] = nil
            identities[id] = identity
        }
        guard reading.isFresh(at: now), let date = reading.updatedAt,
              DailyUsageStore.dayKey(date) == dayKey,
              let identity = reading.sourceIdentity, !identity.isEmpty,
              let value = id == "deepseek" ? reading.numericValue : reading.numericUsedValue,
              value.isFinite, value >= 0,
              id != "deepseek" || reading.currency != nil else {
            breakContinuity(for: id)
            return
        }
        // Never combine different accounts/currencies into the same "today" cell.
        if identities[id] != identity || (id == "deepseek" && currencies[id] != reading.currency) {
            moneySpent[id] = nil
            pointsSpent[id] = nil
            samples[id] = nil
            coverageStart[id] = nil
        }
        identities[id] = identity
        currencies[id] = reading.currency
        defer { samples[id] = DailyUsageSample(value: value, sampledAt: date, identity: identity, currency: reading.currency) }
        guard let previous = samples[id], previous.identity == identity,
              previous.currency == reading.currency, date > previous.sampledAt,
              date.timeIntervalSince(previous.sampledAt) <= reading.freshnessInterval,
              DailyUsageStore.dayKey(previous.sampledAt) == dayKey else { return }
        let delta = id == "deepseek" ? previous.value - value : value - previous.value
        guard delta.isFinite else { return }
        // A recharge or cycle reset cannot reveal usage during that interval.
        guard delta >= 0 else { return }
        coverageStart[id] = coverageStart[id] ?? previous.sampledAt
        if id == "deepseek" {
            let total = moneySpent[id, default: 0] + delta
            if total.isFinite { moneySpent[id] = total }
        } else {
            let total = pointsSpent[id, default: 0] + delta
            if total.isFinite { pointsSpent[id] = total }
        }
    }
}

enum DailyUsageStore {
    static let defaultsKey = "energy-daily-usage-ledger-v2"
    static let timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

    static func dayKey(_ date: Date = .now) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
    static func load(defaults: UserDefaults = .standard) -> DailyUsageLedger {
        guard let data = defaults.data(forKey: defaultsKey),
              var ledger = try? JSONDecoder().decode(DailyUsageLedger.self, from: data) else { return DailyUsageLedger() }
        ledger.samples = [:] // A restart is a sampling gap, never an offline invoice.
        return ledger
    }
    static func save(_ ledger: DailyUsageLedger, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}

struct TodayUsageSnapshot: Equatable {
    let codexTokens: Int?
    let moneySpent: [String: Double]
    let pointsSpent: [String: Double]
    var currencyPrefixes: [String: String] = [:]
    var coverageStart: [String: Date] = [:]

    static let empty = TodayUsageSnapshot(codexTokens: nil, moneySpent: [:], pointsSpent: [:])
    func valueText(for id: String) -> String? {
        switch id {
        case BalanceReading.codexID:
            return codexTokens.map(TokenFormatting.compact)
        case BalanceProvider.deepseek.id:
            guard let spend = moneySpent[id], let prefix = currencyPrefixes[id] else { return nil }
            return prefix + (BalanceFormatting.money(String(spend)) ?? "—")
        case BalanceProvider.workbuddy.id:
            guard let spend = pointsSpent[id] else { return nil }
            return BalanceFormatting.credits(String(spend))
        default: return nil
        }
    }
    func caption(for id: String) -> String {
        switch id {
        case BalanceReading.codexID: "Token · 今日本机"
        case BalanceProvider.deepseek.id: "余额减少 · 今日观测"
        case BalanceProvider.workbuddy.id: "积分 · 今日观测"
        default: ""
        }
    }
}
