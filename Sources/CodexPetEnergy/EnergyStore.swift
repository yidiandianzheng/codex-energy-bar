import Combine
import Foundation

@MainActor
final class EnergyStore: ObservableObject {
    @Published private(set) var quotas = AccountQuotaReadings.unavailable
    @Published private(set) var quotaLimits: [QuotaLimitReading] = []
    @Published private(set) var resetCredits: RateLimitResetCreditsSummary?
    @Published private(set) var projects: [ProjectUsageReading] = []
    @Published private(set) var hasLoadedProjects = false
    @Published private(set) var mode: EnergyPanelMode = .compact
    @Published private(set) var lastQuotaUpdate: Date?
    @Published private(set) var lastProjectUpdate: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isRefreshingProjects = false
    @Published private(set) var quotaRefreshError: String?
    @Published private(set) var projectRefreshError: String?

    @Published private(set) var radarSnapshot: ResetRadarSnapshot?
    @Published private(set) var isRefreshingRadar = false
    @Published private(set) var showsResetCountdown = false
    private var countdownVisibilityTimer: AnyCancellable?
    func beginRadarRefresh() { isRefreshingRadar = true }
    func applyRadar(_ snapshot: ResetRadarSnapshot) {
        radarSnapshot = snapshot
        isRefreshingRadar = false
        updateCountdownVisibility()
        if showsResetCountdown, countdownVisibilityTimer == nil {
            countdownVisibilityTimer = Timer.publish(every: 1, on: .main, in: .common)
                .autoconnect().sink { [weak self] now in self?.updateCountdownVisibility(now: now) }
        }
    }

    func updateCountdownVisibility(now: Date = .now) {
        let visible = radarSnapshot?.countdownTarget(now: now) != nil
        if showsResetCountdown != visible { showsResetCountdown = visible }
        if !visible { countdownVisibilityTimer = nil }
    }
    var currentPageIsRefreshing: Bool {
        switch mode {
        case .radar: isRefreshingRadar
        case .projects: isRefreshingProjects
        default: isRefreshing
        }
    }

    func apply(_ result: RateLimitReadResult) {
        let readings = EnergyLogic.accountReadings(from: result)
        let limits = EnergyLogic.quotaLimits(from: result)
        if quotas != readings { quotas = readings }
        if quotaLimits != limits { quotaLimits = limits }
        if resetCredits != result.rateLimitResetCredits { resetCredits = result.rateLimitResetCredits }
        lastQuotaUpdate = .now
        isRefreshing = false
        quotaRefreshError = limits.isEmpty ? "账户暂未返回可用额度" : nil
    }

    func markUnavailable() {
        isRefreshing = false
        quotaRefreshError = lastQuotaUpdate == nil
            ? "无法读取额度，请检查 Codex 登录状态后重试"
            : "同步失败，显示上次读数"
    }

    func beginRefresh() { isRefreshing = true; quotaRefreshError = nil }
    func beginProjectRefresh() { isRefreshingProjects = true; projectRefreshError = nil }
    func markProjectsUnavailable() {
        isRefreshingProjects = false
        projectRefreshError = "无法读取部分本地日志，请检查目录访问权限后重试"
    }

    func applyProjects(_ summary: ProjectUsageDaySummary) {
        if !hasLoadedProjects { hasLoadedProjects = true }
        if projects != summary.projects { projects = summary.projects }
        lastProjectUpdate = .now
        isRefreshingProjects = false
        projectRefreshError = nil
    }

    func setMode(_ mode: EnergyPanelMode) {
        if self.mode != mode { self.mode = mode }
    }
    func setCompactMode() { setMode(.compact) }

    var projectSummary: ProjectUsageDaySummary {
        ProjectUsageDaySummary(projects: projects, sessionSwitchCount: 0)
    }
}
