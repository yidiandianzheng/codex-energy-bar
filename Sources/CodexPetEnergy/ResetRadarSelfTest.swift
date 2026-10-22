import Foundation

enum ResetRadarSelfTest {
    static func check(into failures: inout [String]) {
        func expect(_ value: Bool, _ message: String) { if !value { failures.append("radar: " + message) } }
        func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T? {
            try? JSONDecoder().decode(type, from: Data(json.utf8))
        }
        let now = ResetRadarSources.date("2026-10-13T07:20:00Z")!
        let emptyJSON = #"{"data":{"latest_reset":null,"scheduled_reset":null,"active_watch":null},"meta":{"generated_at":"2026-10-13T07:19:00Z"}}"#
        var snapshot = ResetRadarSnapshot(primary: decode(ResetRadarSources.Primary.self, emptyJSON), checkedAt: now, errors: [])
        expect(snapshot.primaryIsFresh(now: now), "a recent successful source is fresh without an active watch")
        expect(snapshot.probability(now: now) == nil && snapshot.countdownTarget(now: now) == nil, "no watch must remain unknown, not zero")
        expect(snapshot.compactText(now: now) == "重置雷达 · 暂无预警", "successful empty source must not appear as a failure")
        expect(snapshot.compactText(now: now.addingTimeInterval(1801)) == "重置雷达 · 数据已过期", "sleeping app ages the source")
        snapshot.errors = ["Codex Resets 消息暂不可用"]
        expect(snapshot.compactText(now: now) == "暂无预警 · 消息待同步", "message failure does not disguise working watch service")
        snapshot.primary = nil
        snapshot.archive = decode(ResetRadarSources.Archive.self, #"{"events":[]}"#)
        expect(snapshot.compactText(now: now) == "消息已更新 · 预警待同步", "working archive is a partial success")
        snapshot.archive = nil
        expect(snapshot.compactText(now: now) == "重置雷达 · 同步失败", "both unavailable means a real failure")
        let watchJSON = #"{"data":{"latest_reset":null,"scheduled_reset":null,"active_watch":{"reset_chance_percent":75,"forecast_window":"next 24 hours","observed_at":"2026-10-13T07:10:00Z","expires_at":"2026-10-13T08:00:00Z","text":"Test source signal","source":{"url":"https://x.com/thsottiaux/status/1"}}},"meta":{"generated_at":"2026-10-13T07:19:00Z"}}"#
        snapshot = ResetRadarSnapshot(primary: decode(ResetRadarSources.Primary.self, watchJSON), checkedAt: now, errors: [])
        expect(snapshot.probability(now: now) == 75 && snapshot.forecastIsFresh(now: now), "use only source watch odds")
        expect(snapshot.probabilityTitle(now: now) == "24h预警", "preserve a 24h source window")
        snapshot.primary = decode(ResetRadarSources.Primary.self, watchJSON.replacingOccurrences(of: "next 24 hours", with: "next 48 hours"))
        expect(snapshot.probabilityTitle(now: now) == "来源预警", "never relabel a 48h watch as 24h")
        for invalid in ["null", "101", "-1"] {
            snapshot.primary = decode(ResetRadarSources.Primary.self, watchJSON.replacingOccurrences(of: ":75", with: ":" + invalid))
            expect(snapshot.probability(now: now) == nil, "missing or invalid source odds are not invented")
        }
        let scheduledJSON = watchJSON.replacingOccurrences(of: #""scheduled_reset":null"#, with: #""scheduled_reset":{"scheduled_for":"2026-10-13T07:21:00Z","announced_at":"2026-10-13T07:00:00Z","reset_type":"regular","text":"Test only","source":{}}"#)
        snapshot.primary = decode(ResetRadarSources.Primary.self, scheduledJSON)
        expect(snapshot.countdownTarget(now: now) == nil, "75 percent must not start countdown")
        snapshot.primary = decode(ResetRadarSources.Primary.self, scheduledJSON.replacingOccurrences(of: ":75", with: ":89.9"))
        expect(snapshot.probability(now: now) == 90 && snapshot.countdownTarget(now: now) == nil, "rounded 89.9 percent must not pass the raw threshold")
        let countdownJSON = scheduledJSON.replacingOccurrences(of: ":75", with: ":90")
        snapshot.primary = decode(ResetRadarSources.Primary.self, countdownJSON)
        expect(snapshot.countdownText(now: now) == "更新倒计时 00:01:00", "90 percent plus precise source time starts countdown")
        expect(snapshot.countdownText(now: now.addingTimeInterval(1)) == "更新倒计时 00:00:59", "countdown updates every second")
        expect(snapshot.countdownText(now: now.addingTimeInterval(60)) == "时间已到·待确认", "deadline does not imply recovery")
        expect(snapshot.countdownTarget(now: now.addingTimeInterval(1801)) == nil, "stale status hides countdown")
        expect(snapshot.activeWatch(now: now.addingTimeInterval(3600)) == nil, "expired watch disappears")
        for json in [countdownJSON.replacingOccurrences(of: ":90", with: ":89"),
                     countdownJSON.replacingOccurrences(of: "2026-10-13T07:21:00Z", with: "unknown"),
                     countdownJSON.replacingOccurrences(of: "regular", with: "banked"),
                     watchJSON.replacingOccurrences(of: ":75", with: ":100"),
                     countdownJSON.replacingOccurrences(of: #""latest_reset":null"#, with: #""latest_reset":{"id":"done","reset_type":"regular","announced_at":"2026-10-13T07:19:00Z","text":"Done","source":{}}"#)] {
            snapshot.primary = decode(ResetRadarSources.Primary.self, json)
            expect(snapshot.countdownTarget(now: now) == nil, "low odds, invalid time, cards, no schedule or completion hide countdown")
        }
        snapshot.primary = decode(ResetRadarSources.Primary.self, countdownJSON.replacingOccurrences(of: "2026-10-13T07:21:00Z", with: "2026-10-13T20:00:00Z"))
        expect(snapshot.scheduleText(now: now) == "预告：10月14日 04:00", "source date converts across midnight in Beijing")
        expect(ResetRadarSources.safeLink("javascript:alert(1)") == nil, "external text is not executable")
        expect(ResetRadarSources.safeLink("file:///tmp/example") == nil, "source links cannot open local files")
        expect(ResetRadarSources.safeLink("https://x.com/thsottiaux/status/1") != nil, "public source links remain usable")
        snapshot = ResetRadarSnapshot(primary: decode(ResetRadarSources.Primary.self, watchJSON), checkedAt: now, errors: [])
        expect(snapshot.probabilitySourceName(now: now) == "Codex Resets", "probability is always attributed to selected main site")
        expect(snapshot.probabilitySourceURL(now: now)?.absoluteString == "https://codex-resets.com/zh-CN", "main site link is consistent")
        expect(snapshot.compactForecastDetail(now: now) == "观察至10/13 16:00", "watch expiry is labeled as observation, not a scheduled reset")
        let noOddsJSON = watchJSON.replacingOccurrences(of: ":75", with: ":null")
        snapshot.primary = decode(ResetRadarSources.Primary.self, noOddsJSON)
        expect(snapshot.probability(now: now) == nil && snapshot.activeWatch(now: now) != nil, "watch without odds remains useful evidence")
        expect(snapshot.compactText(now: now) == "重置观察 · 观察至10/13 16:00", "missing odds must not hide an active watch")
        expect(snapshot.countdownTarget(now: now) == nil, "observation deadline cannot start reset countdown")
        snapshot.primary = decode(ResetRadarSources.Primary.self, watchJSON)
        snapshot.errors = ["Codex Resets 预警暂不可用"]
        snapshot.checkedAt = now.addingTimeInterval(60)
        expect(snapshot.probability(now: now.addingTimeInterval(60)) == 75, "fresh retained source can survive a failed refresh")
        snapshot.checkedAt = now.addingTimeInterval(1801)
        expect(snapshot.probability(now: now.addingTimeInterval(1801)) == nil, "retry time cannot renew expired source metadata")
        snapshot.checkedAt = now
        for json in [watchJSON.replacingOccurrences(of: "2026-10-13T07:19:00Z", with: "2026-10-13T05:19:00Z"),
                     watchJSON.replacingOccurrences(of: "2026-10-13T07:19:00Z", with: "2026-10-14T07:19:00Z"),
                     watchJSON.replacingOccurrences(of: "2026-10-13T07:10:00Z", with: "2026-10-14T07:10:00Z"),
                     watchJSON.replacingOccurrences(of: "2026-10-13T08:00:00Z", with: "2026-10-13T07:09:00Z"),
                     watchJSON.replacingOccurrences(of: #""latest_reset":null"#, with: #""latest_reset":{"id":"done","reset_type":"regular","announced_at":"2026-10-13T07:19:00Z","text":"Done","source":{}}"#)] {
            snapshot.primary = decode(ResetRadarSources.Primary.self, json)
            expect(snapshot.activeWatch(now: now) == nil && snapshot.probability(now: now) == nil, "stale, future, reversed or completed watch is withheld")
        }
        let referenceJSON = #"{"updated_at":"2026-10-13T07:19:00Z","last_reset_at":"2026-10-13T06:00:00Z","probabilities":{"rounded_24h":45,"raw_24h":0.18},"confidence":"low"}"#
        snapshot = ResetRadarSnapshot(primary: decode(ResetRadarSources.Primary.self, emptyJSON),
            reference: decode(ResetReferenceForecast.self, referenceJSON), checkedAt: now, errors: [])
        expect(snapshot.probability(now: now) == 45 && !snapshot.isAveraged(now: now), "reference-only uses documented website display value, not raw baseline")
        expect(snapshot.probabilityTitle(now: now) == "24h预测" && snapshot.probabilitySourceName(now: now) == "codex-reset.com", "reference-only reading has its own label and attribution")
        snapshot.primary = nil
        expect(snapshot.probability(now: now) == 45, "reference works when primary request fails")
        snapshot.primary = decode(ResetRadarSources.Primary.self, watchJSON)
        expect(snapshot.probability(now: now) == 60 && snapshot.isAveraged(now: now), "75 and 45 receive equal weight")
        expect(snapshot.rawProbability(now: now) == 60 && snapshot.probabilityTitle(now: now) == "24h参考", "mean is explicitly a computed reference")
        expect(snapshot.probabilitySourceURL(now: now) == nil && snapshot.probabilitySourceName(now: now) == "双源平均", "mean cannot be attributed to just one website")
        snapshot.errors = ["codex-reset.com 参考暂不可用"]
        snapshot.checkedAt = now.addingTimeInterval(60)
        expect(snapshot.probability(now: now.addingTimeInterval(60)) == 60, "still-fresh cached input survives a failed request")
        snapshot.checkedAt = now.addingTimeInterval(1801)
        expect(snapshot.probability(now: now.addingTimeInterval(1801)) == nil, "a retry cannot renew expired source timestamps")
        snapshot.checkedAt = now
        snapshot.errors = []
        snapshot.primary = decode(ResetRadarSources.Primary.self, watchJSON.replacingOccurrences(of: "next 24 hours", with: "next 48 hours"))
        expect(snapshot.probability(now: now) == 75 && !snapshot.isAveraged(now: now), "different horizons are shown separately instead of averaged")
        expect(snapshot.probabilityTitle(now: now) == "来源预警", "48-hour input remains a source watch")
        snapshot.primary = decode(ResetRadarSources.Primary.self, watchJSON.replacingOccurrences(of: "next 24 hours", with: "next 124 hours"))
        expect(!snapshot.announcementIs24h(now: now), "124-hour text must not match 24 hours")
        snapshot.primary = decode(ResetRadarSources.Primary.self, watchJSON)
        for json in [referenceJSON.replacingOccurrences(of: ":45", with: ":101"),
                     referenceJSON.replacingOccurrences(of: ":45", with: ":-1"),
                     referenceJSON.replacingOccurrences(of: ":45", with: ":null"),
                     referenceJSON.replacingOccurrences(of: "rounded_24h", with: "undocumented_value"),
                     referenceJSON.replacingOccurrences(of: "2026-10-13T07:19:00Z", with: "2026-10-13T05:19:00Z"),
                     referenceJSON.replacingOccurrences(of: "2026-10-13T07:19:00Z", with: "2026-10-14T07:19:00Z"),
                     referenceJSON.replacingOccurrences(of: "2026-10-13T06:00:00Z", with: "2026-10-14T06:00:00Z")] {
            snapshot.reference = decode(ResetReferenceForecast.self, json)
            expect(snapshot.probability(now: now) == 75 && !snapshot.isAveraged(now: now), "invalid or stale reference falls back to primary instead of contributing zero")
        }
        snapshot.reference = decode(ResetReferenceForecast.self, referenceJSON)
        snapshot.primary = decode(ResetRadarSources.Primary.self, noOddsJSON)
        expect(snapshot.probability(now: now) == 45, "missing primary probability does not lower reference value")
        snapshot.primary = decode(ResetRadarSources.Primary.self, watchJSON.replacingOccurrences(of: ":75", with: ":0"))
        snapshot.reference = decode(ResetReferenceForecast.self, referenceJSON.replacingOccurrences(of: ":45", with: ":100"))
        expect(snapshot.isAveraged(now: now) && snapshot.probability(now: now) == 50, "an actual zero is a valid input, unlike missing data")
        snapshot.primary = decode(ResetRadarSources.Primary.self, countdownJSON)
        snapshot.reference = decode(ResetReferenceForecast.self, referenceJSON.replacingOccurrences(of: ":45", with: ":89.9"))
        expect(snapshot.probability(now: now) == 90 && snapshot.countdownTarget(now: now) == nil, "unrounded mean controls countdown threshold")
        snapshot.reference = decode(ResetReferenceForecast.self, referenceJSON.replacingOccurrences(of: ":45", with: ":90"))
        expect(snapshot.countdownText(now: now) == "更新倒计时 00:01:00", "qualifying mean still requires a precise primary announcement")
        snapshot.primary = decode(ResetRadarSources.Primary.self, emptyJSON)
        snapshot.reference = decode(ResetReferenceForecast.self, referenceJSON.replacingOccurrences(of: ":45", with: ":100"))
        expect(snapshot.countdownTarget(now: now) == nil, "reference probability cannot invent a scheduled time")
        snapshot.primary = decode(ResetRadarSources.Primary.self, watchJSON)
        snapshot.reference = decode(ResetReferenceForecast.self, referenceJSON.replacingOccurrences(of: "2026-10-13T06:00:00Z", with: "2026-10-13T07:11:00Z"))
        expect(snapshot.announcementProbability(now: now) == nil && snapshot.probability(now: now) == 45, "reference-confirmed reset invalidates an older primary watch")
        snapshot.primary = decode(ResetRadarSources.Primary.self, countdownJSON)
        snapshot.reference = decode(ResetReferenceForecast.self, referenceJSON.replacingOccurrences(of: ":45", with: ":100").replacingOccurrences(of: "2026-10-13T06:00:00Z", with: "2026-10-13T07:11:00Z"))
        expect(snapshot.countdownTarget(now: now) == nil, "a reset confirmed by reference also cancels an older primary announcement countdown")
        let laterPrimaryJSON = watchJSON.replacingOccurrences(of: #""latest_reset":null"#, with: #""latest_reset":{"id":"done","reset_type":"regular","announced_at":"2026-10-13T06:15:00Z","text":"Done","source":{}}"#)
        snapshot.primary = decode(ResetRadarSources.Primary.self, laterPrimaryJSON)
        snapshot.reference = decode(ResetReferenceForecast.self, referenceJSON)
        expect(snapshot.isAveraged(now: now), "observation and announcement minutes apart can describe the same completed reset")
        snapshot.reference = decode(ResetReferenceForecast.self, referenceJSON.replacingOccurrences(of: "2026-10-13T06:00:00Z", with: "2026-10-13T02:00:00Z"))
        expect(snapshot.probability(now: now) == 75 && !snapshot.isAveraged(now: now), "reference missing a newer reset cycle is excluded")
        expect(ResetRadarHTTP.retryDate("1200", now: now) == now.addingTimeInterval(1200), "Retry-After seconds are respected")
        expect(ResetRadarHTTP.retryDate("Tue, 13 Oct 2026 08:00:00 GMT", now: now) == ResetRadarSources.date("2026-10-13T08:00:00Z"), "Retry-After HTTP date is respected")
        expect(ResetRadarHTTP.retryDate("invalid", now: now) == now.addingTimeInterval(60), "invalid retry header uses minimum polling interval")
        var tracking = CompactPointerTracking(start: .zero, target: .radar)
        tracking.update(to: CGPoint(x: 5, y: 0))
        expect(tracking.finish(at: .zero, target: .radar) == nil, "radar shares drag versus click arbitration")
    }
}
