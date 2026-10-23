import Foundation
import CoreFoundation

struct ProjectUsageSessionAccumulator: Equatable {
    private static let sessionMarker = Data("\"session_meta\"".utf8)
    private static let tokenMarker = Data("\"token_count\"".utf8)

    private struct UsageSignature: Hashable {
        let input: Int
        let output: Int
        let reasoning: Int
        let cached: Int
        let total: Int?

        init(_ usage: [String: Any]) {
            input = ProjectUsageSessionAccumulator.integer(usage["input_tokens"])
            output = ProjectUsageSessionAccumulator.integer(usage["output_tokens"])
            reasoning = ProjectUsageSessionAccumulator.integer(usage["reasoning_output_tokens"])
            cached = ProjectUsageSessionAccumulator.integer(usage["cached_input_tokens"])
            total = usage["total_tokens"].map { ProjectUsageSessionAccumulator.integer($0) }
        }
    }

    private struct EventIdentity: Hashable {
        let sessionID: String
        let timestamp: Date
        let usage: UsageSignature
        let cumulative: UsageSignature?
    }

    private(set) var sessionID: String
    private(set) var directory: String?
    private(set) var totals = ProjectUsageTotals.zero
    private(set) var lastActivity: Date?
    private var seenEvents: Set<EventIdentity> = []

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
            directory = (payload["cwd"] as? String) ?? directory
            return
        }

        guard type == "event_msg",
              payload["type"] as? String == "token_count",
              let timestamp = Self.parseTimestamp(object["timestamp"] as? String),
              timestamp >= startOfDay, timestamp < startOfDay.addingTimeInterval(86_400),
              let info = (payload["info"] as? [String: Any])
                ?? ((payload["payload"] as? [String: Any])?["info"] as? [String: Any]),
              let usage = info["last_token_usage"] as? [String: Any]
        else { return }

        let normalized = UsageSignature(usage)
        let identity = EventIdentity(
            sessionID: sessionID, timestamp: timestamp, usage: normalized,
            cumulative: (info["total_token_usage"] as? [String: Any]).map(UsageSignature.init)
        )
        // Only the same event is idempotent. Equal-sized turns at different
        // timestamps (or with different cumulative fields) remain separate.
        guard seenEvents.insert(identity).inserted else { return }
        let turn = ProjectUsageMath.adding(.zero, ProjectUsageTotals(
            inputTokens: normalized.input, outputTokens: normalized.output,
            reasoningTokens: normalized.reasoning, cachedInputTokens: normalized.cached,
            turnCount: 1,
            maximumTurnTokens: ProjectUsageMath.sum(normalized.input, normalized.output)
        ))
        // last_token_usage is attributed by event time. Cumulative session totals
        // are identity evidence only: they may include yesterday or a reset.
        totals = ProjectUsageMath.adding(totals, turn)
        lastActivity = max(lastActivity ?? timestamp, timestamp)
    }

    mutating func consumeCompleteJSONLines(
        in data: Data,
        startOfDay: Date,
        includesSessionMetadata _: Bool
    ) -> Data {
        var lineStart = data.startIndex
        while lineStart < data.endIndex,
              let newline = data[lineStart...].firstIndex(of: 0x0A) {
            // Metadata may finish in a later read or occur after a preamble.
            // Every complete line must therefore be eligible for metadata.
            consume(Data(data[lineStart..<newline]), startOfDay: startOfDay)
            lineStart = data.index(after: newline)
        }
        return Data(data[lineStart...])
    }

    func makeSession() -> ProjectUsageSession? {
        guard let directory, let lastActivity, totals.totalTokens > 0 else { return nil }
        return ProjectUsageSession(id: sessionID, directory: directory, totals: totals, lastActivity: lastActivity)
    }

    private func isRelevant(_ line: Data) -> Bool {
        line.range(of: Self.sessionMarker) != nil || line.range(of: Self.tokenMarker) != nil
    }

    private static func integer(_ value: Any?) -> Int {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return 0 }
        if let exact = value as? Int { return max(0, exact) }
        let value = number.doubleValue
        guard value.isFinite, value > 0 else { return 0 }
        // Comparing before conversion avoids Int(Double.infinity / 1e100) traps.
        if value >= Double(Int.max) { return Int.max }
        return Int(value.rounded(.towardZero))
    }

    private static func parseTimestamp(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        return ISO8601DateFormatter.withFractionalSeconds.date(from: raw)
            ?? ISO8601DateFormatter.standard.date(from: raw)
    }
}

/// Saturation applies only at the Int representation limit. Keep input + output
/// representable too, since the shared totals model computes that sum directly.
enum ProjectUsageMath {
    static func sum(_ lhs: Int, _ rhs: Int) -> Int {
        let (result, overflow) = max(0, lhs).addingReportingOverflow(max(0, rhs))
        return overflow ? Int.max : result
    }

    static func adding(_ lhs: ProjectUsageTotals, _ rhs: ProjectUsageTotals) -> ProjectUsageTotals {
        let input = sum(lhs.inputTokens, rhs.inputTokens)
        let output = min(sum(lhs.outputTokens, rhs.outputTokens), Int.max - input)
        return ProjectUsageTotals(
            inputTokens: input, outputTokens: output,
            reasoningTokens: sum(lhs.reasoningTokens, rhs.reasoningTokens),
            cachedInputTokens: sum(lhs.cachedInputTokens, rhs.cachedInputTokens),
            turnCount: sum(lhs.turnCount, rhs.turnCount),
            maximumTurnTokens: max(0, lhs.maximumTurnTokens, rhs.maximumTurnTokens)
        )
    }
}
