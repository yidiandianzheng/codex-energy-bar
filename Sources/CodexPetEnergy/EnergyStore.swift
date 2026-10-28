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
    /// Account shown on the 账户 page; the 总览 table switches it before jumping in.
    @Published private(set) var selectedAccountID: String
    @Published private(set) var lastQuotaUpdate: Date?
    @Published private(set) var lastProjectUpdate: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isRefreshingProjects = false
    @Published private(set) var quotaRefreshError: String?
    @Published private(set) var projectRefreshError: String?

    @Published private(set) var balances: [BalanceReading] = BalanceProvider.allCases.map { $0.placeholder() }
    @Published private(set) var isRefreshingBalances = false
    @Published private(set) var balanceRefreshError: String?
    @Published private(set) var lastBalanceUpdate: Date?
    @Published private(set) var hasLoadedBalances = false

    /// 今日用量（本机差值累计，见 DailyUsage.swift）。
    @Published private(set) var todayUsage = TodayUsageSnapshot.empty
    private var dailyUsageLedger: DailyUsageLedger
    private let defaults: UserDefaults
    @Published private(set) var clockNow: Date
    @Published private(set) var refreshingBalanceIDs: Set<String> = []
    private var clockTimer: AnyCancellable?
    private var lastQuotaAttempt: Date?
    private let startsTimers: Bool

    /// Accounts whose desktop client is currently open (豆包 / WorkBuddy /
    /// 千问办公 / Qoder CN / Trae CN).
    @Published private(set) var runningClientIDs: Set<String> = []
    /// Whether the compact bar hides accounts that are not in use. Persisted in
    /// UserDefaults; the balance page always keeps the full list.
    @Published private(set) var autoHideInactiveAccounts: Bool
    /// Account ids removed from the compact bar by the current policy.
    @Published private(set) var hiddenBalanceIDs: Set<String> = []

    /// 夜间 AI 通宵模式：系统保持唤醒、显示器可关闭。状态由 NightWatchController 回调同步。
    @Published private(set) var isNightWatchActive = false
    @Published private(set) var nightWatchStartedAt: Date?
    /// 因低电量自动关闭后的提示文案，保留十分钟。
    @Published private(set) var nightWatchNoticeText: String?
    private var nightWatchNoticeUntil: Date?
    private var lastNightWatchAutoStop: Date?
    private let nightWatch: NightWatchController

    @Published private(set) var radarSnapshot: ResetRadarSnapshot?
    @Published private(set) var isRefreshingRadar = false
    @Published private(set) var showsResetCountdown = false
    /// 模型榜（OpenRouter 全量 + 四榜计算；抓取失败保留缓存快照）。
    @Published private(set) var leaderboardSnapshot: LeaderboardSnapshot?
    @Published private(set) var isRefreshingLeaderboard = false
    @Published private(set) var leaderboardError: String?
    /// Local price snapshot; recomputed from the built-in catalog on every clock tick.
    @Published private(set) var pricingSnapshot: PricingSnapshot
    /// Whether the compact bar keeps the cost-light row. Missing preference means on.
    @Published private(set) var showsPricingRow: Bool
    static let pricingRowDefaultsKey = "energy-pricing-row-enabled"
    private var countdownVisibilityTimer: AnyCancellable?
    func beginRadarRefresh() { isRefreshingRadar = true }
    func applyRadar(_ snapshot: ResetRadarSnapshot) {
        radarSnapshot = snapshot
        isRefreshingRadar = false
        updateCountdownVisibility()
        if startsTimers, showsResetCountdown, countdownVisibilityTimer == nil {
            countdownVisibilityTimer = Timer.publish(every: 1, on: .main, in: .common)
                .autoconnect().sink { [weak self] now in self?.updateCountdownVisibility(now: now) }
        }
    }

    func updateCountdownVisibility(now: Date = .now) {
        let visible = radarSnapshot?.countdownTarget(now: now) != nil
        if showsResetCountdown != visible { showsResetCountdown = visible }
        if !visible { countdownVisibilityTimer = nil }
    }

    // MARK: 模型榜（Leaderboard）

    /// 启动时读缓存：离线首启也有上一份好数据。
    func loadLeaderboardCache() {
        if let cached = ModelLeaderboardCache().load() {
            leaderboardSnapshot = cached
        }
    }

    func beginLeaderboardRefresh() {
        isRefreshingLeaderboard = true
        leaderboardError = nil
    }

    /// 抓取成功：引擎排序 → 发布 → 落缓存。空数组视为失败。
    /// supplement 为 nil 时引擎回退静态能力表（降级不中断）。
    func applyLeaderboard(_ models: [OpenRouterModel], supplement: LeaderboardSupplement?, now: Date = .now) {
        guard !models.isEmpty else {
            markLeaderboardUnavailable()
            return
        }
        let snapshot = ModelLeaderboardEngine.rank(models: models, supplement: supplement, now: now)
        leaderboardSnapshot = snapshot
        isRefreshingLeaderboard = false
        leaderboardError = nil
        ModelLeaderboardCache().save(snapshot)
    }

    /// 抓取失败：保留旧快照，仅提示；从无数据时显示可重试的错误。
    func markLeaderboardUnavailable() {
        isRefreshingLeaderboard = false
        leaderboardError = leaderboardSnapshot == nil ? "榜单暂不可用，请稍后重试" : "网络波动，显示上次数据"
    }
    var currentPageIsRefreshing: Bool {
        switch mode {
        case .radar: isRefreshingRadar
        case .leaderboard: isRefreshingLeaderboard
        case .projects: isRefreshingProjects || isRefreshingBalances
        case .balance, .compact: isRefreshingBalances || isRefreshing
        case .quota: selectedAccountID == BalanceReading.codexID ? isRefreshing : refreshingBalanceIDs.contains(selectedAccountID)
        case .pricing: false
        }
    }
    var currentPageLastUpdated: Date? {
        switch mode {
        case .radar: radarSnapshot?.checkedAt
        case .leaderboard: leaderboardSnapshot?.checkedAt
        case .projects: lastProjectUpdate
        case .quota: allBalanceReadings.first { $0.id == selectedAccountID }?.updatedAt
        case .balance, .compact: allBalanceReadings.compactMap(\.updatedAt).min()
        case .pricing: pricingSnapshot.checkedAt
        }
    }
    var currentPageError: String? {
        switch mode {
        case .radar: return radarSnapshot?.errors.first
        case .leaderboard: return leaderboardError
        case .projects: return projectRefreshError
        case .quota: return allBalanceReadings.first { $0.id == selectedAccountID }?.stateMessage
        case .balance, .compact:
            let count = allBalanceReadings.filter { if case .stale = $0.state { return true }; if case .failed = $0.state { return true }; return false }.count
            return count == 0 ? nil : "\(count) 个来源需要处理，详情见对应账户"
        case .pricing: return nil
        }
    }
    var refreshRequest: EnergyRefreshRequest { EnergyRefreshRequest.forPage(mode, accountID: selectedAccountID) }

    func beginBalanceRefresh(providers: Set<BalanceProvider>? = nil) {
        refreshingBalanceIDs.formUnion((providers ?? Set(BalanceProvider.allCases)).map(\.id))
        isRefreshingBalances = !refreshingBalanceIDs.isEmpty
    }
    func setRefreshingBalances(_ ids: Set<String>) {
        refreshingBalanceIDs = ids
        isRefreshingBalances = !ids.isEmpty
    }

    func applyBalance(_ reading: BalanceReading) {
        if let index = balances.firstIndex(where: { $0.id == reading.id }) {
            balances[index] = reading.retainingLastSuccess(balances[index])
        } else {
            balances.append(reading)
        }
        balances.sort { lhs, rhs in
            let left = BalanceProvider(rawValue: lhs.id).flatMap { BalanceProvider.allCases.firstIndex(of: $0) } ?? Int.max
            let right = BalanceProvider(rawValue: rhs.id).flatMap { BalanceProvider.allCases.firstIndex(of: $0) } ?? Int.max
            return left < right
        }
        hasLoadedBalances = true
        updateHiddenBalances()
        recordDailyUsage(reading)
    }

    /// 用本机相邻两次读数累计今日用量；跨天清零。服务端没有自然日用量，
    /// 这里只做"本机可见的今日消耗"，并在页面上说明口径。
    private func recordDailyUsage(_ reading: BalanceReading) {
        let now = startsTimers ? Date.now : clockNow
        dailyUsageLedger.record(reading, now: now)
        DailyUsageStore.save(dailyUsageLedger, defaults: defaults)
        publishTodayUsage()
    }
    private func rollDailyUsageIfNeeded(now: Date) {
        dailyUsageLedger.roll(to: now)
        DailyUsageStore.save(dailyUsageLedger, defaults: defaults)
    }
    private func publishTodayUsage() {
        let visibleIDs = Set(allBalanceReadings.filter {
            $0.isFresh(at: clockNow) && $0.sourceIdentity != nil && $0.sourceIdentity == dailyUsageLedger.identities[$0.id]
        }.map(\.id))
        todayUsage = TodayUsageSnapshot(
            codexTokens: hasLoadedProjects ? projectSummary.allProjectTotals.totalTokens : nil,
            moneySpent: dailyUsageLedger.moneySpent.filter { visibleIDs.contains($0.key) },
            pointsSpent: dailyUsageLedger.pointsSpent.filter { visibleIDs.contains($0.key) },
            currencyPrefixes: dailyUsageLedger.currencies.mapValues { $0 == "CNY" ? "¥" : $0 + " " },
            coverageStart: dailyUsageLedger.coverageStart
        )
    }
    /// Time changes invalidate stale data and daily totals even when every source fails.
    func tick(now: Date) {
        let crossedDay = DailyUsageStore.dayKey(clockNow) != DailyUsageStore.dayKey(now)
        clockNow = now
        if isNightWatchActive { nightWatch.checkBattery(now: now) }
        updateNightWatchNotice()
        pricingSnapshot = PricingEngine.snapshot(at: now, catalog: .builtIn)
        rollDailyUsageIfNeeded(now: now)
        if crossedDay {
            projects = []
            hasLoadedProjects = false
            lastProjectUpdate = nil
        }
        publishTodayUsage()
        updateCountdownVisibility(now: now)
    }

    /// Called by `ClientRunningMonitor` on the main queue whenever 豆包、
    /// WorkBuddy、千问办公、Qoder CN or Trae CN is opened/quit.
    func applyRunningClients(_ ids: Set<String>) {
        guard runningClientIDs != ids else { return }
        for id in runningClientIDs.subtracting(ids) { dailyUsageLedger.breakContinuity(for: id) }
        runningClientIDs = ids
        updateHiddenBalances()
    }

    func setShowsPricingRow(_ enabled: Bool) {
        guard showsPricingRow != enabled else { return }
        showsPricingRow = enabled
        defaults.set(enabled, forKey: Self.pricingRowDefaultsKey)
    }

    func setAutoHideInactiveAccounts(_ enabled: Bool) {
        guard autoHideInactiveAccounts != enabled else { return }
        autoHideInactiveAccounts = enabled
        defaults.set(enabled, forKey: AccountVisibility.autoHideDefaultsKey)
        updateHiddenBalances()
    }

    func toggleNightWatch() {
        nightWatch.toggle()
    }

    func stopNightWatch() {
        nightWatch.stop()
    }

    var nightWatchElapsedText: String? {
        guard let startedAt = nightWatchStartedAt else { return nil }
        let minutes = max(0, Int(clockNow.timeIntervalSince(startedAt)) / 60)
        guard minutes > 0 else { return "已开启" }
        guard minutes >= 60 else { return "已开启 \(minutes) 分钟" }
        let hours = minutes / 60
        let remaining = minutes % 60
        return remaining == 0 ? "已开启 \(hours) 小时" : "已开启 \(hours) 小时 \(remaining) 分"
    }

    var nightWatchAutoStoppedAt: Date? { nightWatch.autoStoppedAt }
    var nightWatchAutoStopPercent: Int? { nightWatch.autoStopPercent }

    private func syncNightWatch() {
        if isNightWatchActive != nightWatch.isActive { isNightWatchActive = nightWatch.isActive }
        if nightWatchStartedAt != nightWatch.startedAt { nightWatchStartedAt = nightWatch.startedAt }
        if lastNightWatchAutoStop != nightWatch.autoStoppedAt {
            lastNightWatchAutoStop = nightWatch.autoStoppedAt
            nightWatchNoticeUntil = nightWatch.autoStoppedAt?.addingTimeInterval(10 * 60)
        }
        updateNightWatchNotice()
    }

    private func updateNightWatchNotice() {
        let notice: String?
        if !isNightWatchActive, let until = nightWatchNoticeUntil, until > clockNow,
           let percent = nightWatch.autoStopPercent {
            notice = "电量 \(percent)%，已自动关闭"
        } else {
            notice = nil
        }
        if nightWatchNoticeText != notice { nightWatchNoticeText = notice }
    }

    private func updateHiddenBalances() {
        let hidden = AccountVisibility.hiddenIDs(
            readings: allBalanceReadings,
            runningClients: runningClientIDs,
            autoHide: autoHideInactiveAccounts
        )
        if hidden != hiddenBalanceIDs { hiddenBalanceIDs = hidden }
    }

    func finishBalanceRefresh() {
        refreshingBalanceIDs = []
        isRefreshingBalances = false
        hasLoadedBalances = true
        lastBalanceUpdate = balances.compactMap(\.updatedAt).min()
        let failures = balances.filter { if case .failed = $0.state { return true }; return false }
        balanceRefreshError = failures.isEmpty ? nil : "\(failures.count) 个账户读取失败，其余账户不受影响"
    }

    func apply(_ result: RateLimitReadResult) {
        let readings = EnergyLogic.accountReadings(from: result)
        let limits = EnergyLogic.quotaLimits(from: result)
        if quotas != readings { quotas = readings }
        if quotaLimits != limits { quotaLimits = limits }
        if resetCredits != result.rateLimitResetCredits { resetCredits = result.rateLimitResetCredits }
        lastQuotaUpdate = startsTimers ? .now : clockNow
        lastQuotaAttempt = lastQuotaUpdate
        isRefreshing = false
        quotaRefreshError = limits.isEmpty ? "账户暂未返回可用额度" : nil
    }

    func markUnavailable() {
        lastQuotaAttempt = startsTimers ? .now : clockNow
        isRefreshing = false
        quotaRefreshError = lastQuotaUpdate == nil
            ? "无法读取额度，请检查 Codex 登录状态后重试"
            : "同步失败，显示上次读数"
    }

    func beginRefresh() { isRefreshing = true; lastQuotaAttempt = startsTimers ? .now : clockNow }
    func beginProjectRefresh() { isRefreshingProjects = true; projectRefreshError = nil }
    func markProjectsUnavailable() {
        isRefreshingProjects = false
        projectRefreshError = "无法读取部分本地日志，请检查目录访问权限后重试"
    }

    func applyProjects(_ summary: ProjectUsageDaySummary) {
        if !hasLoadedProjects { hasLoadedProjects = true }
        if projects != summary.projects { projects = summary.projects }
        lastProjectUpdate = startsTimers ? .now : clockNow
        isRefreshingProjects = false
        projectRefreshError = nil
        publishTodayUsage()
    }

    func setMode(_ mode: EnergyPanelMode) {
        if self.mode != mode { self.mode = mode }
    }
    func setCompactMode() { setMode(.compact) }

    /// Switch the 账户 page to another account; remembered across launches so
    /// reopening the page keeps the account the user last looked at.
    func selectAccount(_ id: String) {
        guard ([BalanceReading.codexID] + BalanceProvider.allCases.map(\.id)).contains(id), selectedAccountID != id else { return }
        selectedAccountID = id
        noteAccountOpened(id)
        defaults.set(id, forKey: EnergyStore.selectedAccountDefaultsKey)
    }

    private static let selectedAccountDefaultsKey = "energy-selected-account"

    /// 账户网格排序：使用频率记录与手动置顶（见 AccountRanking.swift）。
    private let usageTracker = AccountUsageTracker()
    private let pinStore = AccountPinStore()

    func isPinned(_ id: String) -> Bool { pinStore.isPinned(id) }

    /// 切换账户置顶；只影响 Mini 条网格顺序。
    func togglePin(_ id: String) { pinStore.toggle(id) }

    /// 清空排序学习数据（频率记录 + 置顶），恢复静态权重排序。
    func resetRankingData() {
        usageTracker.reset()
        pinStore.reset()
    }

    /// 打开账户页时记录一次使用，驱动显性排名。
    private func noteAccountOpened(_ id: String) { usageTracker.recordOpen(id: id) }

    var codexBalanceReading: BalanceReading {
        var reading = BalanceReading.codex(limits: quotaLimits, now: lastQuotaUpdate ?? clockNow)
        reading.updatedAt = lastQuotaUpdate
        reading.lastAttemptAt = lastQuotaAttempt
        if let error = quotaRefreshError { reading.state = reading.hasReading ? .stale(error) : .failed(error) }
        return reading.evaluated(at: clockNow)
    }

    var allBalanceReadings: [BalanceReading] {
        [codexBalanceReading] + balances.filter { $0.id != BalanceReading.codexID }.map { $0.evaluated(at: clockNow) }
    }

    /// What the compact bar shows: the full account list minus accounts whose
    /// client app is closed (or that are not configured), reordered by the
    /// dual ranking engine (usage frequency + capability, pins first).
    var compactBalanceReadings: [BalanceReading] {
        let visible = allBalanceReadings.filter { !hiddenBalanceIDs.contains($0.id) }
        let order = AccountRankingEngine(tracker: usageTracker, pinnedIDs: pinStore.orderedIDs)
            .orderedIDs(visible.map(\.id), now: clockNow)
        var ranked: [BalanceReading] = []
        ranked.reserveCapacity(visible.count)
        for id in order {
            if let reading = visible.first(where: { $0.id == id }) { ranked.append(reading) }
        }
        return ranked
    }

    /// The balance page keeps every account; the Mini bar recommendation is
    /// computed from what is actually visible there so it never recommends an
    /// account the user cannot see on the bar.
    var compactAdvice: UsageAdvice {
        AIUsageAdvisor.advise(readings: compactBalanceReadings, now: clockNow)
    }

    var balanceAdvice: UsageAdvice {
        AIUsageAdvisor.advise(readings: allBalanceReadings, now: clockNow)
    }

    init(defaults: UserDefaults = .standard, now: Date = .now, startsTimers: Bool = true,
         nightWatch: NightWatchController? = nil) {
        self.defaults = defaults
        self.startsTimers = startsTimers
        self.nightWatch = nightWatch ?? NightWatchController()
        self.clockNow = now
        self.dailyUsageLedger = DailyUsageStore.load(defaults: defaults)
        let selected = defaults.string(forKey: Self.selectedAccountDefaultsKey) ?? BalanceReading.codexID
        self.selectedAccountID = ([BalanceReading.codexID] + BalanceProvider.allCases.map(\.id)).contains(selected) ? selected : BalanceReading.codexID
        self.autoHideInactiveAccounts = defaults.object(forKey: AccountVisibility.autoHideDefaultsKey) as? Bool ?? true
        self.showsPricingRow = defaults.object(forKey: Self.pricingRowDefaultsKey) as? Bool ?? true
        self.pricingSnapshot = PricingEngine.snapshot(at: now, catalog: .builtIn)
        self.nightWatch.onChange = { [weak self] in self?.syncNightWatch() }
        loadLeaderboardCache()
        updateHiddenBalances()
        rollDailyUsageIfNeeded(now: now)
        publishTodayUsage()
        if startsTimers {
            clockTimer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()
                .sink { [weak self] date in self?.tick(now: date) }
        }
    }

    func activate(_ target: CompactActionTarget) {
        switch target {
        case .account(let id): selectAccount(id); setMode(.quota)
        case .page(let mode): setMode(mode)
        case .nightWatch: toggleNightWatch()
        }
    }

    var projectSummary: ProjectUsageDaySummary {
        ProjectUsageDaySummary(projects: projects, sessionSwitchCount: 0)
    }
}
