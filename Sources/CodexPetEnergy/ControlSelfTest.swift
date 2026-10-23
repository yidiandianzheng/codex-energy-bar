import Foundation

@MainActor enum ControlSelfTest {
    static func check(into failures: inout [String]) {
        func expect(_ value: Bool, _ text: String) { if !value { failures.append("control: " + text) } }
        expect((try? EnergyCLIRequest.parse(["show", "radar"]))?.value == "radar", "radar CLI routing")
        expect((try? EnergyCLIRequest.parse(["size", "5"]))?.value == "level5", "five size presets")
        for args in [["size", "0"], ["size", "6"], ["move", "nan", "1"], ["move", "inf", "2"], ["show", "unknown"], ["status", "extra"], ["shell", "anything"]] {
            expect((try? EnergyCLIRequest.parse(args)) == nil, "reject invalid input \(args)")
        }
        expect((try? EnergyCLIRequest(command: "size", value: "level9").validated()) == nil, "validate IPC size independently")
        for size in CompactPanelSize.allCases {
            let normal = EnergyPanelLayout.size(for: .compact, compactSize: size)
            let countdown = EnergyPanelLayout.size(for: .compact, compactSize: size, showsCountdown: true)
            expect(abs(countdown.height - normal.height - 22 * size.scale) < 0.01 && normal.width == countdown.width, "countdown adds only its own row")
        }
        let now = Date()
        let format = ISO8601DateFormatter()
        let json = """
        {"data":{"scheduled_reset":{"scheduled_for":"\(format.string(from: now.addingTimeInterval(3600)))","announced_at":"\(format.string(from: now.addingTimeInterval(-60)))","reset_type":"regular","text":"Test","source":{}},"active_watch":{"reset_chance_percent":100,"forecast_window":"24h","observed_at":"\(format.string(from: now.addingTimeInterval(-30)))","expires_at":"\(format.string(from: now.addingTimeInterval(300)))","text":"Test","source":{}}},"meta":{"generated_at":"\(format.string(from: now))"}}
        """
        guard let primary = try? JSONDecoder().decode(ResetRadarSources.Primary.self, from: Data(json.utf8)) else {
            failures.append("control: fixture decode failed"); return
        }
        let snapshot = ResetRadarSnapshot(primary: primary, checkedAt: now, errors: [])
        let store = SelfTest.makeStore(now: now)
        store.applyRadar(snapshot)
        expect(store.showsResetCountdown, "eligible snapshot expands countdown row")
        expect(snapshot.compactScheduleText(now: now)?.hasPrefix("来源预告") == true, "probability row retains scheduled date")
        store.updateCountdownVisibility(now: now.addingTimeInterval(301))
        expect(store.showsResetCountdown, "an official announcement outlives the watch that carried it")
        store.updateCountdownVisibility(now: now.addingTimeInterval(1801))
        expect(!store.showsResetCountdown, "a stale source removes the row without another network response")
        store.applyRadar(snapshot)
        store.applyRadar(ResetRadarSnapshot(checkedAt: now, errors: []))
        expect(!store.showsResetCountdown, "withdrawn schedule removes row")
    }
}
