import Foundation

/// 账户网格排序引擎（2026-10-25 上线，需求见 docs/待办任务.md）。
///
/// 双排名逻辑：
/// 1. **显性 —— 使用频率**：`AccountUsageTracker` 记录本机打开各账户页面的
///    时间戳，按指数衰减加权（半衰期 3 天），越常用越靠前。
/// 2. **隐性 —— 受众 × 模型能力**：人工标定的静态权重（0–100），模型能力
///    弱、跑任务"水"的靠后。百度搭子按用户明确反馈垫底（8 分）。
///
/// 综合分 = 0.45 × 频率归一 + 0.55 × 能力归一；手动置顶永远最前（按置顶顺序）；
/// 同分保持原有相对顺序（稳定排序），避免账户在网格里无谓跳动。
///
/// Codex 是本应用的主账户，固定排第一：即使其他账户打开次数更多，也不会把它
/// 挤下去；置顶与自动排名只决定其余账户的顺序。
///
/// 只有 Mini 条（compactBalanceReadings）按此排序；余额详情页保持全量原序。
struct AccountRankingEngine {
    var frequencyWeight: Double
    var capabilityWeight: Double
    var capabilityWeights: [String: Double]
    var tracker: AccountUsageTracker
    var pinnedIDs: [String]

    init(
        frequencyWeight: Double = AccountRanking.frequencyWeight,
        capabilityWeight: Double = AccountRanking.capabilityWeight,
        capabilityWeights: [String: Double] = AccountRanking.capabilityWeights,
        tracker: AccountUsageTracker,
        pinnedIDs: [String] = []
    ) {
        self.frequencyWeight = frequencyWeight
        self.capabilityWeight = capabilityWeight
        self.capabilityWeights = capabilityWeights
        self.tracker = tracker
        self.pinnedIDs = pinnedIDs
    }

    /// 对给定的账户 id 列表排序。`ids` 的原始顺序作为稳定排序的兜底。
    /// Codex 固定首位，其余账户再按「置顶 → 综合分」排序。
    func orderedIDs(_ ids: [String], now: Date = .now) -> [String] {
        let others = ids.filter { $0 != "codex" }
        guard !others.isEmpty else { return ids }

        let rawScores = others.map { tracker.decayedScore(id: $0, now: now) }
        let maxRaw = rawScores.max() ?? 0

        struct Item {
            let id: String
            let composite: Double
            let pinRank: Int
            let original: Int
        }

        var items: [Item] = []
        for (index, id) in others.enumerated() {
            let frequency = maxRaw > 0 ? rawScores[index] / maxRaw : 0
            let capability = (capabilityWeights[id] ?? AccountRanking.defaultCapability) / 100
            items.append(Item(
                id: id,
                composite: frequencyWeight * frequency + capabilityWeight * capability,
                pinRank: pinnedIDs.firstIndex(of: id) ?? Int.max,
                original: index
            ))
        }

        let sorted = items.sorted { lhs, rhs in
            if lhs.pinRank != rhs.pinRank { return lhs.pinRank < rhs.pinRank }
            if abs(lhs.composite - rhs.composite) > 1e-9 { return lhs.composite > rhs.composite }
            return lhs.original < rhs.original
        }.map(\.id)

        return ids.contains("codex") ? ["codex"] + sorted : sorted
    }
}

/// 排序权重与口径的集中定义（测试与 UI 共用）。
enum AccountRanking {
    /// 频率 vs 能力的权重：频率略高——用户的核心诉求是"常用的排第一"；
    /// 无使用记录时能力兜底决定顺序。
    static let frequencyWeight = 0.55
    static let capabilityWeight = 0.45

    /// 隐性排名权重表（0–100），人工标定：
    /// - codex / deepseek：用户主力，能力与生态最强 → 第一梯队
    /// - workbuddy 系：本家产品，日常主力 → 中上
    /// - 千问办公 / Qoder CN / Trae CN：各有专长 → 中游
    /// - 豆包：通用对话可替代性高 → 中下
    /// - dumate（百度搭子）：用户反馈"跑任务真的好水" → 垫底
    static let capabilityWeights: [String: Double] = [
        "codex": 100,
        "deepseek": 96,
        "gemini": 93,
        "workbuddy": 92,
        "workbuddyintl": 88,
        "qwenwork": 74,
        "qoder": 72,
        "doubao": 70,
        "trae": 70,
        "dumate": 8,
    ]

    /// 未标定账户的能力初值：中游，保证排序不把它误沉底。
    static let defaultCapability: Double = 60

    /// 频率衰减半衰期：3 天（约 3 天前的 1 次打开 ≈ 现在的 0.5 次）。
    static let frequencyHalfLife: TimeInterval = 3 * 86_400

    /// 使用记录保留窗口：14 天。
    static let usageWindow: TimeInterval = 14 * 86_400

    /// 每账户事件上限，防止 UserDefaults 无限膨胀。
    static let usageEventCap = 500
}

/// 本机账户使用记录：打开账户页面的时间戳。纯本地 UserDefaults，不上传。
/// 内存缓存避免每次 SwiftUI 求值都解码 JSON。
final class AccountUsageTracker {
    private let defaults: UserDefaults
    private let key = "account-ranking-usage-log-v1"
    private var cache: [String: [Double]]?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 记录一次打开（账户页激活时调用）。
    func recordOpen(id: String, now: Date = .now) {
        var log = load()
        var events = log[id] ?? []
        events.append(now.timeIntervalSince1970)
        log[id] = Self.prune(events, now: now)
        save(log)
    }

    /// 指数衰减后的频率原始分：Σ 0.5^(距今天数 / 3)。
    /// 读取时顺带惰性裁剪窗口外事件（写入时已裁过一次，这里兜底防腐化）。
    func decayedScore(id: String, now: Date, halfLife: TimeInterval = AccountRanking.frequencyHalfLife) -> Double {
        guard let events = load()[id], !events.isEmpty else { return 0 }
        let nowT = now.timeIntervalSince1970
        let cutoff = nowT - AccountRanking.usageWindow
        var score = 0.0
        for t in events where t <= nowT + 60 && t >= cutoff {
            score += pow(0.5, (nowT - t) / halfLife)
        }
        return score
    }

    /// 清除全部记录（设置页"重置排序数据"用）。
    func reset() {
        cache = [:]
        defaults.removeObject(forKey: key)
    }

    private func load() -> [String: [Double]] {
        if let cache { return cache }
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: [Double]].self, from: data) else {
            return [:]
        }
        cache = decoded
        return decoded
    }

    private func save(_ log: [String: [Double]]) {
        cache = log
        if let data = try? JSONEncoder().encode(log) {
            defaults.set(data, forKey: key)
        }
    }

    /// 丢弃窗口外事件并按上限截断（保留最近的）。
    static func prune(_ events: [Double], now: Date, window: TimeInterval = AccountRanking.usageWindow, cap: Int = AccountRanking.usageEventCap) -> [Double] {
        let cutoff = now.timeIntervalSince1970 - window
        return Array(events.filter { $0 >= cutoff }.suffix(cap))
    }
}

/// 手动置顶列表（优先级最高，压过自动排名）。UserDefaults 持久化。
final class AccountPinStore {
    private let defaults: UserDefaults
    private let key = "account-ranking-pinned-v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var orderedIDs: [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    func isPinned(_ id: String) -> Bool {
        orderedIDs.contains(id)
    }

    /// 切换置顶；新置顶的排在最前。
    func toggle(_ id: String) {
        var ids = orderedIDs
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
        } else {
            ids.insert(id, at: 0)
        }
        defaults.set(ids, forKey: key)
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }
}
