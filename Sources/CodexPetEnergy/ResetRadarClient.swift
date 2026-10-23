import Foundation

@MainActor
final class ResetRadarClient {
    var onUpdate: ((ResetRadarSnapshot) -> Void)?
    var onLoading: (() -> Void)?
    private var loop: Task<Void, Never>?
    private var request: Task<Void, Never>?
    private var lastAttempt: Date?
    private var lastSnapshot: ResetRadarSnapshot?
    private var retryAfter: [Int: Date] = [:]

    func start() {
        guard loop == nil else { return }
        refresh()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 900_000_000_000) } catch { return }
                self?.refresh()
            }
        }
    }
    func stop() { loop?.cancel(); loop = nil; request?.cancel(); request = nil }

    func refresh() {
        // Respect source rate limits even under repeated refresh clicks.
        guard request == nil, lastAttempt.map({ Date().timeIntervalSince($0) >= 60 }) ?? true else { return }
        lastAttempt = .now
        onLoading?()
        request = Task { [weak self] in
            let endpoints = [
                "https://codex-resets.com/api/v1/status",
                "https://codex-resets.com/api/resets?locale=zh-CN",
                ResetReferenceForecast.endpoint
            ]
            var results: [Int: Data] = [:]
            var errors: [String] = []
            let names = ["Codex Resets 预警", "Codex Resets 消息", "codex-reset.com 参考"]
            let cooldowns = self?.retryAfter ?? [:]
            var retryDates: [Int: Date] = [:]
            await withTaskGroup(of: (Int, Data?, Date?).self) { group in
                for (index, endpoint) in endpoints.enumerated() {
                    if let retry = cooldowns[index], retry > Date() {
                        errors.append("\(names[index])请求受限，\(ResetRadarSources.beijing(retry)) 后可重试")
                        continue
                    }
                    group.addTask {
                        do { return (index, try await Self.fetch(endpoint), nil) }
                        catch let ResetRadarHTTP.Failure.rateLimited(date) { return (index, nil, date) }
                        catch { return (index, nil, nil) }
                    }
                }
                for await (index, data, retry) in group {
                    if let data { results[index] = data } else { errors.append("\(names[index])暂不可用") }
                    if let retry { retryDates[index] = retry }
                }
            }
            guard !Task.isCancelled else { return }
            let decoder = JSONDecoder()
            func decode<T: Decodable>(_ type: T.Type, _ index: Int) -> T? {
                guard let data = results[index] else { return nil }
                do { return try decoder.decode(type, from: data) }
                catch { errors.append("\(names[index])格式已变更"); return nil }
            }
            // Retain recent data only on failure; a successful empty watch clears old signals.
            // Freshness still uses generated_at, so a retry cannot renew an expired reading.
            let primary = decode(ResetRadarSources.Primary.self, 0) ?? self?.lastSnapshot?.primary
            let archive = decode(ResetRadarSources.Archive.self, 1) ?? self?.lastSnapshot?.archive
            // A 200 response can still be a source error payload (e.g. published_copy_unavailable);
            // it decodes into an all-optional struct with no reading, so keep the last good one.
            func decodedReference() -> ResetReferenceForecast? {
                guard let decoded: ResetReferenceForecast = decode(ResetReferenceForecast.self, 2) else { return nil }
                if decoded.updated_at == nil, decoded.probabilities == nil, decoded.official_signal == nil { return nil }
                return decoded
            }
            let reference = decodedReference() ?? self?.lastSnapshot?.reference
            for (index, retry) in retryDates {
                self?.retryAfter[index] = retry
                errors.append("\(names[index])请求受限，\(ResetRadarSources.beijing(retry)) 后可重试")
            }
            let snapshot = ResetRadarSnapshot(primary: primary, archive: archive, reference: reference,
                checkedAt: .now, errors: errors.sorted())
            self?.lastSnapshot = snapshot
            self?.onUpdate?(snapshot)
            self?.request = nil
        }
    }

    nonisolated private static func fetch(_ endpoint: String) async throws -> Data {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("ComputeRing/1.4.0 (+https://github.com/yidiandianzheng/compute-ring)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Ephemeral session avoids cookies and credential persistence on third-party sites.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForResource = 20
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if response.statusCode == 429 {
            throw ResetRadarHTTP.Failure.rateLimited(ResetRadarHTTP.retryDate(response.value(forHTTPHeaderField: "Retry-After")))
        }
        guard response.statusCode == 200,
              data.count <= 2_000_000 else { throw URLError(.badServerResponse) }
        return data
    }
}

enum ResetRadarHTTP {
    enum Failure: Error { case rateLimited(Date) }
    static func retryDate(_ value: String?, now: Date = .now) -> Date {
        if let value, let seconds = Double(value), seconds.isFinite, seconds >= 0,
           seconds <= Date.distantFuture.timeIntervalSince(now) {
            return now.addingTimeInterval(max(60, seconds))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        if let value, let date = formatter.date(from: value) { return max(now.addingTimeInterval(60), date) }
        return now.addingTimeInterval(60)
    }
}
