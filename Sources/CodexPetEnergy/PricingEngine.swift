import Foundation

enum PricingFormatting {
    static let shanghai = TimeZone(identifier: "Asia/Shanghai") ?? .current

    static func money(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        let absValue = abs(value)
        if absValue >= 10 {
            return String(format: "%.0f", value)
        }
        if absValue >= 1 {
            return trim(String(format: "%.1f", value))
        }
        return trim(String(format: "%.2f", value))
    }

    static func mixedPriceText(_ value: Double) -> String {
        "¥\(money(value))/M"
    }

    static func tokenPriceText(_ price: PricingTokenPrice) -> String {
        "输入 ¥\(money(price.inputMiss)) · 缓存 ¥\(money(price.inputHit)) · 输出 ¥\(money(price.output))"
    }

    static func discountText(_ ratio: Double) -> String {
        let zhe = ratio * 10
        if abs(zhe - zhe.rounded()) < 0.01 {
            return "\(Int(zhe.rounded()))折"
        }
        return trim(String(format: "%.1f", zhe)) + "折"
    }

    static func countdownText(until date: Date, now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now).rounded()))
        if seconds < 60 { return "不到 1 分钟" }
        if seconds < 3_600 { return "\(seconds / 60) 分钟" }
        if seconds < 86_400 {
            let hours = seconds / 3_600
            let minutes = (seconds % 3_600) / 60
            return minutes == 0 ? "\(hours) 小时" : "\(hours) 小时 \(minutes) 分"
        }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        return hours == 0 ? "\(days) 天" : "\(days) 天 \(hours) 小时"
    }

    static func relativeMoment(_ date: Date, now: Date, timeZone: TimeZone = shanghai) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        if calendar.isDate(date, inSameDayAs: now) {
            formatter.dateFormat = "HH:mm"
            return "今天 \(formatter.string(from: date))"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            formatter.dateFormat = "HH:mm"
            return "明天 \(formatter.string(from: date))"
        }
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: date)
        if (2...6).contains(days) {
            let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
            let weekday = calendar.component(.weekday, from: date)
            return "\(weekdays[max(0, min(6, weekday - 1))]) \(time)"
        }
        formatter.dateFormat = "M月d日"
        return "\(formatter.string(from: date)) \(time)"
    }

    static func transitionText(_ transition: PricingTransition, now: Date, timeZone: TimeZone = shanghai) -> String {
        "\(relativeMoment(transition.date, now: now, timeZone: timeZone)) \(transition.label) · \(countdownText(until: transition.date, now: now))"
    }

    static func checkedAtText(_ date: Date, timeZone: TimeZone = shanghai) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    static func shortDateText(_ date: Date, timeZone: TimeZone = shanghai) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }

    static func profileText(_ profile: PricingTaskProfile) -> String {
        "输入\(detailNumber(profile.inputWeight)) : 输出\(detailNumber(profile.outputWeight))"
    }

    static func scheduleText(for rule: PricingRule?, timeZone: TimeZone = shanghai) -> String {
        guard let rule else { return "常态价，无分时折扣" }
        switch rule {
        case let .weekdayPeak(_, ranges, _, _):
            let windows = ranges.map(\.timeText).joined(separator: "、")
            return "工作日 \(windows) 峰时；其余时段、周末及法定节假日全天谷时"
        case let .dailyDiscount(start, end):
            return "每天 \(PricingTimeRange.clock(start))–\(PricingTimeRange.clock(end)) 折扣；其余时间原价"
        }
    }

    private static func detailNumber(_ value: Double) -> String {
        if abs(value - value.rounded()) < 0.001 {
            return String(Int(value.rounded()))
        }
        return trim(String(format: "%.1f", value))
    }

    private static func trim(_ text: String) -> String {
        guard text.contains(".") else { return text }
        var value = text
        while value.hasSuffix("0") { value.removeLast() }
        if value.hasSuffix(".") { value.removeLast() }
        return value
    }
}

enum PricingEngine {
    static let flashID = "deepseek-flash"

    static func snapshot(at date: Date, catalog: PricingCatalog = .builtIn) -> PricingSnapshot {
        let quotes = catalog.models
            .map { quote(for: $0, at: date, catalog: catalog) }
            .sorted { lhs, rhs in
                // Active activity prices lead the list; inside each group the
                // absolute mixed price still decides the order.
                let lhsDeal = lhs.kind == .offPeak
                let rhsDeal = rhs.kind == .offPeak
                if lhsDeal != rhsDeal { return lhsDeal }
                if abs(lhs.mixedPrice - rhs.mixedPrice) > 0.0001 { return lhs.mixedPrice < rhs.mixedPrice }
                return lhs.model.name < rhs.model.name
            }
        let channels = catalog.channels.map { channelQuote(for: $0, at: date, catalog: catalog) }
        // The headline "next change" is about model prices; each points/subscription
        // channel carries its own transition in its row.
        let nextTransition = quotes.compactMap(\.nextTransition).min { $0.date < $1.date }
        let changes = catalog.changes
            .filter { $0.date.timeIntervalSince(date) > -3_600 }
            .sorted { $0.date < $1.date }
        return PricingSnapshot(
            generatedAt: date,
            catalogVersion: catalog.version,
            checkedAt: catalog.checkedAt,
            timeZone: catalog.timeZone,
            profile: catalog.profile,
            thresholds: catalog.thresholds,
            quotes: quotes,
            channels: channels,
            changes: changes,
            nextTransition: nextTransition,
            cheapest: quotes.min { $0.mixedPrice < $1.mixedPrice },
            greenCount: quotes.filter { $0.light == .green }.count,
            yellowCount: quotes.filter { $0.light == .yellow }.count,
            redCount: quotes.filter { $0.light == .red }.count,
            isStale: catalog.isStale(at: date),
            sourceLine: catalog.sourceLine
        )
    }

    static func quote(for model: PricingModel, at date: Date, catalog: PricingCatalog) -> PricingQuote {
        switch model.tier {
        case let .flat(price):
            let mixed = mixedPrice(price, profile: catalog.profile)
            return PricingQuote(
                model: model,
                kind: .flat,
                currentPrice: price,
                mixedPrice: mixed,
                light: light(for: mixed, thresholds: catalog.thresholds),
                discountRatio: nil,
                discountLabel: nil,
                tierLabel: "常态价",
                nextTransition: nil
            )
        case let .peakValley(peak, offPeak, ruleID):
            let rule = catalog.rule(ruleID)
            let isPeakNow = rule.map { isPeak(at: date, rule: $0, catalog: catalog) } ?? false
            let price = isPeakNow ? peak : offPeak
            let mixed = mixedPrice(price, profile: catalog.profile)
            let ratio = discountRatio(peak: peak, offPeak: offPeak)
            let discountLabel = ratio.map(PricingFormatting.discountText)
            let tierLabel = isPeakNow ? "峰时原价" : "谷时 \(discountLabel ?? "折扣")"
            return PricingQuote(
                model: model,
                kind: isPeakNow ? .peak : .offPeak,
                currentPrice: price,
                mixedPrice: mixed,
                light: light(for: mixed, thresholds: catalog.thresholds),
                discountRatio: ratio,
                discountLabel: discountLabel,
                tierLabel: tierLabel,
                nextTransition: nextModelTransition(after: date, model: model, catalog: catalog)
            )
        }
    }

    static func channelQuote(for note: PricingChannelNote, at date: Date, catalog: PricingCatalog) -> PricingChannelQuote {
        guard let rule = catalog.rule(note.ruleID) else {
            return PricingChannelQuote(note: note, rule: nil, isActive: false, nextTransition: nil)
        }
        return PricingChannelQuote(
            note: note,
            rule: rule,
            isActive: isDiscountActive(at: date, rule: rule, catalog: catalog),
            nextTransition: nextChannelTransition(after: date, note: note, rule: rule, catalog: catalog)
        )
    }

    /// True only for weekday peak rules. Daily discount rules never define a
    /// peak product tier in this catalog.
    static func isPeak(at date: Date, rule: PricingRule, catalog: PricingCatalog) -> Bool {
        guard case let .weekdayPeak(weekdays, ranges, excludeHolidays, weekendOffPeak) = rule else {
            return false
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = catalog.timeZone
        if excludeHolidays, catalog.holidays.contains(date, calendar: calendar) {
            return false
        }
        let weekday = calendar.component(.weekday, from: date)
        if weekendOffPeak, weekday == 1 || weekday == 7 {
            return false
        }
        guard weekdays.contains(weekday) else { return false }
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        return ranges.contains { $0.contains(minute: minute) }
    }

    static func isDiscountActive(at date: Date, rule: PricingRule, catalog: PricingCatalog) -> Bool {
        switch rule {
        case .weekdayPeak:
            return !isPeak(at: date, rule: rule, catalog: catalog)
        case let .dailyDiscount(start, end):
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = catalog.timeZone
            let components = calendar.dateComponents([.hour, .minute], from: date)
            let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            if start < end {
                return minute >= start && minute < end
            }
            if start > end {
                return minute >= start || minute < end
            }
            return false
        }
    }

    static func mixedPrice(_ price: PricingTokenPrice, profile: PricingTaskProfile) -> Double {
        let weightSum = profile.inputWeight + profile.outputWeight
        guard weightSum > 0 else { return price.output }
        let ratio = min(max(profile.cacheHitRatio, 0), 1)
        let effectiveInput = price.inputHit * ratio + price.inputMiss * (1 - ratio)
        return (profile.inputWeight * effectiveInput + profile.outputWeight * price.output) / weightSum
    }

    static func light(for mixedPrice: Double, thresholds: PricingThresholds) -> PricingLight {
        guard mixedPrice.isFinite else { return .unknown }
        if mixedPrice <= thresholds.greenMax { return .green }
        if mixedPrice >= thresholds.redMin { return .red }
        return .yellow
    }

    static func nextModelTransition(after date: Date, model: PricingModel, catalog: PricingCatalog) -> PricingTransition? {
        guard case let .peakValley(_, _, ruleID) = model.tier,
              let rule = catalog.rule(ruleID),
              case .weekdayPeak = rule
        else { return nil }
        let currentDiscount = isDiscountActive(at: date, rule: rule, catalog: catalog)
        guard let candidate = firstChangeDate(after: date, rule: rule, catalog: catalog, currentState: currentDiscount) else {
            return nil
        }
        let targetDiscount = isDiscountActive(at: candidate, rule: rule, catalog: catalog)
        let targetPeak = !targetDiscount
        let label = targetPeak ? "转峰时" : "转谷时"
        return PricingTransition(
            date: candidate,
            becomesDiscounted: targetDiscount,
            targetKind: targetPeak ? .peak : .offPeak,
            context: "\(model.name) \(label)",
            label: label
        )
    }

    static func nextChannelTransition(after date: Date, note: PricingChannelNote, rule: PricingRule, catalog: PricingCatalog) -> PricingTransition? {
        let currentActive = isDiscountActive(at: date, rule: rule, catalog: catalog)
        guard let candidate = firstChangeDate(after: date, rule: rule, catalog: catalog, currentState: currentActive) else {
            return nil
        }
        let targetActive = isDiscountActive(at: candidate, rule: rule, catalog: catalog)
        let label = targetActive ? "折扣开始" : "折扣结束"
        return PricingTransition(
            date: candidate,
            becomesDiscounted: targetActive,
            targetKind: nil,
            context: "\(note.title) \(label)",
            label: label
        )
    }

    /// Walks the rule's own boundaries for the next ten days; no minute-by-minute
    /// scan, so a 15-second UI tick stays cheap.
    static func firstChangeDate(
        after date: Date,
        rule: PricingRule,
        catalog: PricingCatalog,
        currentState: Bool
    ) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = catalog.timeZone
        let dayStart = calendar.startOfDay(for: date)
        let boundaries = boundaryMinutes(for: rule)
        for offset in 0...10 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: dayStart) else { continue }
            for minute in boundaries {
                guard let candidate = calendar.date(byAdding: .minute, value: minute, to: day), candidate > date else { continue }
                guard state(at: candidate, rule: rule, catalog: catalog) != currentState else { continue }
                return candidate
            }
        }
        return nil
    }

    /// State domain for transitions is always "discount active", so peak rules
    /// (outside = discount) and daily discount windows share one comparison.
    private static func state(at date: Date, rule: PricingRule, catalog: PricingCatalog) -> Bool {
        isDiscountActive(at: date, rule: rule, catalog: catalog)
    }

    private static func boundaryMinutes(for rule: PricingRule) -> [Int] {
        switch rule {
        case let .weekdayPeak(_, ranges, _, _):
            let values = [0] + ranges.flatMap { [$0.startMinute, $0.endMinute] }
            return Array(Set(values)).sorted()
        case let .dailyDiscount(start, end):
            return Array(Set([start, end])).sorted()
        }
    }

    /// Intraday discount ratio, derived from the input-miss prices.
    static func discountRatio(peak: PricingTokenPrice, offPeak: PricingTokenPrice) -> Double? {
        guard peak.inputMiss > 0, offPeak.inputMiss > 0 else { return nil }
        let ratio = offPeak.inputMiss / peak.inputMiss
        guard ratio > 0, ratio <= 1 else { return nil }
        return ratio
    }
}
