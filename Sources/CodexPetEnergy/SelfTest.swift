import Foundation

@MainActor
enum SelfTest {
    private static var suites: [String] = []
    static func makeStore(now: Date = .now) -> EnergyStore {
        let name = "compute-ring.selftest." + UUID().uuidString
        suites.append(name)
        return EnergyStore(defaults: UserDefaults(suiteName: name)!, now: now, startsTimers: false)
    }
    static func run() -> Bool {
        defer { for name in suites { UserDefaults.standard.removePersistentDomain(forName: name) }; suites = [] }
        var failures: [String] = []
        ResetRadarSelfTest.check(into: &failures)
        ControlSelfTest.check(into: &failures)
        UpgradeSelfTest.check(into: &failures)

        check(EnergyLogic.remainingPercent(fromUsedPercent: 0) == 100, "0% used should leave 100%", into: &failures)
        check(EnergyLogic.remainingPercent(fromUsedPercent: 66) == 34, "66% used should leave 34%", into: &failures)
        check(EnergyLogic.remainingPercent(fromUsedPercent: 99.6) == 0, "remaining percentage should round", into: &failures)
        check(EnergyLogic.remainingPercent(fromUsedPercent: -5) == 100, "remaining percentage should clamp high", into: &failures)
        check(EnergyLogic.remainingPercent(fromUsedPercent: 120) == 0, "remaining percentage should clamp low", into: &failures)

        // Click/drag arbitration is measured in screen points at every visual size.
        for scale in CompactPanelSize.allCases {
            let start = CGPoint(x: 100 * scale.scale, y: 100 * scale.scale)
            var click = CompactPointerTracking(start: start, target: .quota)
            check(click.finish(at: CGPoint(x: start.x + 3, y: start.y + 1), target: .quota) == .quota,
                  "small pointer jitter should still click at \(scale)", into: &failures)
            var boundary = CompactPointerTracking(start: start, target: .projects)
            check(boundary.finish(at: CGPoint(x: start.x + 4, y: start.y), target: .projects) == .projects,
                  "exactly four points should remain a click", into: &failures)
            var drag = CompactPointerTracking(start: start, target: .quota)
            drag.update(to: CGPoint(x: start.x + 4.1, y: start.y))
            check(drag.finish(at: start, target: .quota) == nil && drag.isDragging,
                  "returning to the start must not restore a cancelled click", into: &failures)
            var cross = CompactPointerTracking(start: start, target: .quota)
            check(cross.finish(at: start, target: .projects) == nil,
                  "release in another region must not navigate", into: &failures)
            var blank = CompactPointerTracking(start: start, target: nil)
            check(blank.finish(at: start, target: nil) == nil,
                  "blank areas and drag mark should not navigate", into: &failures)
            blank.update(to: CGPoint(x: start.x + 3, y: start.y + 3))
            check(blank.isDragging, "diagonal movement uses Euclidean distance", into: &failures)
            var releaseOnly = CompactPointerTracking(start: start, target: .projects)
            check(releaseOnly.finish(at: CGPoint(x: start.x + 8, y: start.y), target: .projects) == nil,
                  "mouse up must check distance even without a drag event", into: &failures)
        }

        let toneCases: [(Int?, EnergyTone)] = [
            (nil, .unavailable), (0, .red), (19, .red), (20, .yellow),
            (49, .yellow), (50, .green), (99, .green), (100, .green),
        ]
        for (value, expected) in toneCases {
            check(EnergyLogic.tone(for: value) == expected, "wrong tone for \(value.map(String.init) ?? "nil")", into: &failures)
        }

        let resetJSON = #"{"rateLimits":{"limitId":"codex"},"rateLimitResetCredits":{"availableCount":1,"credits":[{"id":"test-credit","resetType":"codexRateLimits","status":"available","grantedAt":1790707815,"expiresAt":1793299815,"title":"Full reset","description":null}]}}"#
        if let result = try? JSONDecoder().decode(RateLimitReadResult.self, from: Data(resetJSON.utf8)) {
            check(result.rateLimitResetCredits?.availableCount == 1, "reset credits count should decode", into: &failures)
            let credit = result.rateLimitResetCredits?.credits?.first
            check(credit?.displayTitle == "完全重置", "full reset should display a Chinese title", into: &failures)
            check(credit?.expirationText(now: Date(timeIntervalSince1970: 0)) == "将于 10月30日 02:50（GMT+8）到期", "credit expiration should use GMT+8", into: &failures)
            let merged = EnergyLogic.mergingSparseUpdate(RateLimitSnapshot(limitId: "codex", primary: nil, secondary: nil), into: result)
            check(merged.rateLimitResetCredits == result.rateLimitResetCredits, "quota notifications must preserve reset credits", into: &failures)
            let store = makeStore()
            store.apply(result)
            store.markUnavailable()
            check(store.resetCredits == result.rateLimitResetCredits, "refresh failure must preserve reset credits", into: &failures)
        } else {
            failures.append("reset credits payload should decode")
        }
        let countOnlyJSON = #"{"availableCount":1}"#
        let countOnly = try? JSONDecoder().decode(RateLimitResetCreditsSummary.self, from: Data(countOnlyJSON.utf8))
        check(countOnly?.credits == nil && countOnly?.availableCount == 1, "count-only credits must not invent expiry details", into: &failures)
        let noExpiry = RateLimitResetCredit(id: "no-expiry", resetType: "codexRateLimits", status: "available", grantedAt: 0, expiresAt: nil, title: nil, description: nil)
        check(noExpiry.expirationText() == "无到期时间", "null expiration means no expiry", into: &failures)

        // Extra balance sources: parsers, store state and placeholder ordering.
        check(BalanceFormatting.money("12.3") == "12.30", "money formatting keeps cents", into: &failures)
        check(BalanceFormatting.credits("195.12000212") == "195.12", "credits formatting rounds", into: &failures)
        let deepSeekFixture = #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"6.06","granted_balance":"0.00","topped_up_balance":"6.06"}]}"#
        check(DeepSeekBalanceParser.reading(from: Data(deepSeekFixture.utf8)).valueText == "6.06",
              "deepseek balance parsing", into: &failures)
        let workBuddyFixture = #"{"code":0,"data":{"TotalCredits":"195.12000212","SubscriptionPackageName":"体验版","Packages":[{"CycleTotalCapacity":"500","CycleUsedCapacity":"304.88"}]}}"#
        check(WorkBuddyBalanceParser.reading(from: Data(workBuddyFixture.utf8)).valueText == "195.12",
              "workbuddy credit parsing", into: &failures)
        let doubaoFixture = #"{"code":0,"data":{"window_limit_section":{"window_limit_groups":[{"window_limits":[{"end_time":1792819135023,"used_percent":29,"window_type":2}]}]}}}"#
        check(DoubaoQuotaParser.reading(from: Data(doubaoFixture.utf8)).valueText == "71",
              "doubao quota parsing", into: &failures)
        let codexLimit = QuotaLimitReading(id: "codex-primary", title: "周额度", remainingPercent: 3,
                                          resetsAt: Date().addingTimeInterval(6 * 86400), windowDurationMins: 10_080)
        let codexReading = BalanceReading.codex(limits: [codexLimit])
        check(codexReading.percent == 3 && codexReading.caption == "周额度剩余",
              "codex joins the balance page with its weekly window", into: &failures)
        let advisorReadings: [BalanceReading] = [
            codexReading,
            BalanceReading(id: "deepseek", title: "DeepSeek", systemImage: "sparkles", valueText: "43.06",
                           unitPrefix: "¥", unitSuffix: nil, caption: "账户余额", detail: nil, percent: nil,
                           windows: [], state: .ok, sourceURL: nil, updatedAt: .now, numericValue: 43.06, currency: "CNY"),
            BalanceReading(id: "doubao", title: "豆包", systemImage: "bubble.left.and.bubble.right",
                           valueText: "71", unitPrefix: nil, unitSuffix: "%", caption: "近 7 天剩余额度",
                           detail: nil, percent: 71, windows: [
                               BalanceWindowReading(id: "H5", title: "5 小时", remainingPercent: 15, resetAt: Date().addingTimeInterval(3600)),
                               BalanceWindowReading(id: "D7", title: "近 7 天", remainingPercent: 71, resetAt: Date().addingTimeInterval(3 * 86400)),
                           ], state: .ok, sourceURL: nil, updatedAt: .now),
            BalanceReading(id: "workbuddy", title: "WorkBuddy", systemImage: "briefcase", valueText: "195.12",
                           unitPrefix: nil, unitSuffix: " 积分", caption: "剩余积分", detail: nil, percent: 3,
                           windows: [], state: .ok, sourceURL: nil, updatedAt: .now),
        ]
        let advice = AIUsageAdvisor.advise(readings: advisorReadings)
        check(advice.recommendedID == "doubao", "advisor prefers a healthy subscription over cash", into: &failures)
        check(advice.levels["codex"] == .critical && advice.levels["workbuddy"] == .critical,
              "advisor marks near-empty accounts", into: &failures)

        let balanceStore = makeStore()
        check(balanceStore.balances.map(\.id) == BalanceProvider.allCases.map(\.id),
              "balance placeholders follow provider order", into: &failures)
        balanceStore.beginBalanceRefresh()
        balanceStore.applyBalance(DeepSeekBalanceParser.reading(from: Data(deepSeekFixture.utf8)))
        balanceStore.finishBalanceRefresh()
        check(balanceStore.balances.first { $0.id == "deepseek" }?.state == .ok,
              "balance store applies readings", into: &failures)
        check(balanceStore.lastBalanceUpdate != nil && !balanceStore.isRefreshingBalances,
              "balance refresh finishes", into: &failures)

        let overallWindow = RateLimitWindow(usedPercent: 10, windowDurationMins: 10_080, resetsAt: 2_000)
        let legacyShortWindow = RateLimitWindow(usedPercent: 66, windowDurationMins: 300, resetsAt: 1_000)
        let readings = EnergyLogic.accountReadings(
            from: RateLimitReadResult(
                rateLimits: RateLimitSnapshot(limitId: "codex", primary: overallWindow, secondary: nil),
                rateLimitsByLimitId: ["codex_bengalfox": RateLimitSnapshot(limitId: "codex_bengalfox", limitName: "GPT-5.3-Codex-Spark", primary: legacyShortWindow, secondary: nil)]
            )
        )
        check(readings.weekly.remainingPercent == 90, "primary should remain the weekly account quota", into: &failures)
        check(readings.spark.remainingPercent == 34, "secondary should remain the Spark model quota", into: &failures)
        check(readings.weekly.resetsAt == Date(timeIntervalSince1970: 2_000), "weekly reset date should decode", into: &failures)
        check(readings.spark.resetsAt == Date(timeIntervalSince1970: 1_000), "Spark must keep its independent reset date", into: &failures)
        let inheritedResetReadings = EnergyLogic.accountReadings(
            from: RateLimitReadResult(
                rateLimits: RateLimitSnapshot(limitId: "codex", primary: overallWindow, secondary: nil),
                rateLimitsByLimitId: nil
            )
        )
        check(inheritedResetReadings.spark.remainingPercent == nil, "missing Spark percentage must stay unavailable", into: &failures)
        check(inheritedResetReadings.spark.resetsAt == nil, "absent Spark bucket must not inherit a reset time", into: &failures)
        let dynamicLimits = EnergyLogic.quotaLimits(from: sparseResultForTest(overallWindow))
        check(dynamicLimits.count == 1 && dynamicLimits.first?.title == "周额度", "only received quota windows should be displayed", into: &failures)
        check(
            EnergyLogic.compactResetDateText(
                Date(timeIntervalSince1970: 0),
                timeZone: TimeZone(secondsFromGMT: 0) ?? .current
            ) == "1月1日 00:00:00",
            "compact reset date should include hours, minutes, and seconds",
            into: &failures
        )
        check(
            EnergyLogic.statusBarResetDateText(
                Date(timeIntervalSince1970: 0),
                timeZone: TimeZone(secondsFromGMT: 0) ?? .current
            ) == "1/1 00:00:00",
            "status-bar reset date should stay precise while using a compact format",
            into: &failures
        )
        check(EnergyLogic.remainingDays(until: nil) == nil, "missing reset date should have no remaining days", into: &failures)
        check(EnergyLogic.windowDurationText(300) == "5小时", "window duration should format hours", into: &failures)
        let countdownNow = Date(timeIntervalSince1970: 1_000_000)
        check(
            EnergyLogic.resetCountdownText(until: countdownNow.addingTimeInterval(23 * 3_600 + 15 * 60), now: countdownNow) == "约23小时15分",
            "reset countdown under two days should show hours and minutes",
            into: &failures
        )
        let sparseCurrent = RateLimitReadResult(
            rateLimits: RateLimitSnapshot(limitId: "codex", primary: overallWindow, secondary: nil),
            rateLimitsByLimitId: ["codex_bengalfox": RateLimitSnapshot(limitId: "codex_bengalfox", limitName: "GPT-5.3-Codex-Spark", primary: legacyShortWindow, secondary: nil)]
        )
        let anonymousUpdate = RateLimitSnapshot(limitId: nil, primary: RateLimitWindow(usedPercent: 90, windowDurationMins: nil, resetsAt: nil), secondary: nil)
        check(EnergyLogic.mergingSparseUpdate(anonymousUpdate, into: sparseCurrent) == sparseCurrent, "anonymous sparse update must not overwrite a quota bucket", into: &failures)
        let namedUpdate = RateLimitSnapshot(limitId: nil, limitName: "GPT-5.3-Codex-Spark", primary: RateLimitWindow(usedPercent: 20, windowDurationMins: nil, resetsAt: nil), secondary: nil)
        let mergedByName = EnergyLogic.mergingSparseUpdate(namedUpdate, into: sparseCurrent)
        check(mergedByName.rateLimitsByLimitId?["codex_bengalfox"]?.primary?.usedPercent == 20, "named sparse update should merge into the matching model quota", into: &failures)

        let missing = EnergyLogic.accountReadings(
            from: RateLimitSnapshot(limitId: "codex", primary: nil, secondary: nil)
        )
        check(missing == .unavailable, "missing windows should be unavailable", into: &failures)
        check(CompactPanelSize.default.scale == 1, "default compact panel size should be 100%", into: &failures)
        check(CompactPanelSize.level1.scale < CompactPanelSize.level5.scale, "compact panel size presets should increase", into: &failures)
        check(CompactPanelSize.allCases.map(\.scale) == CompactPanelSize.allCases.map(\.scale).sorted(), "all compact size presets should be ordered", into: &failures)
        check(
            EnergyPanelLayout.size(for: .quota) == EnergyPanelLayout.size(for: .projects),
            "dashboard tabs should keep one window size",
            into: &failures
        )
        check(
            EnergyPanelLayout.size(for: .compact, compactSize: .level1).width < EnergyPanelLayout.expandedSize.width,
            "compact bar should remain smaller than the dashboard",
            into: &failures
        )
        let modeStore = makeStore()
        check(!modeStore.hasLoadedProjects, "project loading state should begin unresolved", into: &failures)
        modeStore.applyProjects(ProjectUsageDaySummary(projects: [], sessionSwitchCount: 0))
        check(modeStore.hasLoadedProjects, "first project scan should resolve the loading state", into: &failures)
        modeStore.setMode(.quota)
        modeStore.setMode(.quota)
        check(modeStore.mode == .quota, "reselecting quota should not jump back to the main card", into: &failures)
        modeStore.setCompactMode()
        check(modeStore.mode == .compact, "return action should explicitly show the main card", into: &failures)
        modeStore.apply(RateLimitReadResult(rateLimits: RateLimitSnapshot(limitId: "codex", primary: overallWindow, secondary: nil), rateLimitsByLimitId: nil))
        modeStore.beginRefresh()
        modeStore.markUnavailable()
        check(modeStore.quotas.weekly.remainingPercent == 90, "temporary refresh failure should keep the last valid quota", into: &failures)
        check(modeStore.quotaRefreshError != nil, "temporary refresh failure should be visible in details", into: &failures)
        check(EnergyLogic.shortResetText(until: countdownNow.addingTimeInterval(3 * 24 * 3_600), now: countdownNow) == "约3天后重置", "mini reset text should show rounded days", into: &failures)
        check(!modeStore.isRefreshing, "failure must finish the quota refresh state", into: &failures)
        modeStore.beginProjectRefresh()
        modeStore.beginRefresh()
        modeStore.applyProjects(ProjectUsageDaySummary(projects: [], sessionSwitchCount: 0))
        check(!modeStore.isRefreshingProjects && modeStore.isRefreshing, "project completion must not finish quota refresh", into: &failures)
        modeStore.markUnavailable()
        check(TokenFormatting.compact(1_234_500_000_000) == "1.2万亿", "compact tokens should omit grouping separators", into: &failures)
        check(TokenFormatting.exact(27_000_000) == "27,000,000", "exact token counts should preserve grouping", into: &failures)
        check(TokenFormatting.compact(27_000_000) == "2700万", "large token numbers should use Chinese units", into: &failures)
        checkPanelGeometry(into: &failures)

        checkProjectUsage(into: &failures)

        if failures.isEmpty {
            print("Self-test passed: quota parsing, balance parsing, colors, independent resets, sparse updates, panel geometry, mode behavior, project usage")
            return true
        }
        failures.forEach { print("Self-test failed: \($0)") }
        return false
    }

    private static func sparseResultForTest(_ window: RateLimitWindow) -> RateLimitReadResult {
        RateLimitReadResult(rateLimits: RateLimitSnapshot(limitId: "codex", primary: window, secondary: nil), rateLimitsByLimitId: nil)
    }

    private static func checkPanelGeometry(into failures: inout [String]) {
        let visible = CGRect(x: 100, y: 100, width: 600, height: 400)
        let clamped = PanelFrameLayout.clamped(CGRect(x: 900, y: -50, width: 240, height: 52), to: visible)
        check(clamped.minX == 460 && clamped.minY == 100, "panel frame should remain inside the visible screen", into: &failures)
        let oversized = PanelFrameLayout.clamped(CGRect(x: 0, y: 0, width: 800, height: 500), to: visible)
        check(oversized.minX == visible.minX && oversized.minY == visible.minY, "oversized panel should keep a reachable origin", into: &failures)
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String, into failures: inout [String]) {
        if !condition() { failures.append(message) }
    }

    private static func checkProjectUsage(into failures: inout [String]) {
        let now = Date()
        let active = now.addingTimeInterval(-60)
        let older = ProjectUsageLogic.startOfDay(containing: now).addingTimeInterval(-1)
        let sessionA = ProjectUsageMonitor.parseSession(
            sessionLog(id: "a", cwd: "/tmp/alpha", events: [(active, 100, 20, 5, 80), (active.addingTimeInterval(10), 40, 10, 2, 30)]),
            fallbackID: "fallback-a",
            now: now
        )
        let sessionB = ProjectUsageMonitor.parseSession(
            sessionLog(id: "b", cwd: "/tmp/alpha", events: [(active.addingTimeInterval(20), 30, 7, 1, 20)]),
            fallbackID: "fallback-b",
            now: now
        )
        let expired = ProjectUsageMonitor.parseSession(
            sessionLog(id: "old", cwd: "/tmp/old", events: [(older, 500, 20, 0, 0)]),
            fallbackID: "fallback-old",
            now: now
        )
        check(sessionA?.totals.totalTokens == 170, "turn usage should be summed within a session", into: &failures)
        check(expired == nil, "usage before today's Shanghai boundary should be excluded", into: &failures)

        let sessions = [sessionA, sessionB].compactMap { $0 }
        let alpha = ProjectUsageLogic.aggregate(sessions).first
        check(alpha?.projectName == "alpha", "directory name should become project name", into: &failures)
        check(alpha?.totals.totalTokens == 207, "sessions in one project should be merged", into: &failures)
        check(ProjectUsageMonitor.parseSession("not json", fallbackID: "bad", now: now) == nil, "malformed logs should be ignored", into: &failures)

        var incremental = ProjectUsageSessionAccumulator(fallbackID: "incremental-fallback")
        let firstIncrement = sessionLog(
            id: "incremental",
            cwd: "/tmp/incremental",
            events: [(active, 11, 3, 1, 5)]
        ) + "\n"
        let pending = incremental.consumeCompleteJSONLines(
            in: Data(firstIncrement.utf8),
            startOfDay: ProjectUsageLogic.startOfDay(containing: now),
            includesSessionMetadata: true
        )
        check(pending.isEmpty, "complete JSONL input should not leave a pending line", into: &failures)
        check(incremental.makeSession()?.totals.totalTokens == 14, "initial incremental scan should read Token totals", into: &failures)

        let appendedLog = sessionLog(
            id: "incremental",
            cwd: "/tmp/incremental",
            events: [(active.addingTimeInterval(30), 7, 4, 1, 2)]
        )
        let appendedLine = appendedLog.split(separator: "\n").last.map(String.init) ?? ""
        _ = incremental.consumeCompleteJSONLines(
            in: Data("\(appendedLine)\n".utf8),
            startOfDay: ProjectUsageLogic.startOfDay(containing: now),
            includesSessionMetadata: false
        )
        check(incremental.makeSession()?.totals.totalTokens == 25, "appended JSONL should add only new Token usage", into: &failures)

        let ranked = (0..<6).map { index in
            ProjectUsageSession(
                id: "rank-\(index)",
                directory: "/tmp/project-\(index)",
                totals: ProjectUsageTotals(inputTokens: 1, outputTokens: 1, reasoningTokens: 0, cachedInputTokens: 0, turnCount: 1, maximumTurnTokens: 2),
                lastActivity: active.addingTimeInterval(TimeInterval(index))
            )
        }
        let fixtureRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        do {
            let logs = fixtureRoot.appendingPathComponent("logs")
            let link = fixtureRoot.appendingPathComponent("linked-logs")
            try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: logs)
            for index in 0..<6 {
                try (sessionLog(id: "fixture-\(index)", cwd: "/tmp/fixture-\(index)", events: [(now, 10, 2, 1, 3)]) + "\n")
                    .write(to: logs.appendingPathComponent("\(index).jsonl"), atomically: true, encoding: .utf8)
            }
            let linkedSummary = ProjectUsageMonitor.readToday(from: [link], now: now)
            check(linkedSummary.projects.count == 6 && linkedSummary.allProjectTotals.totalTokens == 72,
                "symlinked log roots must include all six projects", into: &failures)
        } catch {
            failures.append("symlink fixture failed: \(error)")
        }
        let top = ProjectUsageLogic.aggregate(ranked)
        check(top.count == 6 && top.first?.projectName == "project-5", "all projects must remain in the data summary", into: &failures)
        let fullSummary = ProjectUsageDaySummary(projects: top, sessionSwitchCount: 0)
        check(fullSummary.allProjectTotals.totalTokens == 12, "six projects must contribute to the daily total", into: &failures)
        check(ProjectUsageLogic.aggregate(ranked, limit: 5).count == 5, "display may explicitly request a top five subset", into: &failures)
    }

    private static func sessionLog(id: String, cwd: String, events: [(Date, Int, Int, Int, Int)]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let meta = "{\"type\":\"session_meta\",\"payload\":{\"id\":\"\(id)\",\"cwd\":\"\(cwd)\"}}"
        let rows = events.map { event in
            "{\"timestamp\":\"\(formatter.string(from: event.0))\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"last_token_usage\":{\"input_tokens\":\(event.1),\"output_tokens\":\(event.2),\"reasoning_output_tokens\":\(event.3),\"cached_input_tokens\":\(event.4)}}}}"
        }
        return ([meta] + rows).joined(separator: "\n")
    }
}
