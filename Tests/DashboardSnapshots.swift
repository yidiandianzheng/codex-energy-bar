import AppKit
import SwiftUI

/// Explicit demonstration data. Isolated preferences, no client, network or production ledger.
@main struct DashboardSnapshots {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let destination = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let now = Date()
        let suite = "compute-ring-demo-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        for dark in [false, true] {
            for scenario in CommandLine.arguments.contains("--projects-only") ? ["normal"] : ["normal", "errors", "stale", "long-values"] {
                defaults.removePersistentDomain(forName: suite)
                let store = EnergyStore(defaults: defaults, now: now.addingTimeInterval(-300), startsTimers: false)
                var samples: [BalanceReading] = []
                let quotaResult = RateLimitReadResult(rateLimits: RateLimitSnapshot(limitId: "codex", primary: RateLimitWindow(usedPercent: 32, windowDurationMins: 300, resetsAt: now.addingTimeInterval(7200).timeIntervalSince1970), secondary: RateLimitWindow(usedPercent: 58, windowDurationMins: 10080, resetsAt: now.addingTimeInterval(3 * 86400).timeIntervalSince1970)), rateLimitsByLimitId: nil)
                store.apply(quotaResult)
                for provider in BalanceProvider.allCases {
                    let isCredits = provider == .qwenwork || provider == .qoder || provider == .trae
                    let isPoints = provider == .workbuddy || provider == .workbuddyintl || provider == .dumate
                    var reading = BalanceReading(id: provider.id, title: provider.title, systemImage: provider.systemImage,
                        valueText: provider == .doubao ? "71"
                            : isCredits ? (scenario == "long-values" ? "123,456,789.1" : (provider == .qwenwork ? "1,989.6" : provider == .qoder ? "373.0" : "576.9"))
                            : (scenario == "long-values" ? "123,456,789.12" : "43.06"),
                        unitPrefix: provider == .deepseek ? "¥" : nil,
                        unitSuffix: provider == .doubao ? "%" : (isPoints || isCredits ? " 积分" : nil),
                        caption: provider == .deepseek ? "账户余额" : (isCredits ? "套餐积分剩余" : "剩余可用"),
                        detail: "演示账户 · 仅供界面检查",
                        percent: provider == .doubao ? 71 : (provider == .qoder ? 93 : (provider == .trae ? 96 : nil)),
                        windows: provider == .doubao ? [BalanceWindowReading(id: "demo-window", title: "当前时段", remainingPercent: 71, resetAt: now.addingTimeInterval(3600), isPrimary: true)] : [],
                        state: .ok, sourceURL: nil, updatedAt: now.addingTimeInterval(-300), numericValue: scenario == "long-values" ? 123456791.12 : (provider == .deepseek ? 45.06 : (isCredits ? 1989.59 : 43.06)), numericUsedValue: isPoints ? 100 : (isCredits ? 23.1 : nil), currency: provider == .deepseek ? "CNY" : (isCredits ? "credits" : nil), sourceIdentity: "demo-" + provider.id)
                    if scenario == "errors" {
                        reading = provider.placeholder()
                        reading.state = provider == .deepseek ? .unconfigured("尚未配置演示 API Key") : .failed("演示：客户端未运行，请打开客户端后刷新。其余账户仍可查看。")
                    }
                    if scenario == "stale" { reading.updatedAt = now.addingTimeInterval(-3600); reading.state = .stale("演示：本次读取失败，保留上次读数") }
                    store.applyBalance(reading)
                    samples.append(reading)
                }
                store.tick(now: now)
                store.apply(quotaResult)
                if scenario == "normal" || scenario == "long-values" {
                    for var reading in samples {
                        reading.updatedAt = now
                        if reading.id == "deepseek" { reading.numericValue = scenario == "long-values" ? 123456789.12 : 43.06 }
                        if reading.id == "workbuddy" { reading.numericUsedValue = 102 }
                        store.applyBalance(reading)
                    }
                }
                store.finishBalanceRefresh()
                store.applyProjects(ProjectUsageDaySummary(projects: [ProjectUsageReading(directory: "/demo/project", projectName: "演示项目 · 长名称与大数值", totals: ProjectUsageTotals(inputTokens: 1234567890, outputTokens: 654321, reasoningTokens: 12000, cachedInputTokens: 400000, turnCount: 48, maximumTurnTokens: 100000), lastActivity: now)], sessionSwitchCount: 0))
                let iso = ISO8601DateFormatter()
                let radarJSON = """
                {"data":{"active_watch":{"reset_chance_percent":65,"forecast_window":"next 24 hours","observed_at":"\(iso.string(from: now))","expires_at":"\(iso.string(from: now.addingTimeInterval(3600)))","text":"Demonstration only: simulated public signal for layout review.","source":{}}},"meta":{"generated_at":"\(iso.string(from: now))"}}
                """
                let primary = try JSONDecoder().decode(ResetRadarSources.Primary.self, from: Data(radarJSON.utf8))
                store.applyRadar(ResetRadarSnapshot(primary: scenario == "errors" ? nil : primary, checkedAt: now, errors: scenario == "errors" ? ["演示：来源暂不可用"] : []))
                for mode in CommandLine.arguments.contains("--projects-only") ? [EnergyPanelMode.projects] : [EnergyPanelMode.balance, .quota, .projects, .radar, .pricing] {
                    for account in mode == .quota ? ["codex", "deepseek", "doubao", "workbuddy", "qwenwork", "qoder", "trae"] : ["codex"] {
                        store.setMode(mode); store.selectAccount(account)
                        let root = VStack(spacing: 0) {
                            Text("演示数据 · 界面检查").font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 8)
                            EnergyDashboardView(store: store, selectMode: { _ in }, refresh: {}, showMore: {}, collapse: {})
                        }.frame(width: 420, height: 520).background(EnergyVisualStyle.panelBackground)
                            .environment(\.colorScheme, dark ? .dark : .light)
                        let view = NSHostingView(rootView: root)
                        let frame = CGRect(x: 0, y: 0, width: 420, height: 520)
                        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
                        window.isReleasedWhenClosed = false
                        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                        window.contentView = view; view.frame = frame
                        view.layoutSubtreeIfNeeded()
                        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
                        view.layoutSubtreeIfNeeded()
                        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        let name = "\(dark ? "dark" : "light")-\(mode.rawValue)-\(account)-\(scenario)-DEMO.png"
                        try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name))
                        print("PASS demonstration \(name)")
                        window.close()
                    }
                }
            }
        }
    }
}
