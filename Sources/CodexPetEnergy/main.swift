import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = EnergyStore()
    private let rateLimitClient = CodexRateLimitClient()
    private let projectUsageMonitor = ProjectUsageMonitor()
    private let radarClient = ResetRadarClient()
    private var panelController: EnergyPanelController?
    private let controlServer = LocalControlServer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panelController = EnergyPanelController(
            store: store,
            refreshData: { [weak self] in
                guard let self else { return }
                if self.store.mode == .radar {
                    self.radarClient.refresh()
                } else if self.store.mode == .projects {
                    self.store.beginProjectRefresh()
                    self.projectUsageMonitor.refresh(force: true)
                } else {
                    self.store.beginRefresh()
                    self.rateLimitClient.refresh()
                }
            }
        )

        radarClient.onLoading = { [weak self] in self?.store.beginRadarRefresh() }
        radarClient.onUpdate = { [weak self] in self?.store.applyRadar($0) }
        radarClient.start()
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
        store.beginRefresh()
        store.beginProjectRefresh()
        rateLimitClient.start()
        projectUsageMonitor.start()
        do {
            try controlServer.start { [weak self] request in
                self?.panelController?.control(request) ?? ["ok": false, "error": "窗口未就绪"]
            }
        } catch { NSLog("本地 CLI 启动失败：%@", String(describing: error)) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        radarClient.stop()
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
