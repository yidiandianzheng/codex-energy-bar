import Foundation

@MainActor enum UpgradeSelfTest {
    static func check(into failures: inout [String]) {
        func expect(_ condition: Bool, _ message: String) { if !condition { failures.append("upgrade: " + message) } }
        let now = ISO8601DateFormatter().date(from: "2026-10-23T04:00:00Z")!
        expect(EnergyLogic.shortResetText(until: now.addingTimeInterval(59), now: now) == "约1分钟", "sub-hour recovery never reads zero hours")
        expect(EnergyLogic.shortResetText(until: now.addingTimeInterval(-1), now: now) == "恢复待确认", "past reset does not promise recovery")
        let limits = [QuotaLimitReading(id: "codex-primary", title: "5 小时", remainingPercent: 0, resetsAt: now.addingTimeInterval(1800), windowDurationMins: 300),
                      QuotaLimitReading(id: "codex-secondary", title: "周额度", remainingPercent: 80, resetsAt: now.addingTimeInterval(86400), windowDurationMins: 10080)]
        let exhausted = BalanceReading.codex(limits: limits, now: now)
        expect(exhausted.percent == 0, "headline uses binding window")
        expect(AIUsageAdvisor.advise(readings: [exhausted], now: now).recommendedID == nil, "exhausted short window cannot be recommended")
        var valid = BalanceReading.codex(limits: [limits[1]], now: now)
        expect(AIUsageAdvisor.advise(readings: [valid], now: now).recommendedID == "codex", "fresh nonzero window is usable")
        expect(AIUsageAdvisor.advise(readings: [valid], now: now.addingTimeInterval(181)).recommendedID == nil, "age alone invalidates recommendation")
        valid.state = .stale("failed")
        expect(AIUsageAdvisor.advise(readings: [valid], now: now).recommendedID == nil, "retained failed quota cannot be recommended")
        expect(BalanceFormatting.percent(.infinity) == 0 && BalanceFormatting.percent(1e100) == 100, "percent never traps")
        expect(EnergyLogic.reading(from: RateLimitWindow(usedPercent: .nan, windowDurationMins: 300, resetsAt: nil)).remainingPercent == nil, "invalid Codex value stays unknown")

        for invalid in [-1.0, 101.0, 1e100] {
            expect(EnergyLogic.reading(from: RateLimitWindow(usedPercent: invalid, windowDurationMins: 300, resetsAt: nil)).remainingPercent == nil, "out-of-range Codex value stays unknown")
        }

        for id in ["codex", "deepseek", "doubao", "workbuddy"] {
            let store = SelfTest.makeStore(now: now)
            store.activate(.account(id))
            expect(store.mode == .quota && store.selectedAccountID == id, "account action selects " + id)
            let request = store.refreshRequest
            expect(request.codex == (id == "codex") && request.balances == (BalanceProvider(rawValue: id).map { Set([$0]) } ?? []), "account refresh targets " + id)
            var pointer = CompactPointerTracking(start: .zero, target: .account(id))
            expect(pointer.finish(at: .zero, target: .account(id)) == .account(id), "mouse preserves account identity")
            pointer = CompactPointerTracking(start: .zero, target: .account(id))
            expect(pointer.finish(at: CGPoint(x: 10, y: 0), target: .account(id)) == nil, "drag cancels navigation")
        }
        expect(EnergyRefreshRequest.forPage(.balance, accountID: "deepseek").codex, "overview refresh includes Codex")
        expect(EnergyRefreshRequest.forPage(.projects, accountID: "deepseek").balances.count == 3, "usage refresh includes visible balance sources")
        let bonus = BalanceReading(id: "doubao", title: "豆包", systemImage: "bubble.left", valueText: "80", unitPrefix: nil, unitSuffix: "%", caption: nil, detail: nil, percent: 80,
            windows: [BalanceWindowReading(id: "H5", title: "5 小时", remainingPercent: 80, resetAt: nil), BalanceWindowReading(id: "D7", title: "7 天", remainingPercent: 80, resetAt: nil), BalanceWindowReading(id: "INC-H5", title: "赠送", remainingPercent: 1, resetAt: nil)], state: .ok, sourceURL: nil, updatedAt: now)
        expect(AIUsageAdvisor.level(for: bonus, now: now) == .ample, "independent reward pool does not constrain personal quota")
        let unknown = QuotaLimitReading(id: "codex-primary", title: "5 小时", remainingPercent: nil, resetsAt: nil, windowDurationMins: 300)
        expect(AIUsageAdvisor.advise(readings: [BalanceReading.codex(limits: [unknown, limits[1]], now: now)], now: now).recommendedID == nil, "unknown blocking window prevents recommendation")
        let store = SelfTest.makeStore(now: now)
        let snapshot = RateLimitSnapshot(limitId: "codex", primary: RateLimitWindow(usedPercent: 20, windowDurationMins: 300, resetsAt: now.addingTimeInterval(300).timeIntervalSince1970), secondary: nil)
        store.apply(RateLimitReadResult(rateLimits: snapshot, rateLimitsByLimitId: nil))
        store.tick(now: now.addingTimeInterval(181))
        expect(store.codexBalanceReading.updatedAt == now && store.balanceAdvice.recommendedID == nil, "clock tick marks stale without faking success timestamp")
        store.markUnavailable()
        expect(store.codexBalanceReading.hasReading && store.codexBalanceReading.stateMessage != nil, "failure retains labelled previous data")

        func money(_ amount: Double, at date: Date, identity: String? = "account-a", currency: String = "USD") -> BalanceReading {
            BalanceReading(id: "deepseek", title: "DeepSeek", systemImage: "sparkles", valueText: String(amount), unitPrefix: currency + " ", unitSuffix: nil, caption: nil, detail: nil, percent: nil, windows: [], state: .ok, sourceURL: nil, updatedAt: date, numericValue: amount, currency: currency, sourceIdentity: identity)
        }
        var ledger = DailyUsageLedger()
        ledger.record(money(100, at: now), now: now)
        expect(ledger.moneySpent["deepseek"] == nil, "first sample is unknown, not zero")
        ledger.record(money(90, at: now.addingTimeInterval(300)), now: now.addingTimeInterval(300))
        expect(ledger.moneySpent["deepseek"] == 10, "same-day observations accumulate")
        ledger.breakContinuity(for: "deepseek")
        ledger.record(money(70, at: now.addingTimeInterval(600)), now: now.addingTimeInterval(600))
        expect(ledger.moneySpent["deepseek"] == 10, "reconnect gap is not backfilled")
        let nextDay = now.addingTimeInterval(86400)
        ledger.record(money(60, at: nextDay), now: nextDay)
        expect(ledger.moneySpent["deepseek"] == nil, "offline cross-day spend is not today")
        ledger.record(money(50, at: nextDay.addingTimeInterval(300)), now: nextDay.addingTimeInterval(300))
        ledger.record(money(10, at: nextDay.addingTimeInterval(600), identity: "account-b"), now: nextDay.addingTimeInterval(600))
        expect(ledger.moneySpent["deepseek"] == nil, "account changes clear incompatible totals")
        ledger.record(money(9, at: nextDay.addingTimeInterval(700), identity: "account-b", currency: "CNY"), now: nextDay.addingTimeInterval(700))
        expect(ledger.moneySpent["deepseek"] == nil, "currency changes establish a new baseline")
        ledger.record(money(1, at: nextDay.addingTimeInterval(800), identity: nil), now: nextDay.addingTimeInterval(800))
        expect(ledger.samples["deepseek"] == nil, "unknown identity never guesses billable daily usage")
        var failedAccount = money(0, at: nextDay.addingTimeInterval(900), identity: "account-c")
        failedAccount.state = .failed("unauthorized")
        ledger.moneySpent["deepseek"] = 12
        ledger.record(failedAccount, now: nextDay.addingTimeInterval(900))
        expect(ledger.moneySpent["deepseek"] == nil && ledger.identities["deepseek"] == "account-c", "failed new account cannot inherit previous daily spend")
        let display = TodayUsageSnapshot(codexTokens: nil, moneySpent: ["deepseek": 2.5], pointsSpent: [:], currencyPrefixes: ["deepseek": "USD "])
        expect(display.valueText(for: "deepseek") == "USD 2.50", "daily display preserves currency")

        let name = "compute-ring.ledger-test." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data("legacy".utf8), forKey: "energy-daily-usage-ledger")
        DailyUsageStore.save(ledger, defaults: defaults)
        expect(DailyUsageStore.load(defaults: defaults).samples.isEmpty, "restart drops continuity baselines")
        expect(defaults.data(forKey: "energy-daily-usage-ledger") == Data("legacy".utf8), "migration preserves old ledger")
    }
}
