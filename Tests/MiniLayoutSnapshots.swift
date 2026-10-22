import AppKit
import SwiftUI

/// Standalone visual fixtures; never starts RPC or modifies user preferences.
@main
struct MiniLayoutSnapshots {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let destination = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for dark in [false, true] {
            for size in CompactPanelSize.allCases {
                for scenario in ["full", "no-watch", "error", "watch-no-odds", "reference", "average", "countdown", "countdown-days", "countdown-due"] {
                    let failure = scenario == "error"
                    let scale = size.scale
                    let limits = [QuotaLimitReading(id: "codex-primary", title: "周额度", remainingPercent: 100,
                        resetsAt: Date().addingTimeInterval(5 * 86400), windowDurationMins: 10080)]
                    let formatter = ISO8601DateFormatter()
                    let now = Date()
                    let watch = ["full", "watch-no-odds", "average"].contains(scenario) ? "{\"reset_chance_percent\":75,\"forecast_window\":\"next 24 hours\",\"observed_at\":\"\(formatter.string(from: now))\",\"expires_at\":\"\(formatter.string(from: now.addingTimeInterval(1800)))\",\"text\":\"Visual fixture only\",\"source\":{}}" : "null"
                    let primaryJSON = "{\"data\":{\"active_watch\":\(watch)},\"meta\":{\"generated_at\":\"\(formatter.string(from: now))\"}}"
                    var radar = ResetRadarSnapshot(primary: failure ? nil : try JSONDecoder().decode(ResetRadarSources.Primary.self, from: Data(primaryJSON.utf8)),
                        checkedAt: now, errors: failure ? ["Codex Resets 预警暂不可用"] : [])
                    if scenario.contains("countdown") {
                        let formatter = ISO8601DateFormatter()
                        let now = Date()
                        let offset: TimeInterval = scenario == "countdown-days" ? 172801 : (scenario == "countdown-due" ? -1 : 3661)
                        let json = """
                        {"data":{"scheduled_reset":{"scheduled_for":"\(formatter.string(from: now.addingTimeInterval(offset)))","announced_at":"\(formatter.string(from: now.addingTimeInterval(-3600)))","reset_type":"regular","text":"Visual fixture only","source":{}},"active_watch":{"reset_chance_percent":100,"forecast_window":"next 24 hours","observed_at":"\(formatter.string(from: now))","expires_at":"\(formatter.string(from: now.addingTimeInterval(1800)))","text":"Visual fixture only","source":{}}},"meta":{"generated_at":"\(formatter.string(from: now))"}}
                        """
                        radar.primary = try JSONDecoder().decode(ResetRadarSources.Primary.self, from: Data(json.utf8))
                    }
                    if scenario == "watch-no-odds" {
                        radar.primary = try JSONDecoder().decode(ResetRadarSources.Primary.self,
                            from: Data(primaryJSON.replacingOccurrences(of: "\"reset_chance_percent\":75", with: "\"reset_chance_percent\":null").utf8))
                    }
                    if ["reference", "average"].contains(scenario) {
                        let json = """
                        {"updated_at":"\(formatter.string(from: now))","last_reset_at":"\(formatter.string(from: now.addingTimeInterval(-3600)))","probabilities":{"rounded_24h":45},"confidence":"low"}
                        """
                        radar.reference = try JSONDecoder().decode(ResetReferenceForecast.self, from: Data(json.utf8))
                    }
                    let countdown = radar.countdownTarget(now: .now) != nil
                    let base = EnergyPanelLayout.compactBaseSize(showsCountdown: countdown)
                    let root = CompactEnergyBar(limits: limits, quotaError: failure ? "同步失败" : nil,
                        projectError: failure ? "同步失败" : nil, todayTokens: 1_234_500_000_000,
                        showQuota: {}, showProjects: {}, radarSnapshot: radar, showsCountdown: countdown, showRadar: {})
                        .frame(width: base.width, height: base.height)
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(width: base.width * scale, height: base.height * scale, alignment: .topLeading)
                        .energyPanelSurface(cornerRadius: 10 * scale)
                        .environment(\.colorScheme, dark ? .dark : .light)
                    let view = NSHostingView(rootView: root)
                    let frame = CGRect(x: 0, y: 0, width: base.width * scale, height: base.height * scale)
                    let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    window.contentView = view
                    view.frame = frame
                    view.layoutSubtreeIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                    view.layoutSubtreeIfNeeded()
                    let regions = markers(in: view)
                    precondition(regions.count == (countdown ? 4 : 3), "Every visible button must publish a layout marker")
                    let rects = regions.map { $0.convert($0.bounds, to: view) }
                    precondition(rects.allSatisfy { frame.insetBy(dx: -0.5, dy: -0.5).contains($0) }, "Hit regions must stay inside the window")
                    // Scaled adjoining edges can differ by ~1e-13 points after AppKit conversion.
                    precondition(rects.indices.allSatisfy { a in rects.indices.allSatisfy { b in a == b || !rects[a].insetBy(dx: 0.001, dy: 0.001).intersects(rects[b]) } }, "Action regions must not overlap: \(rects)")
                    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    let name = "\(dark ? "dark" : "light")-\(size.rawValue)-\(scenario).png"
                    try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name))
                    print("PASS \(name) regions=\(rects)")
                    window.close()
                }
            }
        }
    }

    @MainActor static func markers(in view: NSView) -> [CompactActionRegionView] {
        if let marker = view as? CompactActionRegionView { return [marker] }
        return view.subviews.flatMap { markers(in: $0) }
    }
}
