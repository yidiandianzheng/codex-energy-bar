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
        expect(abs(miniQuote.mixedPrice - 0.5) < 0.0001 && miniQuote.light == .green, "Mini has the lowest raw price (but is below the recommendation floor)")
        expect(PricingFormatting.money(0.5) == "0.5" && PricingFormatting.money(0.04) == "0.04"
               && PricingFormatting.money(10) == "10", "money formatting trims zeros")

        // Snapshot order, counts and headline next change.
        let snapshot = PricingEngine.snapshot(at: now, catalog: catalog)
        expect(snapshot.quotes.count == catalog.models.count, "snapshot keeps every model")
        expect(snapshot.bestValue?.id == flash.id, "best value is DeepSeek Flash; cheap-but-weak Mini never wins")
        expect((snapshot.bestValue?.model.capabilityScore ?? 0) >= PricingEngine.capabilityFloor,
               "best value always clears the capability floor")
        expect(PricingEngine.valueScore(of: miniQuote) == nil,
               "Mini is below the floor and cannot be scored as a recommendation")
        expect(snapshot.quotes.first?.id == flash.id, "off-peak models lead the price list")
        expect(snapshot.quotes.last?.id == "doubao-seed-2.1-pro", "normal expensive model stays last")
        let peakList = PricingEngine.snapshot(at: date(2026, 10, 26, 10, 0), catalog: catalog)
        expect(peakList.quotes.first?.id == mini.id, "with no active deal the list returns to pure price order")
        expect(peakList.bestValue?.id == flash.id, "best value stays DeepSeek Flash at weekday peak")
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

        // Free-model windows: Hy4 夜间免费 23:00–08:00 until 10/31 is the only
        // built-in free offer. Step-5 and Hy3 were removed on 2026-10-28 after
        // both went back to paid. The 3-day verification window is exercised
        // below with a custom open-ended offer, because no built-in offer is
        // open-ended anymore.
        func freeState(_ id: String, at moment: Date) -> PricingFreeOfferState? {
            PricingEngine.snapshot(at: moment, catalog: catalog).freeOffers.first { $0.id == id }
        }
        let evening = date(2026, 10, 23, 20, 50)
        let hy4Evening = freeState("workbuddy-hy4-night", at: evening)
        expect(hy4Evening?.isFreeNow == false, "Hy4 is paid before 23:00")
        expect(hy4Evening?.nextTransition?.date == date(2026, 10, 23, 23, 0),
               "Hy4 free window starts tonight at 23:00")
        expect(hy4Evening?.nextTransition?.label == "免费开始", "Hy4 transition label is 免费开始")
        let hy4Night = freeState("workbuddy-hy4-night", at: date(2026, 10, 23, 23, 30))
        expect(hy4Night?.isFreeNow == true, "Hy4 is free at 23:30")
        expect(hy4Night?.nextTransition?.date == date(2026, 10, 24, 8, 0),
               "Hy4 free window ends next morning at 08:00")
        expect(hy4Night?.nextTransition?.label == "免费结束", "Hy4 transition label is 免费结束")
        expect(freeState("workbuddy-hy4-night", at: date(2026, 10, 24, 8, 0))?.isFreeNow == false,
               "the free window is half-open: 08:00 is paid again")
        expect(freeState("workbuddy-hy4-night", at: date(2026, 10, 31, 23, 30))?.isFreeNow == true,
               "10/31 night is still inside the activity")
        let hy4Expired = freeState("workbuddy-hy4-night", at: date(2026, 11, 2, 12, 0))
        expect(hy4Expired?.isFreeNow == false && hy4Expired?.nextTransition == nil,
               "after 10/31 the Hy4 activity is over and has no countdown")
        expect(freeState("workbuddy-hy3-limited", at: evening) == nil,
               "Hy3 is no longer a free offer after the 2026-10-28 correction")
        expect(freeState("workbuddy-step5-limited", at: evening) == nil,
               "Step-5 is no longer a free offer after the 2026-10-28 correction")
        let freeSnapshot = PricingEngine.snapshot(at: evening, catalog: catalog)
        expect(freeSnapshot.freeOffers.count == 1, "only Hy4 remains as a built-in free offer")
        expect((freeSnapshot.freeOffersCheckedAt ?? .distantPast) > freeSnapshot.checkedAt,
               "free offers were rechecked after the price table date")

        // 3-day verification window: an open-ended offer is trusted only while
        // its last manual check is fresh; stale data must never be recommended.
        let ttlOffer = PricingFreeOffer(
            id: "test-open-ended",
            modelName: "Test Open Ended",
            shortName: "Test",
            badge: "限时免费",
            ruleID: nil,
            validFrom: nil,
            validUntil: nil,
            verifiedAt: catalog.checkedAt,
            note: nil,
            capabilityScore: 95
        )
        let ttlCatalog = PricingCatalog(
            version: "test",
            checkedAt: catalog.checkedAt,
            freeOffersCheckedAt: nil,
            timeZone: catalog.timeZone,
            models: catalog.models,
            rules: catalog.rules,
            holidays: catalog.holidays,
            channels: catalog.channels,
            freeOffers: [ttlOffer],
            changes: catalog.changes,
            profile: catalog.profile,
            thresholds: catalog.thresholds,
            sourceLine: "test"
        )
        let ttlFresh = PricingEngine.snapshot(at: date(2026, 10, 26, 12, 0), catalog: ttlCatalog).freeOffers.first
        expect(ttlFresh?.isVerified == true && ttlFresh?.isFreeNow == true,
               "open-ended offer stays free inside the 3-day verification window")
        let ttlStaleSnapshot = PricingEngine.snapshot(at: date(2026, 10, 28, 12, 0), catalog: ttlCatalog)
        let ttlStale = ttlStaleSnapshot.freeOffers.first
        expect(ttlStale?.isVerified == false && ttlStale?.isFreeNow == false,
               "open-ended offer becomes unverified after 3 days without re-check")
        expect(ttlStale?.statusText == "待核对", "unverified free offers say 待核对")
        expect(!ttlStaleSnapshot.recommendations.contains { $0.id == "free:test-open-ended" },
               "unverified free offers never enter the Mini row")
        let eveningPicks = freeSnapshot.recommendations
        expect(eveningPicks.map(\.id) == [
            "discount:deepseek-flash",
            "discount:deepseek-v4-pro",
            "upcoming:workbuddy-hy4-night",
        ], "evening: no free pick; discounts by value, then the upcoming Hy4 window")
        expect(!eveningPicks.contains { $0.name == "豆包 Mini" },
               "the cheap-but-weak Doubao Mini never takes a recommendation slot")
        expect(eveningPicks.allSatisfy { $0.capabilityScore >= PricingEngine.capabilityFloor },
               "every recommendation clears the capability floor")
        expect(eveningPicks.first?.shortText == "5折 DeepSeek Flash", "discount pick text carries the deal")
        expect(eveningPicks[1].shortText == "5折 DeepSeek Pro", "second pick is the next value discount")
        let freeNightSnapshot = PricingEngine.snapshot(at: date(2026, 10, 23, 23, 30), catalog: catalog)
        expect(freeNightSnapshot.recommendations.prefix(2).map(\.id) == [
            "free:workbuddy-hy4-night",
            "discount:deepseek-flash",
        ], "at night the strong Hy4 free window leads, then value discounts")
        let peakWithUpcoming = PricingEngine.snapshot(at: date(2026, 10, 26, 11, 30), catalog: catalog)
        expect(peakWithUpcoming.recommendations.map(\.id) == [
            "upcoming:workbuddy-hy4-night",
        ], "only the upcoming Hy4 window fills a slot; Step-5 and Hy3 are gone")
        expect(peakWithUpcoming.recommendations.last?.shortText == "23:00 Hy4免费",
               "upcoming pick shows the start time")

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
