import Foundation

enum PricingSelfTest {
    static func check(into failures: inout [String]) {
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { failures.append("pricing: " + message) }
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
        }

        let catalog = PricingCatalog.builtIn
        let now = date(2026, 10, 23, 20, 50)
        guard let flash = catalog.models.first(where: { $0.id == PricingEngine.flashID }),
              let pro = catalog.models.first(where: { $0.id == "deepseek-v4-pro" }),
              let mini = catalog.models.first(where: { $0.id == "doubao-seed-2.0-mini" })
        else {
            failures.append("pricing: built-in catalog must contain flash, pro and doubao mini")
            return
        }

        // Weekday peak boundaries are half-open: 09:00 starts peak, 12:00 ends it.
        let flashStates: [(Date, PricingKind, Double)] = [
            (date(2026, 10, 26, 8, 59), .offPeak, 1.5),
            (date(2026, 10, 26, 9, 0), .peak, 3.0),
            (date(2026, 10, 26, 11, 59), .peak, 3.0),
            (date(2026, 10, 26, 12, 0), .offPeak, 1.5),
            (date(2026, 10, 26, 13, 59), .offPeak, 1.5),
            (date(2026, 10, 26, 14, 0), .peak, 3.0),
            (date(2026, 10, 26, 17, 59), .peak, 3.0),
            (date(2026, 10, 26, 18, 0), .offPeak, 1.5),
        ]
        for (moment, kind, mixed) in flashStates {
            let quote = PricingEngine.quote(for: flash, at: moment, catalog: catalog)
            expect(quote.kind == kind, "flash should be \(kind) at \(PricingFormatting.checkedAtText(moment))")
            expect(abs(quote.mixedPrice - mixed) < 0.0001, "flash mixed price at \(PricingFormatting.checkedAtText(moment))")
        }

        // Weekends, statutory holidays and make-up workday weekends are all off-peak.
        for weekend in [date(2026, 10, 24, 10, 0), date(2026, 10, 25, 10, 0), date(2026, 10, 10, 10, 0)] {
            let quote = PricingEngine.quote(for: flash, at: weekend, catalog: catalog)
            expect(quote.kind == .offPeak, "weekend must stay off-peak: \(PricingFormatting.checkedAtText(weekend))")
        }
        let holidayQuote = PricingEngine.quote(for: flash, at: date(2026, 10, 1, 10, 0), catalog: catalog)
        expect(holidayQuote.kind == .offPeak, "statutory holiday must be off-peak")
        expect(catalog.holidays.hasYear(2026) && !catalog.holidays.hasYear(2027), "only 2026 holiday fixtures are built in")

        // Monday 09:00 is the first change after a Friday evening; weekend is continuous.
        let fridayQuote = PricingEngine.quote(for: flash, at: now, catalog: catalog)
        expect(fridayQuote.kind == .offPeak && fridayQuote.light == .green, "Friday evening flash is green")
        expect(fridayQuote.discountLabel == "5折", "flash discount label is 5折")
        if let transition = fridayQuote.nextTransition {
            expect(transition.date == date(2026, 10, 26, 9, 0), "next flash change is Monday 09:00")
            expect(transition.becomesDiscounted == false && transition.targetKind == .peak, "Monday change turns peak")
            expect(PricingFormatting.countdownText(until: transition.date, now: now) == "2 天 12 小时",
                   "weekend countdown combines days and hours")
        } else {
            failures.append("pricing: Friday flash must expose a next transition")
        }
        let fridayPeak = date(2026, 10, 23, 17, 0)
        if let transition = PricingEngine.quote(for: flash, at: fridayPeak, catalog: catalog).nextTransition {
            expect(transition.date == date(2026, 10, 23, 18, 0), "Friday 17:00 waits only until 18:00")
            expect(transition.becomesDiscounted, "18:00 starts the discounted period")
        } else {
            failures.append("pricing: Friday 17:00 must expose the 18:00 transition")
        }

        // Red threshold is absolute: Pro is expensive even at 5折.
        let proOff = PricingEngine.quote(for: pro, at: now, catalog: catalog)
        let proPeak = PricingEngine.quote(for: pro, at: date(2026, 10, 26, 10, 0), catalog: catalog)
        expect(abs(proOff.mixedPrice - 6.0) < 0.0001 && proOff.light == .red, "Pro at off-peak is still red")
        expect(abs(proPeak.mixedPrice - 12.0) < 0.0001 && proPeak.light == .red, "Pro at peak is red")
        let miniQuote = PricingEngine.quote(for: mini, at: now, catalog: catalog)
        expect(miniQuote.kind == .flat && miniQuote.nextTransition == nil, "flat price has no transition")
        expect(abs(miniQuote.mixedPrice - 0.5) < 0.0001 && miniQuote.light == .green, "Mini is the cheapest green")
        expect(PricingFormatting.money(0.5) == "0.5" && PricingFormatting.money(0.04) == "0.04"
               && PricingFormatting.money(10) == "10", "money formatting trims zeros")

        // Snapshot order, counts and headline next change.
        let snapshot = PricingEngine.snapshot(at: now, catalog: catalog)
        expect(snapshot.quotes.count == catalog.models.count, "snapshot keeps every model")
        expect(snapshot.cheapest?.id == mini.id, "cheapest model is Doubao Mini even when deals lead the list")
        expect(snapshot.quotes.first?.id == flash.id, "off-peak models lead the price list")
        expect(snapshot.quotes.last?.id == "doubao-seed-2.1-pro", "normal expensive model stays last")
        let peakList = PricingEngine.snapshot(at: date(2026, 10, 26, 10, 0), catalog: catalog)
        expect(peakList.quotes.first?.id == mini.id, "with no active deal the list returns to pure price order")
        expect(peakList.cheapest?.id == mini.id, "cheapest stays absolute at weekday peak")
        expect(snapshot.greenCount == 4 && snapshot.yellowCount == 0 && snapshot.redCount == 2,
               "light counts at Friday 20:50 are 4/0/2")
        expect(snapshot.nextTransition?.date == date(2026, 10, 26, 9, 0), "snapshot headline uses the model transition")
        expect(!snapshot.isStale, "fresh catalog is not stale")
        expect(PricingEngine.snapshot(at: date(2026, 11, 25, 12, 0), catalog: catalog).isStale,
               "catalog older than 30 days is stale")
        expect(!PricingEngine.snapshot(at: date(2026, 11, 1, 12, 0), catalog: catalog).isStale,
               "catalog under 30 days is fresh")

        // Points / subscription channels carry their own discount and clock.
        func channel(_ id: String) -> PricingChannelQuote? {
            snapshot.channels.first { $0.id == id }
        }
        expect(channel("workbuddy-deepseek")?.isActive == true, "WorkBuddy DeepSeek discount is active at 20:50")
        expect(channel("workbuddy-deepseek")?.nextTransition?.date == date(2026, 10, 26, 9, 0),
               "WorkBuddy DeepSeek discount ends Monday 09:00")
        expect(channel("workbuddy-glm52")?.isActive == false, "GLM-5.2 night reduction starts at 23:00")
        expect(channel("workbuddy-glm52")?.nextTransition?.date == date(2026, 10, 23, 23, 0),
               "GLM-5.2 transition is today 23:00")
        expect(channel("qwen-night")?.isActive == false, "Qwen Night Plan is not active at 20:50")
        expect(channel("qwen-night")?.nextTransition?.date == date(2026, 10, 23, 22, 0),
               "Qwen Night Plan starts at 22:00")
        expect(channel("codex")?.statusText == "订阅额度，无分时价", "Codex is subscription-only")
        expect(channel("qwen-batch")?.statusText == "非分时折扣", "Batch discount is mode-based")
        let nightSnapshot = PricingEngine.snapshot(at: date(2026, 10, 23, 23, 30), catalog: catalog)
        expect(nightSnapshot.channels.first { $0.id == "workbuddy-glm52" }?.isActive == true,
               "GLM-5.2 is active at 23:30")
        expect(nightSnapshot.channels.first { $0.id == "qwen-night" }?.isActive == true,
               "Qwen Night Plan is active at 23:30")
        let morningSnapshot = PricingEngine.snapshot(at: date(2026, 10, 24, 8, 0), catalog: catalog)
        expect(morningSnapshot.channels.first { $0.id == "qwen-night" }?.isActive == false,
               "Qwen Night Plan ends at 08:00")

        // Price-change calendar only shows changes that have not fully passed.
        expect(snapshot.changes.contains { $0.id == "deepseek-search-fetch" },
               "November search/fetch billing is listed")
        expect(PricingEngine.snapshot(at: date(2026, 12, 1, 12, 0), catalog: catalog)
            .changes.contains { $0.id == "deepseek-search-fetch" } == false,
               "past price changes disappear")

        // Row height: pricing adds exactly one 22 pt row at every scale.
        for size in CompactPanelSize.allCases {
            let base = EnergyPanelLayout.size(for: .compact, compactSize: size)
            let pricing = EnergyPanelLayout.size(for: .compact, compactSize: size, showsPricing: true)
            let both = EnergyPanelLayout.size(for: .compact, compactSize: size, showsCountdown: true, showsPricing: true)
            expect(abs(pricing.height - base.height - 22 * size.scale) < 0.01,
                   "pricing row adds one row at \(size.rawValue)")
            expect(abs(both.height - pricing.height - 22 * size.scale) < 0.01,
                   "countdown still adds one row with pricing at \(size.rawValue)")
            expect(pricing.width == base.width, "pricing row never changes compact width")
        }
    }
}
