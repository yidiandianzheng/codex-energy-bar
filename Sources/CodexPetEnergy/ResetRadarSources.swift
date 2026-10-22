import Foundation

/// Public read-only feeds. Account credentials and usage never enter these requests.
enum ResetRadarSources {
    static let primaryURL = URL(string: "https://codex-resets.com/zh-CN")!

    struct Primary: Decodable {
        let data: Status
        let meta: Meta
        struct Meta: Decodable { let generated_at: String }
        struct Status: Decodable {
            let latest_reset: Event?
            let scheduled_reset: Scheduled?
            let active_watch: Watch?
        }
        struct Event: Decodable {
            let id: String
            let reset_type: String
            let announced_at: String
            let text: String
            let source: Source
        }
        struct Source: Decodable { let url: String? }
        struct Scheduled: Decodable {
            let scheduled_for: String?
            let announced_at: String
            let reset_type: String
            let text: String
            let source: Source
        }
        struct Watch: Decodable {
            let reset_chance_percent: Double?
            let forecast_window: String
            let observed_at: String
            let expires_at: String
            let text: String
            let source: Source
        }
    }

    struct Archive: Decodable {
        let events: [Event]
        struct Event: Decodable, Identifiable {
            let tweet_id: String
            let tweet_url: String?
            let text: String
            let display_text: String?
            let announced_at: String
            let reset_type: String
            var id: String { tweet_id }
        }
    }

    static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    static func beijing(_ date: Date?) -> String {
        guard let date else { return "时间未提供" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }

    static func safeLink(_ text: String?) -> URL? {
        guard let text, let url = URL(string: text), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    static func cleanText(_ text: String) -> String {
        text.replacingOccurrences(of: #"https://t\.co/\S+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
