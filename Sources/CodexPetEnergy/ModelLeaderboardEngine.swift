import Foundation

/// 模型排行榜计算引擎（Swift 版，与 scripts/model_leaderboard.py 口径一致）。
///
/// 四榜：① 推理能力（人工静态分降序）② 性价比（分 ÷ 混合单价，指数归一化）
/// ③ 价格（混合单价升序，免费单列）④ 新秀雷达（近 30 天上线倒序）。
///
/// 公式：混合单价 = 0.75 × 输入价 + 0.25 × 输出价（$/M token）；
///       性价比 = 能力分 / 混合单价；指数 = 值 / 榜内最高值 × 100。
/// 图像模型（pricing 带 image 或输出模态含 image）与 batch 变体不进能力/性价比榜。
enum ModelLeaderboardEngine {

    /// 人工静态能力表（0–100，100 = 当期最强公开模型）。与 Python 版 CAPABILITY 同源，改一处记得同步另一处。
    /// 2026-10-25 代际更新：新一代旗舰入表（GPT-6.1-Sol / Claude Opus 5.5 / Gemini 4 Argon /
    /// GPT-5.2 / GPT-5.5 / Qwen3.5-Plus），上代 ≥94 分条目各降 4–5 分；≤93 分不动，相对顺序保留。
    static let capability: [String: Double] = [
        // 新一代（2026-09/10）
        "gpt-6.1-sol-pro": 100,
        "claude-opus-5.5": 99,
        "gpt-6.1-sol": 98,
        "gemini-4-argon": 98,
        "gpt-5.2-codex": 96,
        "claude-opus-5": 95,
        "gpt-5.5-pro": 95,
        "gpt-5.2-pro": 94,
        "gpt-5.5": 93,
        "gpt-5.2-chat": 92,
        "qwen3.5-plus": 92,
        // 上代旗舰（2026-10-25 各降 4–5 分）
        "gpt-5.1-codex-max": 96,
        "gpt-5.1-codex": 95,
        "claude-opus-4.5": 95,
        "gemini-3-pro": 95,
        "gpt-5.1": 94,
        "grok-4.1": 94,
        "kimi-k3.1-pro": 94,
        "kimi-k3.1": 92,
        "gpt-5-pro": 93,
        "gpt-5-codex": 93,
        "claude-sonnet-4.5": 93,
        "deepseek-v4.1-pro": 93,
        "gpt-5": 92,
        "gemini-2.5-pro": 92,
        "grok-4": 92,
        "claude-opus-4.1": 92,
        "glm-5": 92,
        // WorkBuddy 免费额度口径（2026-10-25 评测网标定）：Hy4 preview 追平
        // Claude Opus 5 的 Terminal Bench；Step-5 高于 DeepSeek V4 Pro；
        // Hy3 搜索/Agent 专精但深度代码与数学偏弱，低于 DeepSeek V4.1 Flash。
        "hy4": 94,
        "step-5": 93,
        "hy3": 86,
        "qwen3-max": 91,
        "gemini-3-flash": 90,
        "claude-sonnet-4": 90,
        "deepseek-v4.1": 90,
        "deepseek-v4": 89,
        "minimax-m2": 89,
        "doubao-seed-2.0-pro": 89,
        "deepseek-reasoner": 89,
        "codex-mini": 88,
        "qwen3-coder-plus": 88,
        "glm-4.6": 88,
        "kimi-k2-thinking": 87,
        "grok-4-fast": 87,
        "gpt-5-mini": 87,
        "minimax-m3.1-flash": 86,
        "deepseek-v3.2": 86,
        "deepseek-chat": 86,
        "qwen3-235b": 86,
        "claude-haiku-4.5": 86,
        "glm-4.5": 86,
        "kimi-k2": 85,
        "grok-code-fast": 85,
        "mistral-large-3": 85,
        "gemini-2.5-flash": 85,
        "deepseek-r1": 85,
        "nemotron": 83,
        "doubao-seed-2.0-lite": 83,
        "doubao-seed-1.6": 82,
        "glm-4.5-air": 82,
        "mercury-3": 82,
        "o4-mini": 82,
        "claude-3.5-sonnet": 82,
        "minimax-m1": 82,
        "magistral-medium": 81,
        "qwen3-30b": 81,
        "llama-4-maverick": 84,
        "llama-4-scout": 79,
        "ernie-5.0": 84,
        "ernie-4.5": 79,
        "gemini-2.0-flash": 79,
        "codestral": 79,
    ]

    /// 未标定初值（中游），仅用于文档说明；未命中表不打分。
    static let defaultCapability = 60.0

    static let radarWindow: TimeInterval = 30 * 86_400
    /// 性价比榜只收近半年上线的模型。旧的低价模型（如 Llama 4 Scout、
    /// Qwen3 2507）会长期霸榜，但已经没有推荐价值；它们仍留在能力/价格榜。
    static let valueWindow: TimeInterval = 180 * 86_400
    static let inputWeight = 0.75
    static let outputWeight = 0.25

    private struct Entry {
        let id: String
        let name: String
        let vendor: String
        let context: Int
        let inputPerM: Double
        let outputPerM: Double
        let blended: Double
        let free: Bool
        let image: Bool
        let batch: Bool
        let created: Double
        /// Artificial Analysis intelligence 指数（有值即来自 AA 页面数据）。
        let aaScore: Double?
        /// 人工静态表兜底分（AA 未收录时使用）。
        let staticScore: Double?
        let usageTokens: Double?
        let usageChange: Double?
    }

    // MARK: 主入口

    static func rank(models: [OpenRouterModel], supplement: LeaderboardSupplement? = nil, now: Date = .now, limit: Int = 40) -> LeaderboardSnapshot {
        // AA 指数顶格约 80，静态表顶格 100：两把尺子。有 AA 数据时把静态分
        // 按 AA 顶格等比缩放，保证混排时跨源可比；无 AA 数据时静态表原样兜底。
        let aaMax = supplement?.aaScores.values.max()
        let staticScale = aaMax.map { $0 / 100.0 } ?? 1.0
        var entries: [Entry] = []
        for model in models {
            let pricing = model.pricing
            let input = Self.perMillion(pricing?.prompt)
            let output = Self.perMillion(pricing?.completion)
            let blended = inputWeight * input + outputWeight * output
            let modalities = model.architecture?.output_modalities ?? []
            // 能力分：AA 指数优先（权威、覆盖新模型），未收录回退人工静态表。
            let aa = supplement?.aaScores[model.id]
            entries.append(Entry(
                id: model.id,
                name: model.name ?? model.id,
                vendor: model.id.split(separator: "/").first.map(String.init) ?? model.id,
                context: model.context_length ?? 0,
                inputPerM: input,
                outputPerM: output,
                blended: blended,
                free: blended <= 0,
                // 图像模型判定只看输出模态：pricing 带 image 价只说明「图像输入」要
                // 收费（如 Gemini 4 Argon 多模态文本模型），不能作为排除依据。
                image: modalities.contains("image"),
                batch: model.id.lowercased().contains("batch"),
                created: model.created ?? 0,
                aaScore: aa,
                staticScore: Self.capabilityOf(model.id).map { $0 * staticScale },
                usageTokens: supplement?.usage[model.id]?.tokens,
                usageChange: supplement?.usage[model.id]?.change
            ))
        }

        let paid = entries.filter { !$0.free }
        let free = entries.filter(\.free)

        let radarCutoff = now.timeIntervalSince1970 - radarWindow
        let radar = entries
            .filter { $0.created >= radarCutoff }
            .sorted { lhs, rhs in
                if lhs.created != rhs.created { return lhs.created > rhs.created }
                return lhs.id < rhs.id
            }

        let scored = entries.filter { ($0.aaScore != nil || $0.staticScore != nil) && !$0.image && !$0.batch }
        let capability = scored.sorted { lhs, rhs in
            let l = lhs.aaScore ?? lhs.staticScore ?? 0
            let r = rhs.aaScore ?? rhs.staticScore ?? 0
            if l != r { return l > r }
            return lhs.id < rhs.id
        }

        let valueCutoff = now.timeIntervalSince1970 - valueWindow
        let valued = scored.filter { !$0.free && $0.created >= valueCutoff }
        var valueRows: [(entry: Entry, index: Double)] = []
        let maxValue = valued.map { (($0.aaScore ?? $0.staticScore ?? 0)) / $0.blended }.max() ?? 1
        let safeMax = maxValue > 0 ? maxValue : 1
        for entry in valued {
            let value = (entry.aaScore ?? entry.staticScore ?? 0) / entry.blended
            valueRows.append((entry, value / safeMax * 100))
        }
        valueRows.sort { lhs, rhs in
            if lhs.index != rhs.index { return lhs.index > rhs.index }
            return lhs.entry.id < rhs.entry.id
        }

        let price = paid.sorted { lhs, rhs in
            if lhs.blended != rhs.blended { return lhs.blended < rhs.blended }
            return lhs.id < rhs.id
        }
        let priceFree = free.sorted { lhs, rhs in
            if lhs.context != rhs.context { return lhs.context > rhs.context }
            return lhs.id < rhs.id
        }

        // 热度榜：按近一周 token 用量降序（无用量数据的不进）。
        let popular = entries
            .filter { ($0.usageTokens ?? 0) > 0 }
            .sorted { lhs, rhs in
                if lhs.usageTokens != rhs.usageTokens { return (lhs.usageTokens ?? 0) > (rhs.usageTokens ?? 0) }
                return lhs.id < rhs.id
            }

        let boards: [LeaderboardBoardData] = [
            LeaderboardBoardData(board: .radar, rows: radar.prefix(limit).map { radarRow($0, now: now) }),
            LeaderboardBoardData(board: .capability, rows: capability.prefix(limit).map { row($0) }),
            LeaderboardBoardData(board: .value, rows: valueRows.prefix(limit).map { valueRow($0.entry, index: $0.index) }),
            LeaderboardBoardData(board: .price, rows: price.prefix(limit).map { row($0) }
                + priceFree.prefix(limit).map { row($0) }),
            LeaderboardBoardData(board: .popularity, rows: popular.prefix(limit).map { popularityRow($0) }),
        ]

        return LeaderboardSnapshot(
            checkedAt: now,
            totalCount: entries.count,
            paidCount: paid.count,
            freeCount: free.count,
            radarCount: radar.count,
            scoredCount: scored.count,
            aaCount: entries.filter { $0.aaScore != nil }.count,
            boards: boards
        )
    }

    // MARK: 行构造

    /// 能力分展示文本：AA 指数保留一位小数；静态表取整；都没有 → 待标定。
    private static func scoreText(_ entry: Entry) -> String {
        if let aa = entry.aaScore { return String(format: "%.1f", aa) }
        if let staticScore = entry.staticScore {
            return staticScore == staticScore.rounded() ? String(format: "%.0f", staticScore) : String(format: "%.1f", staticScore)
        }
        return "待标定"
    }

    private static func row(_ entry: Entry) -> LeaderboardRow {
        LeaderboardRow(
            modelID: entry.id,
            name: entry.name,
            vendor: entry.vendor,
            contextText: contextText(entry.context),
            priceText: priceText(entry.blended),
            inputText: priceText(entry.inputPerM),
            outputText: priceText(entry.outputPerM),
            scoreText: scoreText(entry),
            noteText: entry.free ? "免费" : "",
            aaScore: entry.aaScore,
            usageTokens: entry.usageTokens,
            usageChange: entry.usageChange
        )
    }

    private static func valueRow(_ entry: Entry, index: Double) -> LeaderboardRow {
        var result = row(entry)
        result.valueIndex = index.rounded()
        return result
    }

    private static func radarRow(_ entry: Entry, now: Date) -> LeaderboardRow {
        var result = row(entry)
        let date = Date(timeIntervalSince1970: entry.created)
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        formatter.timeZone = .current
        var note = formatter.string(from: date) + " 上线"
        let effective = entry.aaScore ?? entry.staticScore ?? 0
        // 阈值 75 对两把尺子都约等于「第一梯队」：AA 顶格 ~82，静态顶格 100。
        let worthTrying = effective >= 75 || (entry.aaScore == nil && entry.staticScore == nil && entry.free)
        if worthTrying { note += " · ★ 值得试" }
        if entry.image { note += " · 图像" }
        result.noteText = note
        return result
    }

    private static func popularityRow(_ entry: Entry) -> LeaderboardRow {
        var result = row(entry)
        var note = "近一周 " + tokenText(entry.usageTokens ?? 0)
        if let change = entry.usageChange {
            note += change >= 0 ? " · ↑\(String(format: "%.0f", change))%" : " · ↓\(String(format: "%.0f", abs(change)))%"
        }
        result.noteText = note
        return result
    }

    /// token 量缩写：1.2T / 340B / 5.1M。
    static func tokenText(_ tokens: Double) -> String {
        switch tokens {
        case 1_000_000_000_000...: return String(format: "%.1fT", tokens / 1_000_000_000_000)
        case 1_000_000_000...: return String(format: "%.0fB", tokens / 1_000_000_000)
        case 1_000_000...: return String(format: "%.1fM", tokens / 1_000_000)
        default: return "\(Int(tokens))"
        }
    }

    // MARK: 工具

    /// 最长子串命中，避免 "deepseek-v4" 误中 "deepseek-v4.1-flash"。
    static func capabilityOf(_ modelID: String) -> Double? {
        var best: Double?
        var bestLength = 0
        for (key, score) in capability where modelID.contains(key) && key.count > bestLength {
            best = score
            bestLength = key.count
        }
        return best
    }

    /// 每 token 字符串 → 每百万 token 美元。
    static func perMillion(_ value: String?) -> Double {
        guard let value, let perToken = Double(value), perToken.isFinite else { return 0 }
        return perToken * 1_000_000
    }

    static func priceText(_ perMillion: Double) -> String {
        guard perMillion > 0 else { return "免费" }
        if perMillion < 0.01 { return String(format: "$%.5f", perMillion) }
        if perMillion < 1 { return String(format: "$%.3f", perMillion) }
        return String(format: "$%.2f", perMillion)
    }

    static func contextText(_ length: Int) -> String {
        guard length > 0 else { return "—" }
        if length >= 1_000_000 {
            return "\((length + 500_000) / 1_000_000)M"
        }
        return "\(length / 1024)K"
    }
}
