import Foundation

/// 模型榜数据客户端：OpenRouter `/api/v1/models`（免 key）。
///
/// 契约（与 Python 版一致）：
/// - 自动刷新每 15 分钟检查一次，距上次成功 >24h 才真正请求（每日 1 更）
/// - 手动 refresh() 立即请求，但 60 秒内不重复（防连点）
/// - 失败 / 空数据 / 200+错误体 → onError，由上层保留上一份好数据
/// 端点与节奏常量（nonisolated，供非隔离网络函数使用）。
private enum LeaderboardEndpoint {
    static let modelsURL = "https://openrouter.ai/api/v1/models"
    /// rankings 页面服务端渲染时内嵌 AA intelligence 指数与全平台 token 用量
    /// （react-query 脱水状态）；没有公开 JSON API，只能解析 HTML。
    static let rankingsURL = "https://openrouter.ai/rankings"
    static let autoInterval: TimeInterval = 15 * 60
    static let manualInterval: TimeInterval = 60
    static let freshWindow: TimeInterval = 24 * 3_600
}

/// rankings 页面解析器（纯函数，便于测试）。
enum LeaderboardRankingsParser {
    /// 从 HTML 中提取 Next.js RSC 负载并解析 AA 指数与用量统计。
    /// 任何一步失败返回 nil（调用方回退静态能力表，降级不中断）。
    static func supplement(fromHTML html: String) -> LeaderboardSupplement? {
        guard let blob = rscBlob(from: html), !blob.isEmpty else { return nil }

        var aaScores: [String: Double] = [:]
        let aaPattern = #""heuristic_openrouter_slug":"([^"]+)","aa_name":"[^"]*","score":([0-9.]+)"#
        for match in matches(aaPattern, in: blob) {
            guard let slug = group(1, in: match, of: blob), let score = Double(group(2, in: match, of: blob) ?? "") else { continue }
            aaScores[slug] = score
        }
        guard !aaScores.isEmpty else { return nil }

        var usage: [String: (tokens: Double, change: Double?)] = [:]
        var usageDates: [String: String] = [:]
        var latestDate: String?
        let usagePattern = #""date":"([^"]+)","model_permaslug":"([^"]+)","variant":"[^"]*","total_completion_tokens":([0-9]+),"total_prompt_tokens":([0-9]+),.{0,900}?"change":(null|-?[0-9.]+)"#
        for match in matches(usagePattern, in: blob, dotAll: true) {
            guard let date = group(1, in: match, of: blob),
                  let slug = group(2, in: match, of: blob),
                  let completion = Double(group(3, in: match, of: blob) ?? ""),
                  let prompt = Double(group(4, in: match, of: blob) ?? "") else { continue }
            let changeText = group(5, in: match, of: blob)
            let change = changeText == "nil" || changeText == nil ? nil : Double(changeText ?? "")
            // 同一模型只保留最新日期的行。
            if let existingDate = usageDates[slug], existingDate >= date { continue }
            usage[slug] = (prompt + completion, change)
            usageDates[slug] = date
            if latestDate.map({ date > $0 }) ?? true { latestDate = date }
        }

        return LeaderboardSupplement(aaScores: aaScores, usage: usage, usageDate: latestDate)
    }

    /// 拼接所有 `self.__next_f.push([1,"..."])` 字符串字面量并做基础反转义。
    ///
    /// 注意：必须用手写逐字符扫描而非正则。含 AA 指数的 push 负载可达 600KB+，
    /// ICU 正则的 `(?:[^"\\]|\\.)*` 星号组在超长字符串上会因正则栈溢出而
    /// **静默匹配失败**（实测 615K 字符负载 0 匹配），短 push 却正常。
    static func rscBlob(from html: String) -> String? {
        var blob = ""
        blob.reserveCapacity(html.count / 4)
        for payload in pushPayloads(in: html) {
            blob += unescape(payload)
        }
        return blob.isEmpty ? nil : blob
    }

    /// 逐字符扫描所有 `self.__next_f.push([1,"…"])` 的原始（未反转义）负载。
    /// 遇到 `\` 跳过下一字符（转义），遇到后跟 `])` 的未转义 `"` 即为负载终点。
    private static func pushPayloads(in html: String) -> [String] {
        let marker = "self.__next_f.push([1,\""
        var payloads: [String] = []
        var searchRange = html.startIndex..<html.endIndex
        while let range = html.range(of: marker, range: searchRange) {
            var payload = ""
            var i = range.upperBound // marker 已含开引号，此处即 payload 首字符
            while i < html.endIndex {
                let ch = html[i]
                if ch == "\\" {
                    let next = html.index(after: i)
                    guard next < html.endIndex else { break }
                    payload.append(ch)
                    payload.append(html[next])
                    i = html.index(after: next)
                    continue
                }
                if ch == "\"" {
                    let n1 = html.index(after: i)
                    let n2 = n1 < html.endIndex ? html.index(after: n1) : html.endIndex
                    if n1 < html.endIndex, n2 < html.endIndex, html[n1] == "]", html[n2] == ")" {
                        payloads.append(payload)
                        break
                    }
                }
                payload.append(ch)
                i = html.index(after: i)
            }
            searchRange = range.upperBound..<html.endIndex
        }
        return payloads
    }

    /// 基础 JS 字符串反转义（只需还原引号与反斜杠，\uXXXX 不影响字段匹配）。
    static func unescape(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"\""#, with: "\"")
            .replacingOccurrences(of: #"\\"#, with: "\\")
            .replacingOccurrences(of: #"\n"#, with: "\n")
            .replacingOccurrences(of: #"\t"#, with: "\t")
            .replacingOccurrences(of: #"\r"#, with: "\r")
    }

    // MARK: 小工具

    private static func matches(_ pattern: String, in text: String, dotAll: Bool = false) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: dotAll ? [.dotMatchesLineSeparators] : []) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: range)
    }

    private static func group(_ index: Int, in match: NSTextCheckingResult, of text: String) -> String? {
        guard let range = Range(match.range(at: index), in: text) else { return nil }
        return String(text[range])
    }
}

@MainActor
final class ModelLeaderboardClient {
    var onLoading: (() -> Void)?
    var onModels: (([OpenRouterModel], LeaderboardSupplement?) -> Void)?
    var onError: ((String) -> Void)?

    private var loop: Task<Void, Never>?
    private var request: Task<Void, Never>?
    private var lastAttempt: Date?
    private var lastSuccess: Date?

    func start() {
        guard loop == nil else { return }
        refreshIfStale()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: UInt64(LeaderboardEndpoint.autoInterval) * 1_000_000_000) } catch { return }
                self?.refreshIfStale()
            }
        }
    }

    func stop() { loop?.cancel(); loop = nil; request?.cancel(); request = nil }

    /// 自动链路：仅在上次成功超过 24h 时才请求。
    func refreshIfStale() {
        guard lastSuccess.map({ Date().timeIntervalSince($0) >= LeaderboardEndpoint.freshWindow }) ?? true else { return }
        refresh()
    }

    /// 手动刷新（页面刷新按钮）。60s 内不重复。
    func refresh() {
        guard request == nil, lastAttempt.map({ Date().timeIntervalSince($0) >= LeaderboardEndpoint.manualInterval }) ?? true else { return }
        lastAttempt = .now
        onLoading?()
        request = Task { [weak self] in
            do {
                // 两个源并行抓：模型清单（必需）+ rankings 页面（AA 指数/用量，可选）。
                async let modelsResult = Self.fetchModels()
                async let rankingsHTML = Self.fetchRankingsHTML()
                let models = try await modelsResult
                let supplement: LeaderboardSupplement?
                if let html = try? await rankingsHTML {
                    supplement = LeaderboardRankingsParser.supplement(fromHTML: html)
                } else {
                    supplement = nil
                }
                guard !Task.isCancelled else { return }
                guard !models.isEmpty else { throw URLError(.zeroByteResource) }
                self?.lastSuccess = .now
                self?.onModels?(models, supplement)
            } catch {
                guard !Task.isCancelled else { return }
                self?.onError?(Self.message(for: error))
            }
            self?.request = nil
        }
    }

    private nonisolated static func message(for error: Error) -> String {
        if let urlError = error as? URLError, urlError.code == .notConnectedToInternet {
            return "网络不可用，显示上次数据"
        }
        return "榜单暂不可用，显示上次数据"
    }

    private nonisolated static func fetchModels() async throws -> [OpenRouterModel] {
        let data = try await Self.fetchText(LeaderboardEndpoint.modelsURL, timeout: 60, maxBytes: 4_000_000)
        return try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data).data
    }

    private nonisolated static func fetchRankingsHTML() async throws -> String {
        let data = try await Self.fetchText(LeaderboardEndpoint.rankingsURL, timeout: 30, maxBytes: 8_000_000)
        return String(decoding: data, as: UTF8.self)
    }

    private nonisolated static func fetchText(_ urlString: String, timeout: TimeInterval, maxBytes: Int) async throws -> Data {
        var request = URLRequest(url: URL(string: urlString)!)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("ComputeRing/1.4.0 (+https://github.com/yidiandianzheng/compute-ring)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard http.statusCode == 200, data.count <= maxBytes else { throw URLError(.badServerResponse) }
        return data
    }
}
