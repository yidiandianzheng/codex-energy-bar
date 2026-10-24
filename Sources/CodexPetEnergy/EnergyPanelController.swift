import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class EnergyPanelController: NSObject, NSWindowDelegate {
    private enum PositionKeys {
        static let x = "codex-energy-panel-position-x"
        static let y = "codex-energy-panel-position-y"
    }

    private let store: EnergyStore
    private let refreshData: () -> Void
    private let refreshBalances: () -> Void
    private let panel: EnergyFloatingPanel
    private var statusItem: NSStatusItem?
    private var modeObserver: AnyCancellable?
    private var countdownObserver: AnyCancellable?
    private var pricingRowObserver: AnyCancellable?
    private var displayedMode: EnergyPanelMode = .compact
    private var suppressAnimations = false
    private var snapshotPath: String?
    private var refreshHostedContent: (() -> Void)?
    private var compactOrigin: CGPoint?

    init(store: EnergyStore, refreshBalances: @escaping () -> Void, refreshData: @escaping () -> Void) {
        self.store = store
        self.refreshData = refreshData
        self.refreshBalances = refreshBalances
        panel = EnergyFloatingPanel(
            contentRect: CGRect(origin: .zero, size: EnergyPanelLayout.size(
                for: .compact,
                showsCountdown: store.showsResetCountdown,
                showsPricing: store.showsPricingRow
            )),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        let contentView = PanelContentView(
            rootView: EnergyPanelView(store: store, refresh: refreshData, showMore: { [weak self] in self?.showMore() }),
            menuProvider: { [weak self] in self?.makeMenu() ?? NSMenu() },
            dragDidEnd: { [weak self] in self?.saveDraggedPosition() },
            isCompact: { [weak store] in store?.mode == .compact },
            activateCompactTarget: { [weak store] in store?.activate($0) }
        )
        panel.contentView = contentView
        refreshHostedContent = { [weak contentView] in contentView?.refreshHostedContent() }
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.title = "算力环"

        modeObserver = store.$mode
            .dropFirst()
            .sink { [weak self] mode in
                guard let self else { return }
                self.resize(for: mode)
                if mode == .balance { self.refreshBalancesIfStale() }
            }
        countdownObserver = store.$showsResetCountdown.dropFirst().sink { [weak self] visible in
            guard let self else { return }
            // Published emits before the store changes. Preserve the compact top edge even
            // when a countdown appears or disappears while the detail page is open.
            if self.store.mode != .compact, let origin = self.compactOrigin {
                let oldHeight = self.panelSize(for: .compact).height
                let newHeight = self.panelSize(for: .compact, showsCountdown: visible).height
                self.compactOrigin = CGPoint(x: origin.x, y: origin.y + oldHeight - newHeight)
            }
            self.resize(for: self.store.mode, showsCountdown: visible)
        }
        pricingRowObserver = store.$showsPricingRow
            .dropFirst()
            .sink { [weak self] visible in
                guard let self else { return }
                // Keep the compact top edge stable, mirroring the countdown row.
                if self.store.mode != .compact, let origin = self.compactOrigin {
                    let oldHeight = self.panelSize(for: .compact).height
                    let newHeight = self.panelSize(for: .compact, showsPricing: visible).height
                    self.compactOrigin = CGPoint(x: origin.x, y: origin.y + oldHeight - newHeight)
                }
                self.resize(for: self.store.mode, showsPricing: visible)
            }
        panel.collapse = { [weak store] in store?.setCompactMode() }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "gauge.with.dots.needle.50percent", accessibilityDescription: "算力环")
        item.button?.target = self
        item.button?.action = #selector(toggleVisibility)
        statusItem = item
        showInitialPanel()
    }

    private func saveDraggedPosition() {
        let compactSize = panelSize(for: .compact)
        let origin: CGPoint
        if store.mode == .compact {
            origin = panel.frame.origin
        } else {
            origin = CGPoint(
                x: panel.frame.minX,
                y: panel.frame.maxY - compactSize.height
            )
        }
        compactOrigin = origin
        UserDefaults.standard.set(origin.x, forKey: PositionKeys.x)
        UserDefaults.standard.set(origin.y, forKey: PositionKeys.y)
    }

    private func showInitialPanel() {
        let size = panelSize(for: .compact)
        let frame: CGRect
        if UserDefaults.standard.object(forKey: PositionKeys.x) != nil,
           UserDefaults.standard.object(forKey: PositionKeys.y) != nil {
            frame = CGRect(
                x: UserDefaults.standard.double(forKey: PositionKeys.x),
                y: UserDefaults.standard.double(forKey: PositionKeys.y),
                width: size.width,
                height: size.height
            )
        } else if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            frame = CGRect(
                x: visible.maxX - size.width - 20,
                y: visible.maxY - size.height - 20,
                width: size.width,
                height: size.height
            )
        } else {
            frame = CGRect(origin: .zero, size: size)
        }
        setFrameKeepingVisible(frame)
        compactOrigin = panel.frame.origin
        panel.orderFrontRegardless()
    }

    /// Opening the balance page should show fresh numbers, but repeated mode
    /// switches must not hammer the sources.
    private func refreshBalancesIfStale() {
        guard !store.isRefreshingBalances else { return }
        if let last = store.lastBalanceUpdate, Date().timeIntervalSince(last) < 60 { return }
        refreshBalances()
    }

    private func resize(for mode: EnergyPanelMode, showsCountdown: Bool? = nil, showsPricing: Bool? = nil) {
        let size = panelSize(for: mode, showsCountdown: showsCountdown, showsPricing: showsPricing)
        let current = panel.frame
        if mode != .compact, displayedMode == .compact {
            compactOrigin = current.origin
        }
        let targetOrigin: CGPoint
        if mode == .compact, displayedMode != .compact, let compactOrigin {
            targetOrigin = compactOrigin
        } else {
            targetOrigin = CGPoint(x: current.minX, y: current.maxY - size.height)
        }
        let proposed = CGRect(origin: targetOrigin, size: size)
        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame ?? proposed
        let target = PanelFrameLayout.clamped(proposed, to: visible)

        displayedMode = mode
        guard current.size != target.size || current.origin != target.origin else { return }
        if mode == .compact {
            compactOrigin = target.origin
        }
        if suppressAnimations || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.setFrame(target, display: true)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.8, 0.2, 1)
                panel.animator().setFrame(target, display: true)
            } completionHandler: { [weak self] in self?.panel.invalidateShadow() }
        }
        panel.orderFrontRegardless()
        if mode != .compact { panel.makeKey() }
    }

    private func setFrameKeepingVisible(_ proposed: CGRect) {
        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame ?? proposed
        panel.setFrame(PanelFrameLayout.clamped(proposed, to: visible), display: true)
    }

    private func panelSize(for mode: EnergyPanelMode, showsCountdown: Bool? = nil, showsPricing: Bool? = nil) -> CGSize {
        EnergyPanelLayout.size(
            for: mode,
            showsCountdown: showsCountdown ?? store.showsResetCountdown,
            showsPricing: showsPricing ?? store.showsPricingRow
        )
    }

    func control(_ request: EnergyCLIRequest) -> [String: Any] {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        return withTransaction(transaction) { applyControl(request) }
    }

    private func applyControl(_ request: EnergyCLIRequest) -> [String: Any] {
        suppressAnimations = true
        defer { suppressAnimations = false }
        switch request.command {
        case "status": break
        case "show":
            guard let mode = EnergyPanelMode(rawValue: request.value ?? "") else {
                return ["ok": false, "error": "无效页面"]
            }
            store.setMode(mode)
            panel.orderFrontRegardless()
            if mode != .compact { panel.makeKey() }
        case "hide": panel.orderOut(nil)
        case "size":
            guard let size = CompactPanelSize(rawValue: request.value ?? "") else {
                return ["ok": false, "error": "无效尺寸"]
            }
            size.save()
            resize(for: store.mode)
            saveDraggedPosition()
        case "move":
            guard let x = request.x, let y = request.y else { return ["ok": false, "error": "缺少坐标"] }
            setFrameKeepingVisible(CGRect(origin: CGPoint(x: x, y: y), size: panel.frame.size))
            saveDraggedPosition()
        case "refresh": refreshData()
        case "snapshot":
            break
        default: return ["ok": false, "error": "未知命令"]
        }
        if request.command != "status" {
            refreshHostedContent?()
            NSApp.updateWindows()
            panel.displayIfNeeded()
            CATransaction.flush()
        }
        if request.command == "snapshot" {
            panel.contentView?.layoutSubtreeIfNeeded()
            panel.displayIfNeeded()
            snapshotPath = renderPanelSnapshot()
        }
        let frame = panel.frame
        let now = Date()
        let quota: [[String: Any]] = store.quotaLimits.map { reading in
            var item: [String: Any] = ["title": reading.title]
            item["remainingPercent"] = reading.remainingPercent.map { $0 as Any } ?? NSNull()
            return item
        }
        let balances: [[String: Any]] = store.allBalanceReadings.map { reading in
            var item: [String: Any] = ["id": reading.id, "title": reading.title]
            // `hidden` means "left out of the compact Mini bar right now", not
            // "unavailable everywhere": the balance page still lists it.
            item["hidden"] = store.hiddenBalanceIDs.contains(reading.id)
            switch reading.state {
            case .ok:
                item["state"] = "ok"
                item["value"] = [reading.unitPrefix, reading.valueText, reading.unitSuffix].compactMap { $0 }.joined()
                item["caption"] = reading.caption ?? ""
                item["detail"] = reading.detail ?? ""
            case .loading:
                item["state"] = "loading"
            case .unconfigured(let message):
                item["state"] = "unconfigured"
                item["message"] = message
            case .failed(let message):
                item["state"] = "failed"
                item["message"] = message
            case .stale(let message):
                item["state"] = "stale"
                item["value"] = [reading.unitPrefix, reading.valueText, reading.unitSuffix].compactMap { $0 }.joined()
                item["message"] = message
            }
            item["lastSuccessAt"] = reading.updatedAt.map { $0.timeIntervalSince1970 as Any } ?? NSNull()
            item["lastAttemptAt"] = reading.lastAttemptAt.map { $0.timeIntervalSince1970 as Any } ?? NSNull()
            return item
        }
        let radar: [String: Any] = [
            "summary": store.radarSnapshot?.compactText(now: now) ?? "暂无数据",
            "fresh": store.radarSnapshot?.primaryIsFresh(now: now) ?? false,
            "probabilityFresh": store.radarSnapshot?.forecastIsFresh(now: now) ?? false,
            "probabilityTitle": store.radarSnapshot?.probabilityTitle(now: now) ?? "unknown",
            "probability": store.radarSnapshot?.probability(now: now).map { $0 as Any } ?? NSNull(),
            "probabilitySource": store.radarSnapshot?.probabilitySourceName(now: now) ?? "unknown",
            "officialConfirmed": false,
            "sourceAnnouncement": store.radarSnapshot?.countdownTarget(now: now) != nil,
            "averaged": store.radarSnapshot?.isAveraged(now: now) ?? false,
            // The source's committed-window signal is its displayed headline;
            // the 24h/48h cadence values remain separately attributed.
            "commitmentProbability": store.radarSnapshot?.commitmentProbability(now: now).map { $0 as Any } ?? NSNull(),
            "commitmentWindow": store.radarSnapshot?.commitmentWindowDescription(now: now).map { $0 as Any } ?? NSNull(),
            "codexResetsProbability": store.radarSnapshot?.announcementProbability(now: now).map { $0 as Any } ?? NSNull(),
            "codexResetProbability": store.radarSnapshot?.referenceProbability(now: now).map { $0 as Any } ?? NSNull(),
            "codexResetPace48h": store.radarSnapshot?.referenceProbability48h(now: now).map { $0 as Any } ?? NSNull(),
            "codexResetsURL": ResetRadarSources.primaryURL.absoluteString,
            "codexResetURL": ResetReferenceForecast.pageURL.absoluteString,
            "errors": store.radarSnapshot?.errors ?? []
        ]
        let versionInfo = AppVersionInfo.current
        var result: [String: Any] = [
            "ok": true, "schemaVersion": 1,
            "build": versionInfo.isPackaged ? versionInfo.buildNumber : "development",
            "version": versionInfo.shortVersion,
            "buildDate": versionInfo.buildDateText.map { $0 as Any } ?? NSNull(),
            "mode": store.mode.rawValue, "selectedAccount": store.selectedAccountID, "visible": panel.isVisible,
            "sizeLevel": CompactPanelSize.load().rawValue,
            "autoHideInactiveAccounts": store.autoHideInactiveAccounts,
            "frame": ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height],
            "coordinateSystem": "macOS screen points, primary screen bottom-left origin",
            "countdownRowVisible": store.showsResetCountdown,
            "refreshing": store.currentPageIsRefreshing,
            "radar": radar,
            "quota": quota,
            "balances": balances,
            "advice": [
                "headline": store.balanceAdvice.headline,
                "detail": store.balanceAdvice.detail,
                "compact": store.balanceAdvice.compactText,
                "recommended": store.balanceAdvice.recommendedID.map { $0 as Any } ?? NSNull(),
                "levels": store.balanceAdvice.levels.mapValues { $0.title },
            ]
        ]
        if request.command == "refresh" { result["refreshRequested"] = true }
        if let snapshotPath { result["snapshot"] = snapshotPath }
        return result
    }

    private func renderPanelSnapshot() -> String? {
        guard let view = panel.contentView else { return nil }
        guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: representation)
        guard let data = representation.representation(using: .png, properties: [:]) else { return nil }
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexPetEnergy", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("panel-snapshot.png")
        do {
            try data.write(to: url)
            return url.path
        } catch {
            return nil
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let quotaItem = item("打开账户页", action: #selector(showQuota))
        quotaItem.isEnabled = store.mode != .quota
        menu.addItem(quotaItem)
        let balanceItem = item("打开总览页", action: #selector(showBalance))
        balanceItem.isEnabled = store.mode != .balance
        menu.addItem(balanceItem)
        let projectsItem = item("打开今日用量", action: #selector(showProjects))
        projectsItem.isEnabled = store.mode != .projects
        menu.addItem(projectsItem)
        let radarItem = item("打开重置雷达", action: #selector(showRadar))
        radarItem.isEnabled = store.mode != .radar
        menu.addItem(radarItem)
        let pricingItem = item("打开省钱灯", action: #selector(showPricing))
        pricingItem.isEnabled = store.mode != .pricing
        menu.addItem(pricingItem)
        menu.addItem(.separator())
        let refreshItem = item(store.currentPageIsRefreshing ? "正在刷新…" : "刷新当前页", action: #selector(refresh))
        refreshItem.isEnabled = !store.currentPageIsRefreshing
        menu.addItem(refreshItem)

        menu.addItem(.separator())
        for size in CompactPanelSize.allCases {
            let sizeItem = item("大小：\(size.title)", action: #selector(changeSize(_:)))
            sizeItem.representedObject = size.rawValue
            sizeItem.state = size == CompactPanelSize.load() ? .on : .off
            menu.addItem(sizeItem)
        }
        menu.addItem(.separator())
        let autoHideItem = item("自动隐藏未打开应用的账户", action: #selector(toggleAutoHide))
        autoHideItem.state = store.autoHideInactiveAccounts ? .on : .off
        autoHideItem.toolTip = "豆包、WorkBuddy、千问办公客户端未运行时，Mini 条不再为它们占位；总览页仍显示全部账户。"
        menu.addItem(autoHideItem)
        let pricingRowItem = item("在 Mini 条显示省钱灯", action: #selector(togglePricingRow))
        pricingRowItem.state = store.showsPricingRow ? .on : .off
        pricingRowItem.toolTip = "显示当前最省的模型、DeepSeek 谷时/峰时状态；点这一行查看完整折扣与下次变价。"
        menu.addItem(pricingRowItem)
        menu.addItem(item("打开余额配置文件", action: #selector(openBalanceConfig)))
        menu.addItem(item("隐藏浮窗（点击菜单栏图标找回）", action: #selector(hidePanel)))
        menu.addItem(item("恢复默认位置", action: #selector(resetPosition)))
        menu.addItem(item("关于 算力环", action: #selector(showAbout)))
        menu.addItem(.separator())
        menu.addItem(item("退出算力环", action: #selector(quit)))
        return menu
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func showMore() {
        guard let view = panel.contentView else { return }
        makeMenu().popUp(positioning: nil, at: CGPoint(x: view.bounds.maxX - 60, y: view.bounds.maxY - 42), in: view)
    }

    @objc private func openBalanceConfig() {
        guard let url = BalanceConfig.prepareTemplateFile() else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func hidePanel() { panel.orderOut(nil) }
    @objc private func toggleVisibility() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
            if store.mode != .compact { panel.makeKey() }
            if store.mode == .balance { refreshBalancesIfStale() }
        }
    }

    @objc private func showRadar() { store.setMode(.radar) }
    @objc private func showBalance() { store.setMode(.balance) }
    @objc private func showQuota() { store.setMode(.quota) }
    @objc private func showProjects() { store.setMode(.projects) }
    @objc private func showPricing() { store.setMode(.pricing) }
    @objc private func refresh() { refreshData() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func showAbout() {
        let version = AppVersionInfo.current
        let alert = NSAlert(); alert.messageText = "算力环"
        alert.informativeText = "\(version.aboutText)\n显示账户实际额度与上海时区当天的本地 Token。\n唯一安装位置：~/Applications/算力环.app\n更新日志：仓库根目录 CHANGELOG.md"
        alert.addButton(withTitle: "好"); alert.runModal()
    }

    @objc private func changeSize(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let size = CompactPanelSize(rawValue: rawValue)
        else { return }
        size.save()
        resize(for: store.mode)
    }

    @objc private func toggleAutoHide() {
        store.setAutoHideInactiveAccounts(!store.autoHideInactiveAccounts)
        refreshHostedContent?()
    }

    @objc private func togglePricingRow() {
        store.setShowsPricingRow(!store.showsPricingRow)
        refreshHostedContent?()
    }

    @objc private func resetPosition() {
        UserDefaults.standard.removeObject(forKey: PositionKeys.x)
        UserDefaults.standard.removeObject(forKey: PositionKeys.y)
        let size = panelSize(for: store.mode)
        guard let visible = (panel.screen ?? NSScreen.main)?.visibleFrame else { return }
        let frame = CGRect(x: visible.maxX - size.width - 20, y: visible.maxY - size.height - 20,
                           width: size.width, height: size.height)
        setFrameKeepingVisible(frame)
        saveDraggedPosition()
        panel.orderFrontRegardless()
    }
}
