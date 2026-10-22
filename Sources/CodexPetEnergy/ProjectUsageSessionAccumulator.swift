import Foundation

struct ProjectUsageSessionAccumulator: Equatable {
    private static let sessionMarker = Data("\"session_meta\"".utf8)
    private static let tokenMarker = Data("\"token_count\"".utf8)

    private(set) var sessionID: String
    private(set) var directory: String?
    private(set) var totals = ProjectUsageTotals.zero
    private(set) var lastActivity: Date?

    init(fallbackID: String) {
        sessionID = fallbackID
    }

    mutating func consume(_ line: Data, startOfDay: Date) {
        guard isRelevant(line),
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = object["type"] as? String,
              let payload = object["payload"] as? [String: Any]
        else { return }

        if type == "session_meta" {
            sessionID = (payload["id"] as? String) ?? (payload["session_id"] as? String) ?? sessionID
            directory = payload["cwd"] as? String
            return
        }

        guard type == "event_msg",
              payload["type"] as? String == "token_count",
              let timestamp = Self.parseTimestamp(object["timestamp"] as? String),
              timestamp >= startOfDay,
              let info = (payload["info"] as? [String: Any])
                ?? ((payload["payload"] as? [String: Any])?["info"] as? [String: Any]),
              let usage = info["last_token_usage"] as? [String: Any]
        else { return }

        let input = Self.integer(usage["input_tokens"])
        let output = Self.integer(usage["output_tokens"])
        totals = totals.adding(
            ProjectUsageTotals(
                inputTokens: input,
                outputTokens: output,
                reasoningTokens: Self.integer(usage["reasoning_output_tokens"]),
                cachedInputTokens: Self.integer(usage["cached_input_tokens"]),
                turnCount: 1,
                maximumTurnTokens: input + output
            )
        )
        lastActivity = max(lastActivity ?? timestamp, timestamp)
    }

    mutating func consumeCompleteJSONLines(
        in data: Data,
        startOfDay: Date,
        includesSessionMetadata: Bool
    ) -> Data {
        guard let finalNewline = data.lastIndex(of: 0x0A) else { return data }
        let completeEnd = data.index(after: finalNewline)

        if includesSessionMetadata,
           let firstNewline = data[..<completeEnd].firstIndex(of: 0x0A) {
            consume(data[..<firstNewline], startOfDay: startOfDay)
        }

        var searchStart = data.startIndex
        while searchStart < completeEnd,
              let marker = data.range(
                of: Self.tokenMarker,
                options: [],
                in: searchStart..<completeEnd
              ) {
            let lineStart = data[..<marker.lowerBound].lastIndex(of: 0x0A).map {
                data.index(after: $0)
            } ?? data.startIndex
            let lineEnd = data[marker.upperBound..<completeEnd].firstIndex(of: 0x0A)
                ?? completeEnd
            consume(data[lineStart..<lineEnd], startOfDay: startOfDay)
            searchStart = lineEnd < completeEnd ? data.index(after: lineEnd) : completeEnd
        }

        return Data(data[completeEnd...])
    }

    func makeSession() -> ProjectUsageSession? {
        guard let directory, let lastActivity, totals.totalTokens > 0 else { return nil }
        return ProjectUsageSession(
            id: sessionID,
            directory: directory,
            totals: totals,
            lastActivity: lastActivity
        )
    }

    private func isRelevant(_ line: Data) -> Bool {
        line.range(of: Self.sessionMarker) != nil || line.range(of: Self.tokenMarker) != nil
    }

    private static func integer(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        return 0
    }

    private static func parseTimestamp(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        return ISO8601DateFormatter.withFractionalSeconds.date(from: raw)
            ?? ISO8601DateFormatter.standard.date(from: raw)
    }
}
