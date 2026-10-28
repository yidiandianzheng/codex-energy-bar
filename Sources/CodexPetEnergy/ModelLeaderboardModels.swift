import Foundation

// MARK: - OpenRouter API 解码（免 key，GET /api/v1/models）

struct OpenRouterModelsResponse: Decodable {
    let data: [OpenRouterModel]
}

struct OpenRouterModel: Decodable {
    let id: String
    let name: String?
    let created: Double?
    let context_length: Int?
    let pricing: OpenRouterPricing?
    let architecture: OpenRouterArchitecture?
    let description: String?
}

struct OpenRouterPricing: Decodable {
    /// 每 token 单价，字符串形式（如 "0.000002"）；免费模型为 "0"。
    let prompt: String?
    let completion: String?
    /// 图像模型带 image 定价字段 → 识别为图像模型。
    let image: String?
}

struct OpenRouterArchitecture: Decodable {
    let output_modalities: [String]?
}

// MARK: - 展示行与快照（Codable，供落盘缓存）

/// 排行榜一行（展示ready，UI 不做事后计算）。
struct LeaderboardRow: Codable, Identifiable, Equatable {
    var id: String { modelID }
    let modelID: String
    let name: String
    let vendor: String
    let contextText: String
    let priceText: String
    let inputText: String
    let outputText: String
    /// 能力分文本："57.6"（AA 指数）/"96"（静态表）/"待标定"。
    let scoreText: String
    /// 附加说明：上线日期 / ★ 值得试 / 免费标记等。
    var noteText: String
    /// 性价比指数 0–100（仅性价比榜有值）。
    var valueIndex: Double?
    /// Artificial Analysis intelligence 指数（有值即来自 AA）。
    var aaScore: Double?
    /// 近一周 token 用量（热度榜用，绝对值）。
    var usageTokens: Double?
    /// 近一周用量环比变化（百分比，如 44.2）。
    var usageChange: Double?

    enum CodingKeys: String, CodingKey {
        case modelID, name, vendor, contextText, priceText, inputText, outputText
        case scoreText, noteText, valueIndex, aaScore, usageTokens, usageChange
    }
}

/// 四个榜单视图。与 Python 版四榜一一对应。
enum LeaderboardBoard: String, Codable, CaseIterable, Identifiable {
    case radar
    case capability
    case value
    case price
    case popularity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .radar: "新秀雷达"
        case .capability: "推理能力"
        case .value: "性价比"
        case .price: "价格"
        case .popularity: "热度"
        }
    }

    /// 分段选择器用短标题（420pt 宽放不下 5 个全标题）。
    var shortTitle: String {
        switch self {
        case .radar: "雷达"
        case .capability: "能力"
        case .value: "性价比"
        case .price: "价格"
        case .popularity: "热度"
        }
    }

    var note: String {
        switch self {
        case .radar: "近 30 天新上线；★ = 能力分 ≥90 或免费未标定，优先试"
        case .capability: "Artificial Analysis intelligence 指数（OpenRouter 页面内嵌，每日更新）；未收录回退静态表"
        case .value: "能力分 ÷ 混合单价；只收近半年上线的已标定模型，免费与旧模型不参与"
        case .price: "混合单价升序；0.75×输入 + 0.25×输出"
        case .popularity: "近一周 token 用量（OpenRouter 全平台统计），看大家实际在用什么"
        }
    }
}

struct LeaderboardBoardData: Codable, Identifiable, Equatable {
    var id: String { board.rawValue }
    let board: LeaderboardBoard
    let rows: [LeaderboardRow]
}

/// 一次完整的抓取 + 计算结果。整体 Codable → 可整体缓存。
struct LeaderboardSnapshot: Codable, Equatable {
    var checkedAt: Date
    var totalCount: Int
    var paidCount: Int
    var freeCount: Int
    var radarCount: Int
    var scoredCount: Int
    /// AA 指数覆盖的模型数（0 = 本次抓取没拿到 AA 数据，走了静态表兜底）。
    var aaCount: Int
    var boards: [LeaderboardBoardData]

    func rows(_ board: LeaderboardBoard) -> [LeaderboardRow] {
        boards.first { $0.board == board }?.rows ?? []
    }
}

///  rankings 页面附带的补充数据：AA 能力指数 + 全平台 token 用量。
///  解析失败时为 nil，引擎回退静态能力表（降级不中断）。
struct LeaderboardSupplement {
    /// key = heuristic_openrouter_slug（如 "anthropic/claude-opus-5.5"），value = AA intelligence 指数。
    var aaScores: [String: Double]
    /// key = model_permaslug，value = (近一周 tokens, 环比变化%)。
    var usage: [String: (tokens: Double, change: Double?)]
    /// 用量数据日期（页面内最新一天）。
    var usageDate: String?
}

// MARK: - 本地缓存（Application Support，~1MB JSON 不进 UserDefaults）

struct ModelLeaderboardCache {
    private static var fileURL: URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport.appendingPathComponent("CodexPetEnergy/leaderboard-cache.json", isDirectory: false)
    }

    func load() -> LeaderboardSnapshot? {
        guard let url = Self.fileURL, let data = FileManager.default.contents(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LeaderboardSnapshot.self, from: data)
    }

    func save(_ snapshot: LeaderboardSnapshot) {
        guard let url = Self.fileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("模型榜缓存写入失败：%@", String(describing: error))
        }
    }
}
