import Foundation

/// Cost level shown as the traffic light. Colour is a deliberate local exception
/// to the app's monochrome palette; text and shape always accompany it.
enum PricingLight: String, Equatable, CaseIterable {
    case green
    case yellow
    case red
    case unknown

    var title: String {
        switch self {
        case .green: "省"
        case .yellow: "中"
        case .red: "贵"
        case .unknown: "未知"
        }
    }

    var shortTitle: String {
        switch self {
        case .green: "绿灯"
        case .yellow: "黄灯"
        case .red: "红灯"
        case .unknown: "无灯"
        }
    }

    var symbol: String {
        switch self {
        case .green: "circle.fill"
        case .yellow: "circle.lefthalf.filled"
        case .red: "circle"
        case .unknown: "questionmark.circle"
        }
    }
}

/// Price for one million tokens. Cache-hit input is kept separate because it is
/// the dominant cost lever for long agent sessions.
struct PricingTokenPrice: Equatable {
    let inputMiss: Double
    let inputHit: Double
    let output: Double
}

enum PricingTier: Equatable {
    case flat(PricingTokenPrice)
    case peakValley(peak: PricingTokenPrice, offPeak: PricingTokenPrice, ruleID: String)
}

enum PricingKind: String, Equatable {
    case peak
    case offPeak
    case flat
}

struct PricingModel: Identifiable, Equatable {
    let id: String
    let name: String
    /// Compact name for the Mini row where space is scarce.
    let shortName: String
    let vendor: String
    let channel: String
    let tier: PricingTier
    /// Caveat such as "≤32K 档" or "1M 上下文 / 支持图像".
    let note: String?
    let capability: String
    /// 评测能力分（0–100，与模型排行榜同源）；nil = 尚未标定。
    let capabilityScore: Double?
    let sourceURL: String?

    var isFlatPriced: Bool {
        if case .flat = tier { return true }
        return false
    }
}

struct PricingTimeRange: Equatable {
    /// Minutes from midnight, inclusive.
    let startMinute: Int
    /// Minutes from midnight, exclusive.
    let endMinute: Int

    init(startMinute: Int, endMinute: Int) {
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    init(start: String, end: String) {
        self.init(startMinute: Self.minutes(start), endMinute: Self.minutes(end))
    }

    func contains(minute: Int) -> Bool {
        guard endMinute > startMinute else { return false }
        return minute >= startMinute && minute < endMinute
    }

    var timeText: String {
        "\(Self.clock(startMinute))–\(Self.clock(endMinute))"
    }

    private static func minutes(_ text: String) -> Int {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }

}

/// Two rule shapes are enough for the verified 2026 data:
/// - weekday peak windows: outside the windows is the discounted period;
/// - daily discount windows: only inside the window is the price discounted
///   (used by WorkBuddy GLM-5.2 and 千问 Night Plan).
enum PricingRule: Equatable {
    case weekdayPeak(
        weekdays: Set<Int>,
        ranges: [PricingTimeRange],
        excludeHolidays: Bool,
        weekendOffPeak: Bool
    )
    case dailyDiscount(startMinute: Int, endMinute: Int)

    var label: String {
        switch self {
        case .weekdayPeak: "工作日高峰"
        case let .dailyDiscount(start, end):
            "\(PricingTimeRange.clock(start))–\(PricingTimeRange.clock(end))"
        }
    }
}

extension PricingTimeRange {
    static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }
}

/// Official holiday dates, stored as yyyyMMdd in Asia/Shanghai. Only dates that
/// still matter need to be present; an empty year means "not updated yet".
struct PricingHolidayCalendar: Equatable {
    var days: Set<Int>

    func contains(_ date: Date, calendar: Calendar) -> Bool {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else { return false }
        return days.contains(year * 10_000 + month * 100 + day)
    }

    func hasYear(_ year: Int) -> Bool {
        days.contains { $0 / 10_000 == year }
    }
}

/// A local-time price reference frame. It never fetches prices.
struct PricingTaskProfile: Equatable {
    var inputWeight: Double
    var outputWeight: Double
    /// 0 shows the "no cache" standard price; 0.8 approximates a long agent run.
    var cacheHitRatio: Double

    static let `default` = PricingTaskProfile(inputWeight: 5, outputWeight: 1, cacheHitRatio: 0)
}

struct PricingThresholds: Equatable {
    var greenMax: Double
    var redMin: Double
}

struct PricingChangeEvent: Identifiable, Equatable {
    let id: String
    let date: Date
    let title: String
    let detail: String
}

/// A channel that is billed in points or subscription quota rather than CNY.
/// It is displayed separately so points are never compared with cash as if they
/// were the same unit.
struct PricingChannelNote: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let discountLabel: String?
    let discount: Double?
    let ruleID: String?
    let note: String?
    let isSubscription: Bool
}

struct PricingCatalog: Equatable {
    let version: String
    /// 价格表最后一次人工核对的时间。
    let checkedAt: Date
    /// 免费额度最后一次人工复核的时间；nil = 与价格同时核对。
    let freeOffersCheckedAt: Date?
    let timeZone: TimeZone
    let models: [PricingModel]
    let rules: [String: PricingRule]
    let holidays: PricingHolidayCalendar
    let channels: [PricingChannelNote]
    let freeOffers: [PricingFreeOffer]
    let changes: [PricingChangeEvent]
    let profile: PricingTaskProfile
    let thresholds: PricingThresholds
    let sourceLine: String

    func rule(_ id: String?) -> PricingRule? {
        guard let id else { return nil }
        return rules[id]
    }

    func isStale(at date: Date) -> Bool {
        date.timeIntervalSince(checkedAt) > 30 * 86_400
    }
}

struct PricingTransition: Equatable {
    let date: Date
    /// True when the next change starts the cheap period.
    let becomesDiscounted: Bool
    let targetKind: PricingKind?
    /// "DeepSeek Flash 转峰时" / "折扣开始" — context is rendered by the caller.
    let context: String
    let label: String
}

struct PricingQuote: Identifiable, Equatable {
    let model: PricingModel
    let kind: PricingKind
    let currentPrice: PricingTokenPrice
    let mixedPrice: Double
    let light: PricingLight
    /// Current period price divided by the model's highest period price.
    let discountRatio: Double?
    let discountLabel: String?
    let tierLabel: String
    let nextTransition: PricingTransition?

    var id: String { model.id }
}

struct PricingChannelQuote: Identifiable, Equatable {
    let note: PricingChannelNote
    let rule: PricingRule?
    let isActive: Bool
    let nextTransition: PricingTransition?

    var id: String { note.id }

    var statusText: String {
        if note.isSubscription { return "订阅额度，无分时价" }
        if note.ruleID == nil { return "非分时折扣" }
        return isActive ? "现在生效" : "当前未开始"
    }
}

/// A model whose usage costs nothing inside a window or for a limited
/// activity, e.g. WorkBuddy Hy4 preview 夜间免费 (23:00–08:00 until 10/31).
/// Free is strictly better than any discount, so it leads the pricing row.
struct PricingFreeOffer: Identifiable, Equatable {
    let id: String
    let modelName: String
    /// Compact name for the Mini row where space is scarce.
    let shortName: String
    /// "夜间免费" / "限时免费" / "独家限免" — copied from the client badge.
    let badge: String
    /// nil = free around the clock while the activity runs.
    let ruleID: String?
    /// Activity start day (inclusive, Asia/Shanghai).
    let validFrom: Date?
    /// Activity last free day (inclusive, Asia/Shanghai).
    let validUntil: Date?
    /// 最近一次人工核实「该活动仍免费」的时间；nil = 沿用 catalog.checkedAt。
    /// 没有明确结束日期的限免活动超过核验窗口就转「待核对」，不再计入推荐。
    let verifiedAt: Date?
    let note: String?
    /// 评测能力分（0–100）；低于推荐门槛的免费模型只在价格页展示。
    let capabilityScore: Double?
}

/// One line of the Mini recommendation row: a free window or an active discount
/// on a model whose evaluated capability clears the floor. Discounts are ranked
/// by value (capability ÷ blended price), not by absolute price or saving, so
/// weak cheap models never take a slot.
struct PricingRecommendation: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case free
        case discount
        case upcomingFree
    }

    let id: String
    /// Compact model name for the Mini row.
    let name: String
    /// "免费 Step-5" / "5折 DeepSeek Pro" / "23:00 Hy4免费".
    let shortText: String
    /// Full sentence for help text and the pricing page.
    let detail: String
    let kind: Kind
    let capabilityScore: Double
}

struct PricingFreeOfferState: Identifiable, Equatable {
    let offer: PricingFreeOffer
    let isFreeNow: Bool
    /// 没有明确结束日期的限免活动是否还在核验窗口内；false = 数据可能已过期。
    let isVerified: Bool
    let nextTransition: PricingTransition?

    var id: String { offer.id }

    var statusText: String {
        if !isVerified { return "待核对" }
        if isFreeNow { return offer.ruleID == nil ? "全天免费" : "免费中" }
        return "当前未免费"
    }
}

struct PricingSnapshot: Equatable {
    let generatedAt: Date
    let catalogVersion: String
    let checkedAt: Date
    /// 免费额度最后一次人工复核的时间；nil = 与价格同时核对。
    let freeOffersCheckedAt: Date?
    let timeZone: TimeZone
    let profile: PricingTaskProfile
    let thresholds: PricingThresholds
    let quotes: [PricingQuote]
    let channels: [PricingChannelQuote]
    let freeOffers: [PricingFreeOfferState]
    /// Capability-gated free/discount picks for the Mini row, strongest first.
    let recommendations: [PricingRecommendation]
    let changes: [PricingChangeEvent]
    let nextTransition: PricingTransition?
    /// 能力达标模型中性价比最高的一条（能力分 ÷ 折算单价）；免费额度另由
    /// `recommendations` 优先。弱模型不会因为便宜而出现在这里。
    let bestValue: PricingQuote?
    let greenCount: Int
    let yellowCount: Int
    let redCount: Int
    let isStale: Bool
    let sourceLine: String

    var greenQuotes: [PricingQuote] { quotes.filter { $0.light == .green } }
}
