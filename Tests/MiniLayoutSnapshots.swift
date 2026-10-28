import AppKit
import SwiftUI

/// Standalone visual fixtures; never starts RPC or modifies user preferences.
@main
struct MiniLayoutSnapshots {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        if !CommandLine.arguments.contains("--spot-check") { verifyInteractions() }
        if CommandLine.arguments.contains("--interaction-only") { return }
        let destination = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for dark in [false, true] {
            for size in CommandLine.arguments.contains("--spot-check") ? [CompactPanelSize.level1] : CompactPanelSize.allCases {
                for scenario in CommandLine.arguments.contains("--spot-check") ? ["full", "large-values", "error"] : ["full", "no-watch", "error", "watch-no-odds", "reference", "average", "countdown", "countdown-days", "countdown-due", "codex-only", "pricing", "night", "night-notice"] {
                    let failure = scenario == "error"
                    let scale = size.scale
                    let limits = [QuotaLimitReading(id: "codex-primary", title: "5 小时", remainingPercent: 75,
                        resetsAt: Date().addingTimeInterval(4 * 3600), windowDurationMins: 300),
                        QuotaLimitReading(id: "codex-secondary", title: "周额度", remainingPercent: 80,
                        resetsAt: Date().addingTimeInterval(5 * 86400), windowDurationMins: 10080)]
                    let formatter = ISO8601DateFormatter()
                    let now = Date()
                    let codex = BalanceReading.codex(limits: limits)
                    var readings = [
                        codex,
                        BalanceReading(id: "deepseek", title: "DeepSeek", systemImage: "sparkles",
                            valueText: scenario == "large-values" ? "123,456,789.12" : "43.06", unitPrefix: "¥", unitSuffix: nil,
                            caption: "账户余额", detail: "充值 ¥43.06 · 赠送 ¥0.00", percent: nil, windows: [],
                            state: .ok, sourceURL: nil, updatedAt: now, numericValue: scenario == "large-values" ? 123456789.12 : 43.06, currency: "CNY", sourceIdentity: "demo-deepseek"),
                        BalanceReading(id: "doubao", title: "豆包", systemImage: "bubble.left.and.bubble.right",
                            valueText: "15", unitPrefix: nil, unitSuffix: "%",
                            caption: "当前时段剩余 · 标准套餐", detail: "2 小时后重置 · 近 7 天 71%",
                            percent: 15,
                            windows: [
                                BalanceWindowReading(id: "H5", title: "5 小时", remainingPercent: 15, resetAt: now.addingTimeInterval(3600), isPrimary: true),
                                BalanceWindowReading(id: "D7", title: "近 7 天", remainingPercent: 71, resetAt: now.addingTimeInterval(3 * 86400)),
                            ],
                            state: .ok, sourceURL: nil, updatedAt: now),
                        BalanceReading(id: "workbuddy", title: "WorkBuddy", systemImage: "briefcase",
                            valueText: scenario == "large-values" ? "1,000,000,000,000,000" : "195.12", unitPrefix: nil, unitSuffix: " 积分",
                            caption: "剩余积分", detail: "体验版 · 已用 6,504.88 / 6,700", percent: 3, windows: [],
                            state: .ok, sourceURL: nil, updatedAt: now, numericValue: scenario == "large-values" ? 1_000_000_000_000_000 : 195.12, sourceIdentity: "demo-workbuddy"),
                        BalanceReading(id: "qwenwork", title: "千问办公", systemImage: "wand.and.stars",
                            valueText: scenario == "large-values" ? "123,456,789.1" : "1,989.6", unitPrefix: nil, unitSuffix: " 积分",
                            caption: "剩余积分", detail: "个人免费版", percent: nil, windows: [],
                            state: .ok, sourceURL: nil, updatedAt: now, numericValue: scenario == "large-values" ? 123456789.12 : 1989.59, currency: "credits", sourceIdentity: "demo-qwenwork"),
                        BalanceReading(id: "qoder", title: "Qoder CN", systemImage: "curlybraces",
                            valueText: scenario == "large-values" ? "123,456,789.1" : "373.0", unitPrefix: nil, unitSuffix: " 积分",
                            caption: "套餐积分剩余", detail: "Pro Trial · 附加 已用 25 / 100", percent: 93, windows: [],
                            state: .ok, sourceURL: nil, updatedAt: now, numericValue: scenario == "large-values" ? 123456789.12 : 373, currency: "credits", sourceIdentity: "demo-qoder"),
                        BalanceReading(id: "trae", title: "Trae CN", systemImage: "chevron.left.forwardslash.chevron.right",
                            valueText: scenario == "large-values" ? "123,456,789.1" : "576.9", unitPrefix: nil, unitSuffix: " 积分",
                            caption: "套餐积分剩余", detail: "每月登录积分 500 · 已用 23.1 / 600", percent: 96, windows: [],
                            state: .ok, sourceURL: nil, updatedAt: now, numericValue: scenario == "large-values" ? 123456789.12 : 576.9, currency: "credits", sourceIdentity: "demo-trae"),
                        BalanceReading(id: "workbuddyintl", title: "WorkBuddy AI", systemImage: "globe",
                            valueText: "88.4", unitPrefix: nil, unitSuffix: " 积分",
                            caption: "剩余积分", detail: "体验版", percent: 62, windows: [],
                            state: .ok, sourceURL: nil, updatedAt: now, numericValue: 88.4, currency: "credits", sourceIdentity: "demo-workbuddy-intl"),
                        BalanceReading(id: "dumate", title: "百度搭子", systemImage: "person.2.badge.gearshape",
                            valueText: "120.0", unitPrefix: nil, unitSuffix: " 积分",
                            caption: "剩余积分", detail: "个人版", percent: 41, windows: [],
                            state: .ok, sourceURL: nil, updatedAt: now, numericValue: 120, currency: "credits", sourceIdentity: "demo-dumate"),
                    ]
                    if failure {
                        readings[0].state = .stale("演示：保留上次额度")
                        readings[1] = BalanceProvider.deepseek.unconfigured("演示：尚未配置 API Key")
                        readings[2] = BalanceProvider.doubao.failed("演示：客户端未运行")
                        readings[3] = BalanceProvider.workbuddy.failed("演示：读取失败")
                        readings[4] = BalanceProvider.qwenwork.failed("演示：客户端未运行")
                        readings[5] = BalanceProvider.qoder.failed("演示：读取失败")
                        readings[6] = BalanceProvider.trae.unconfigured("演示：请先登录 Trae CN")
                        readings[7] = BalanceProvider.workbuddyintl.failed("演示：客户端未运行")
                        readings[8] = BalanceProvider.dumate.failed("演示：读取失败")
                    }
                    // Auto-hide worst case: the bar keeps only the primary account.
                    let visibleReadings = scenario == "codex-only" ? [codex] : readings
                    let advice = AIUsageAdvisor.advise(readings: visibleReadings)
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
                    let showsPricing = scenario == "pricing"
                    let nightWatchActive = scenario == "night"
                    let nightWatchNotice = scenario == "night-notice" ? "电量 9%，已自动关闭" : nil
                    let base = EnergyPanelLayout.compactBaseSize(accounts: visibleReadings.count,
                        showsCountdown: countdown, showsPricing: showsPricing)
                    let root = CompactEnergyBar(readings: visibleReadings, advice: advice,
                        todayTokens: 1_234_500_000_000, projectError: failure ? "同步失败" : nil,
                        showAccount: { _ in }, showAccounts: {}, showProjects: {},
                        radarSnapshot: radar, showsCountdown: countdown, showRadar: {},
                        pricingSnapshot: showsPricing ? PricingEngine.snapshot(at: now, catalog: .builtIn) : nil,
                        showsPricing: showsPricing, showPricing: {},
                        nightWatchActive: nightWatchActive,
                        nightWatchElapsed: nightWatchActive ? "已开启 2 小时 13 分" : nil,
                        nightWatchNotice: nightWatchNotice,
                        toggleNightWatch: {})
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
                    precondition(regions.count == visibleReadings.count + 4 + (countdown ? 1 : 0) + (showsPricing ? 1 : 0),
                                 "Every visible button must publish a layout marker")
                    let rects = regions.map { $0.convert($0.bounds, to: view) }
                    for (index, rect) in rects.enumerated() where !frame.insetBy(dx: -0.5, dy: -0.5).contains(rect) {
                        let line = "DEBUG overflow \(dark ? "dark" : "light")-\(size.rawValue)-\(scenario) idx=\(index) rect=\(rect) frame=\(frame)\n"
                        FileHandle.standardError.write(Data(line.utf8))
                    }
                    precondition(rects.allSatisfy { frame.insetBy(dx: -1, dy: -1).contains($0) }, "Hit regions must stay inside the window")
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


extension MiniLayoutSnapshots {
    /// Exercises the actual AppKit wrapper, not only its pointer math helper.
    @MainActor static func verifyInteractions() {
        // Ask only this fixture process to construct its SwiftUI accessibility tree.
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        let now = Date()
        let readings = ["codex", "deepseek", "doubao", "workbuddy", "qwenwork"].map { id in
            BalanceReading(id: id, title: id, systemImage: "circle", valueText: "42", unitPrefix: nil,
                unitSuffix: "%", caption: "演示", detail: nil, percent: 42, windows: [], state: .ok,
                sourceURL: nil, updatedAt: now, numericValue: 42, sourceIdentity: "demo-" + id)
        }
        var activated: [CompactActionTarget] = []
        var drags = 0
        let root = CompactEnergyBar(readings: readings, advice: .unavailable,
            todayTokens: 1234, projectError: nil,
            showAccount: { activated.append(.account($0)) },
            showAccounts: { activated.append(.balance) }, showProjects: { activated.append(.projects) })
        let wrapper = PanelContentView(rootView: root, menuProvider: { NSMenu() },
            dragDidEnd: { drags += 1 }, isCompact: { true }, activateCompactTarget: { activated.append($0) })
        let fixtureSize = EnergyPanelLayout.size(for: .compact, accounts: readings.count,
            compactSize: .level1, showsCountdown: false, showsPricing: false)
        let window = MiniInteractionPanel(contentRect: CGRect(origin: CGPoint(x: 100, y: 100), size: fixtureSize),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = wrapper
        wrapper.frame = CGRect(origin: .zero, size: fixtureSize)
        NSApp.setActivationPolicy(.accessory)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        wrapper.layoutSubtreeIfNeeded(); wrapper.refreshHostedContent()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        wrapper.layoutSubtreeIfNeeded()
        let regions = markers(in: wrapper).filter { if case .account = $0.target { return true }; return false }
        precondition(regions.count == 5, "Interaction fixture needs five account regions")
        func event(_ type: NSEvent.EventType, at point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        for region in regions {
            let point = region.convert(CGPoint(x: region.bounds.midX, y: region.bounds.midY), to: nil)
            activated = []
            wrapper.mouseDown(with: event(.leftMouseDown, at: point))
            wrapper.mouseUp(with: event(.leftMouseUp, at: point))
            precondition(activated == [region.target], "Mouse action must open its exact account: \(region.target)")
            print("PASS AppKit mouse account \(region.target)")
        }
        let point = regions[0].convert(CGPoint(x: regions[0].bounds.midX, y: regions[0].bounds.midY), to: nil)
        activated = []
        wrapper.mouseDown(with: event(.leftMouseDown, at: point))
        wrapper.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: point.x + 20, y: point.y + 12)))
        wrapper.mouseUp(with: event(.leftMouseUp, at: CGPoint(x: point.x + 20, y: point.y + 12)))
        precondition(activated.isEmpty && drags == 1, "Dragging must not activate navigation")
        print("PASS AppKit drag does not navigate")

        if let nightRegion = markers(in: wrapper).first(where: { $0.target == .nightWatch }) {
            let nightPoint = nightRegion.convert(CGPoint(x: nightRegion.bounds.midX, y: nightRegion.bounds.midY), to: nil)
            activated = []
            wrapper.mouseDown(with: event(.leftMouseDown, at: nightPoint))
            wrapper.mouseUp(with: event(.leftMouseUp, at: nightPoint))
            precondition(activated == [.nightWatch], "Night watch row must publish its toggle action")
            print("PASS AppKit night watch toggle")
        } else {
            preconditionFailure("Mini bar must expose the night watch action region")
        }

        // SwiftUI.AccessibilityNode implements AX selectors without declaring
        // NSAccessibilityProtocol, so inspect the objects returned by AppKit directly.
        var seen: Set<ObjectIdentifier> = []
        var buttons: [NSObject] = []
        func value(_ object: NSObject, _ name: String) -> AnyObject? {
            let selector = NSSelectorFromString(name)
            guard object.responds(to: selector) else { return nil }
            return object.perform(selector)?.takeUnretainedValue()
        }
        func label(_ object: NSObject) -> String? { value(object, "accessibilityLabel") as? String }
        func visit(_ object: AnyObject) {
            guard seen.insert(ObjectIdentifier(object)).inserted else { return }
            if let object = object as? NSObject {
                let role = value(object, "accessibilityRole") as? String
                if role == NSAccessibility.Role.button.rawValue { buttons.append(object) }
                if role != NSAccessibility.Role.unknown.rawValue {
                    print("AX fixture type=\(type(of: object)) role=\(role ?? "nil") label=\(label(object) ?? "nil")")
                }
                if let children = value(object, "accessibilityChildren") as? [AnyObject] {
                    for child in children { visit(child) }
                }
            }
            if let view = object as? NSView { for child in view.subviews { visit(child) } }
        }
        visit(wrapper)
        var pressed = 0
        for reading in readings {
            if let button = buttons.first(where: { label($0) == "\(reading.title)账户详情" }) {
                activated = []
                let selector = NSSelectorFromString("accessibilityPerformPress")
                precondition(button.responds(to: selector), "AX button must support Press")
                let press = unsafeBitCast(button.method(for: selector), to: (@convention(c) (AnyObject, Selector) -> Bool).self)
                precondition(press(button, selector), "SwiftUI accessibility button must support Press")
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
                precondition(activated == [.account(reading.id)], "Accessibility Press must open the same account")
                pressed += 1
                print("PASS AX Press account \(reading.id)")
            }
        }
        fflush(stdout)
        if !buttons.isEmpty {
            precondition(pressed == 5, "All five account buttons must be accessible when the AX tree is available")
        } else {
            print("UNVERIFIED AX Press and Space: fixture environment did not expose SwiftUI accessibility nodes")
        }
        for reading in readings {
            guard let button = buttons.first(where: { label($0) == "\(reading.title)账户详情" }) else { continue }
            activated = []
            let focusSelector = NSSelectorFromString("setAccessibilityFocused:")
            if button.responds(to: focusSelector) {
                let focus = unsafeBitCast(button.method(for: focusSelector), to: (@convention(c) (AnyObject, Selector, Bool) -> Void).self)
                focus(button, focusSelector, true)
            }
            if let down = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49),
               let up = NSEvent.keyEvent(with: .keyUp, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49) {
                window.sendEvent(down); window.sendEvent(up)
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
            if activated.isEmpty { print("UNVERIFIED actual Space key \(reading.id): fixture did not acquire keyboard focus") }
            else {
                precondition(activated == [.account(reading.id)], "Space must open its focused account")
                print("PASS actual Space key account \(reading.id)")
            }
        }
        window.close()
        NSApp.accessibilitySetValue(false, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        NSApp.setActivationPolicy(.prohibited)
    }
}

private final class MiniInteractionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
