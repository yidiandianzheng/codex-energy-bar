import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = EnergyStore()
    private let rateLimitClient = CodexRateLimitClient()
    private let projectUsageMonitor = ProjectUsageMonitor()
    private let radarClient = ResetRadarClient()
    private let leaderboardClient = ModelLeaderboardClient()
    private let balanceMonitor = BalanceMonitor()
    private let clientMonitor = ClientRunningMonitor()
    private var panelController: EnergyPanelController?
    private let controlServer = LocalControlServer()
    private var hasClientSnapshot = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Publish the client-state snapshot before the panel first renders, so a
        // closed 豆包/WorkBuddy/千问办公/Qoder CN/Trae CN never flashes in the
        // compact bar.
        clientMonitor.onChange = { [weak self] accounts in
            guard let self else { return }
            let previous = self.store.runningClientIDs
            self.store.applyRunningClients(accounts)
            // Opening a client should refresh its figures now instead of waiting
            // for the five-minute balance tick. The launch snapshot is skipped
            // because the initial refresh is already scheduled.
            let opened = accounts.subtracting(previous)
            if self.hasClientSnapshot, !opened.isEmpty {
                self.balanceMonitor.refresh(providers: Set(opened.compactMap(BalanceProvider.init(rawValue:))))
            }
            // 千问办公's local MCP socket becomes available several seconds
            // after the launch notification (the client's adaptor starts after
            // app-ready). The first fetch retries for 12 s; this one delayed
            // safety net covers a very slow cold start without polling forever.
            if self.hasClientSnapshot, opened.contains(BalanceProvider.qwenwork.id) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
                    self?.balanceMonitor.refresh(providers: [.qwenwork])
                }
            }
            self.hasClientSnapshot = true
        }
        clientMonitor.start()

        panelController = EnergyPanelController(
            store: store,
            refreshBalances: { [weak self] in
                guard let self else { return }
                self.store.beginBalanceRefresh()
                self.balanceMonitor.refresh()
            },
            refreshData: { [weak self] in
                guard let self else { return }
                let request = self.store.refreshRequest
                if request.radar { self.radarClient.refresh() }
                if request.leaderboard { self.leaderboardClient.refresh() }
                if request.projects {
                    self.store.beginProjectRefresh()
                    self.projectUsageMonitor.refresh(force: true)
                }
                if request.codex {
                    self.store.beginRefresh()
                    self.rateLimitClient.refresh()
                }
                if !request.balances.isEmpty { self.balanceMonitor.refresh(providers: request.balances) }
            }
        )

        radarClient.onLoading = { [weak self] in self?.store.beginRadarRefresh() }
        radarClient.onUpdate = { [weak self] in self?.store.applyRadar($0) }
        radarClient.start()
        leaderboardClient.onLoading = { [weak self] in self?.store.beginLeaderboardRefresh() }
        leaderboardClient.onModels = { [weak self] models, supplement in self?.store.applyLeaderboard(models, supplement: supplement) }
        leaderboardClient.onError = { [weak self] _ in self?.store.markLeaderboardUnavailable() }
        leaderboardClient.start()
        rateLimitClient.onSnapshot = { [weak self] result in
            self?.store.apply(result)
        }
        rateLimitClient.onUnavailable = { [weak self] in
            self?.store.markUnavailable()
        }
        projectUsageMonitor.onUpdate = { [weak self] summary in
            self?.store.applyProjects(summary)
        }
        projectUsageMonitor.onFailure = { [weak self] in self?.store.markProjectsUnavailable() }
        balanceMonitor.onRefreshing = { [weak self] ids in self?.store.setRefreshingBalances(ids) }
        balanceMonitor.onReading = { [weak self] reading in self?.store.applyBalance(reading) }
        balanceMonitor.onFinished = { [weak self] in self?.store.finishBalanceRefresh() }
        store.beginRefresh()
        store.beginProjectRefresh()
        store.beginBalanceRefresh()
        rateLimitClient.start()
        projectUsageMonitor.start()
        balanceMonitor.start()
        do {
            try controlServer.start { [weak self] request in
                self?.panelController?.control(request) ?? ["ok": false, "error": "窗口未就绪"]
            }
        } catch { NSLog("本地 CLI 启动失败：%@", String(describing: error)) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stopNightWatch()
        radarClient.stop()
        leaderboardClient.stop()
        balanceMonitor.stop()
        clientMonitor.stop()
        controlServer.stop()
        rateLimitClient.stop()
        projectUsageMonitor.stop()
    }
}

if CommandLine.arguments.dropFirst().first == "--cli" {
    exit(EnergyCLI.run(Array(CommandLine.arguments.dropFirst(2))))
} else if CommandLine.arguments.contains("--self-test") {
    MainActor.assumeIsolated {
        exit(SelfTest.run() ? EXIT_SUCCESS : EXIT_FAILURE)
    }
} else {
    MainActor.assumeIsolated {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
