import Foundation

/// Every provider owns one in-flight token and a deadline. Late or duplicate
/// callbacks cannot complete a newer attempt or overwrite its result.
final class BalanceMonitor {
    typealias Fetcher = (BalanceProvider, @escaping (BalanceReading) -> Void) -> Void
    var onReading: ((BalanceReading) -> Void)?
    var onFinished: (() -> Void)?
    var onRefreshing: ((Set<String>) -> Void)?

    private let queue = DispatchQueue(label: "codex.pet.energy.balance")
    private let workers = DispatchQueue(label: "codex.pet.energy.balance.fetch", attributes: .concurrent)
    private let deepSeek = DeepSeekBalanceClient()
    private let workBuddy = WorkBuddyBalanceClient(provider: .workbuddy, configDirectoryName: ".workbuddy")
    private let workBuddyIntl = WorkBuddyBalanceClient(provider: .workbuddyintl, configDirectoryName: ".workbuddy-ai")
    private let doubao = DoubaoBalanceClient()
    private let duMate = DuMateBalanceClient()
    private let qwenWork = QwenWorkBalanceClient()
    private var timer: DispatchSourceTimer?
    private var inFlight: [BalanceProvider: UUID] = [:]
    private let refreshInterval: TimeInterval
    private let providerTimeout: TimeInterval
    private let fetcher: Fetcher?

    init(refreshInterval: TimeInterval = 300, providerTimeout: TimeInterval = 30, fetcher: Fetcher? = nil) {
        self.refreshInterval = max(1, refreshInterval)
        self.providerTimeout = max(0.01, providerTimeout)
        self.fetcher = fetcher
    }

    func start() {
        queue.async { [self] in
            self.timer?.cancel()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 2, repeating: self.refreshInterval)
            timer.setEventHandler { [weak self] in self?.performRefresh(providers: Set(BalanceProvider.allCases)) }
            timer.resume()
            self.timer = timer
        }
    }

    func stop() {
        queue.async {
            self.timer?.cancel()
            self.timer = nil
            self.inFlight.removeAll()
            self.publishRefreshing()
        }
    }

    func refresh(providers: Set<BalanceProvider>? = nil) {
        queue.async { self.performRefresh(providers: providers ?? Set(BalanceProvider.allCases)) }
    }

    private func performRefresh(providers: Set<BalanceProvider>) {
        for provider in BalanceProvider.allCases where providers.contains(provider) && inFlight[provider] == nil {
            let token = UUID()
            inFlight[provider] = token
            publishRefreshing()
            queue.asyncAfter(deadline: .now() + providerTimeout) { [weak self] in
                self?.complete(provider: provider, token: token, reading: provider.failed("读取超时，请重试"))
            }
            workers.async { [weak self] in
                guard let self else { return }
                let completion: (BalanceReading) -> Void = { [weak self] reading in
                    self?.queue.async { self?.complete(provider: provider, token: token, reading: reading) }
                }
                if let fetcher = self.fetcher { fetcher(provider, completion) }
                else { self.fetch(provider, completion: completion) }
            }
        }
    }

    private func fetch(_ provider: BalanceProvider, completion: @escaping (BalanceReading) -> Void) {
        let config = BalanceConfig.load()
        switch provider {
        case .deepseek:
            if let key = config.deepSeekAPIKey { deepSeek.fetch(apiKey: key, completion: completion) }
            else { completion(provider.unconfigured("未找到 DeepSeek API Key：可写入 ~/.config/codex-energy-bar/sources.json 的 deepseek.apiKey")) }
        case .doubao:
            doubao.fetch(productLine: config.doubaoProductLine, fallbackCookie: config.doubaoCookie, completion: completion)
        case .workbuddy:
            if config.workBuddyEnabled { workBuddy.fetch(completion: completion) }
            else { completion(provider.unconfigured("已在配置中关闭 WorkBuddy 读取")) }
        case .workbuddyintl:
            if config.workBuddyIntlEnabled { workBuddyIntl.fetch(completion: completion) }
            else { completion(provider.unconfigured("已在配置中关闭 WorkBuddy AI 读取")) }
        case .dumate:
            if config.duMateEnabled { duMate.fetch(completion: completion) }
            else { completion(provider.unconfigured("已在配置中关闭百度搭子读取")) }
        case .qwenwork:
            if config.qwenWorkEnabled { qwenWork.fetch(completion: completion) }
            else { completion(provider.unconfigured("已在配置中关闭千问办公读取")) }
        }
    }

    private func complete(provider: BalanceProvider, token: UUID, reading: BalanceReading) {
        guard inFlight[provider] == token else { return }
        inFlight.removeValue(forKey: provider)
        var result = reading
        result.lastAttemptAt = result.lastAttemptAt ?? .now
        let isFinished = inFlight.isEmpty
        DispatchQueue.main.async { [weak self] in
            self?.onReading?(result)
            if isFinished { self?.onFinished?() }
        }
        publishRefreshing()
    }

    private func publishRefreshing() {
        let identifiers = Set(inFlight.keys.map(\.id))
        DispatchQueue.main.async { [weak self] in self?.onRefreshing?(identifiers) }
    }
}
