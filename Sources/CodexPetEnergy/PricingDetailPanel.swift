import SwiftUI

/// Expanded cost-light page: absolute price tiers, discount wording and the
/// next price change for every model/channel. It is opened from the Mini row
/// and is not a fifth tab.
struct PricingDetailPanel: View {
    let snapshot: PricingSnapshot
    let now: Date
    let back: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                summary
                freeSection
                modelSection
                channelSection
                calendarSection
                footer
            }
            .padding(.horizontal, EnergyVisualStyle.panelInset)
            .padding(.bottom, 18)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Button(action: back) {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(EnergyTypography.Icon.compact)
                        Text("总览")
                            .font(EnergyTypography.Detail.caption)
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回总览")
                Spacer(minLength: 0)
                Text(checkedAtText)
                    .font(EnergyTypography.Detail.caption)
                    .foregroundStyle(snapshot.isStale ? EnergyVisualStyle.warningAccent : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text("省钱灯").font(EnergyTypography.Detail.title)
            Text("灯色看此刻贵不贵；每行都写明当前打几折、下次何时变价。")
                .font(EnergyTypography.Detail.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// 价格与免费额度可能在不同日期复核；分别显示，避免「还是 10/24」的误会。
    private var checkedAtText: String {
        let price = PricingFormatting.shortDateText(snapshot.checkedAt, timeZone: snapshot.timeZone)
        guard !snapshot.isStale else { return "价格待核对" }
        guard let free = snapshot.freeOffersCheckedAt else { return "核对 \(price)" }
        let freeText = PricingFormatting.shortDateText(free, timeZone: snapshot.timeZone)
        guard freeText != price else { return "核对 \(price)" }
        return "价格 \(price) · 免费 \(freeText)"
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 13) {
                lightCount(.green, count: snapshot.greenCount)
                lightCount(.yellow, count: snapshot.yellowCount)
                lightCount(.red, count: snapshot.redCount)
                Spacer(minLength: 4)
                if let pick = summaryPickText {
                    Text(pick)
                        .font(EnergyTypography.Detail.chip)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(EnergyTypography.Icon.compact)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(nextChangeText)
                    .font(EnergyTypography.Detail.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .energyCardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("价格灯概览")
        .accessibilityValue(accessibilitySummary)
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("模型价格（活动价优先）", caption: "正在打折的模型排前面，同组按折算价排序；圆点=成本灯（绿省 / 黄中 / 红贵），橙色=活动折扣价，灰色=常态价或原价；每行先标能力分，标「推荐」= 能力达标的优惠，推荐位按性价比排序")
            ForEach(snapshot.quotes) { quote in
                quoteRow(quote)
                if quote.id != snapshot.quotes.last?.id {
                    Divider().overlay(EnergyVisualStyle.hairline)
                }
            }
        }
    }

    private var channelSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("积分 / 订阅渠道", caption: "不与人民币混排；只显示各自的分时折扣")
            ForEach(snapshot.channels) { channel in
                channelRow(channel)
                if channel.id != snapshot.channels.last?.id {
                    Divider().overlay(EnergyVisualStyle.hairline)
                }
            }
        }
    }

    private var freeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("免费额度", caption: "0 倍率模型与限免活动；免费时段内不消耗积分，优先于任何折扣。能力 ≥\(PricingEngine.capabilityText(PricingEngine.capabilityFloor)) 的强模型才进入推荐；付费推荐按性价比（能力 ÷ 折算价）排序。没有明确结束日期的限免活动超过 \(PricingEngine.freeOfferVerificationDays) 天未复核会标「待核对」，不再计入推荐")
            if snapshot.freeOffers.isEmpty {
                Text("当前没有已知的免费模型活动。")
                    .font(EnergyTypography.Detail.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(snapshot.freeOffers) { state in
                    freeRow(state)
                    if state.id != snapshot.freeOffers.last?.id {
                        Divider().overlay(EnergyVisualStyle.hairline)
                    }
                }
            }
        }
    }

    private func freeRow(_ state: PricingFreeOfferState) -> some View {
        let offer = state.offer
        let dealTint = PricingLightStyle.channelDealTint()
        let statusTint = state.isVerified
            ? PricingLightStyle.channelStatusTint(isActive: state.isFreeNow)
            : EnergyVisualStyle.warningAccent
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(offer.modelName)
                    .font(EnergyTypography.Detail.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(offer.badge)
                    .font(EnergyTypography.Detail.chip)
                    .foregroundStyle(dealTint)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(dealTint.opacity(0.13), in: Capsule())
                    .fixedSize()
                if isRecommendedFree(state) {
                    recommendationChip()
                }
                Spacer(minLength: 4)
                Text(state.isVerified ? (state.isFreeNow ? "0 倍率" : "当前未免费") : "待核对")
                    .font(EnergyTypography.Detail.caption)
                    .foregroundStyle(statusTint)
                    .lineLimit(1)
                    .fixedSize()
            }
            Text(offer.note ?? "")
                .font(EnergyTypography.Detail.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text(capabilityMeta(offer.capabilityScore))
                Text(validityText(state))
                if let transition = state.nextTransition {
                    Text(PricingFormatting.transitionText(transition, now: now, timeZone: snapshot.timeZone))
                }
            }
            .font(EnergyTypography.Detail.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(offer.modelName)，\(offer.badge)，\(state.statusText)")
        .accessibilityValue(state.nextTransition.map {
            PricingFormatting.transitionText($0, now: now, timeZone: snapshot.timeZone)
        } ?? "")
    }

    private func isRecommendedFree(_ state: PricingFreeOfferState) -> Bool {
        snapshot.recommendations.contains { $0.id == "free:" + state.id }
    }

    private func isRecommendedDiscount(_ quote: PricingQuote) -> Bool {
        quote.kind == .offPeak && snapshot.recommendations.contains { $0.id == "discount:" + quote.id }
    }

    private func capabilityMeta(_ score: Double?) -> String {
        guard let score else { return "能力待标定" }
        let text = PricingEngine.capabilityText(score)
        return score >= PricingEngine.capabilityFloor ? "能力 \(text) · 达标" : "能力 \(text) · 未达标"
    }

    private func recommendationChip() -> some View {
        Text("推荐")
            .font(EnergyTypography.Detail.chip)
            .foregroundStyle(EnergyVisualStyle.pricingDeal)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(EnergyVisualStyle.pricingDeal.opacity(0.13), in: Capsule())
            .fixedSize()
    }

    private func validityText(_ state: PricingFreeOfferState) -> String {
        let offer = state.offer
        guard state.isVerified else { return "免费状态待核对" }
        switch (offer.validFrom, offer.validUntil) {
        case let (from?, until?):
            return "\(PricingFormatting.shortDateText(from, timeZone: snapshot.timeZone))–\(PricingFormatting.shortDateText(until, timeZone: snapshot.timeZone))"
        case let (from?, nil):
            return "\(PricingFormatting.shortDateText(from, timeZone: snapshot.timeZone)) 起"
        case let (nil, until?):
            return "至 \(PricingFormatting.shortDateText(until, timeZone: snapshot.timeZone))"
        default:
            return offer.ruleID == nil ? "全天免费" : "分时免费"
        }
    }

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("价格日历", caption: "已知的生效节点")
            if snapshot.changes.isEmpty {
                Text("近期没有已知的价格变更。")
                    .font(EnergyTypography.Detail.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(snapshot.changes) { event in
                    HStack(alignment: .top, spacing: 8) {
                        Text(PricingFormatting.shortDateText(event.date, timeZone: snapshot.timeZone))
                            .font(EnergyTypography.Detail.chip)
                            .foregroundStyle(.primary)
                            .frame(width: 38, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .font(EnergyTypography.Detail.label)
                                .lineLimit(2)
                            Text(event.detail)
                                .font(EnergyTypography.Detail.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 5)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 5) {
            Divider().overlay(EnergyVisualStyle.hairline)
            Text("按 \(PricingFormatting.profileText(snapshot.profile)) 折算，缓存命中 0% 的标准价。只读本地价格，不改变任何账户。")
                .font(EnergyTypography.Detail.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("DeepSeek 时段：工作日 09:00–12:00、14:00–18:00 为峰时；其余时段、周末、法定节假日及调休上班的周末全天为谷时（5 折）。")
                .font(EnergyTypography.Detail.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(snapshot.sourceLine)
                .font(EnergyTypography.Detail.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("急事不要为了省灯延误；返工成本通常高于 Token 差价。灯色只反映价格，能力分来自公开评测；推荐位已按能力门槛过滤，不会把便宜但更弱的模型推上来。")
                .font(EnergyTypography.Detail.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if snapshot.isStale {
                Text("价格数据已超过 30 天未核对，请打开官方价格页确认后再依赖灯色。")
                    .font(EnergyTypography.Detail.caption)
                    .foregroundStyle(EnergyVisualStyle.warningAccent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sectionHeader(_ title: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(EnergyTypography.Detail.section)
            Text(caption).font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func quoteRow(_ quote: PricingQuote) -> some View {
        let lightColor = PricingLightStyle.color(for: quote.light)
        let chipTint = PricingLightStyle.tierChipTint(for: quote)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: quote.light.symbol)
                    .font(EnergyTypography.Detail.chip)
                    .foregroundStyle(lightColor)
                    .accessibilityHidden(true)
                Text(quote.model.name)
                    .font(EnergyTypography.Detail.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(quote.tierLabel)
                    .font(EnergyTypography.Detail.chip)
                    .foregroundStyle(chipTint)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(PricingLightStyle.tierChipFill(for: quote), in: Capsule())
                    .fixedSize()
                if isRecommendedDiscount(quote) {
                    recommendationChip()
                }
                Spacer(minLength: 4)
                Text(PricingFormatting.mixedPriceText(quote.mixedPrice))
                    .font(EnergyTypography.Detail.rowValue)
                    .foregroundStyle(.primary)
                    .fixedSize()
            }
            Text("\(quote.model.channel) · \(PricingFormatting.tokenPriceText(quote.currentPrice))")
                .font(EnergyTypography.Detail.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(detailLine(for: quote))
                .font(EnergyTypography.Detail.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(quote.model.name)，\(quote.tierLabel)，折算 \(PricingFormatting.mixedPriceText(quote.mixedPrice))")
        .accessibilityValue(detailLine(for: quote))
    }

    private func channelRow(_ channel: PricingChannelQuote) -> some View {
        let dealTint = PricingLightStyle.channelDealTint()
        let statusTint = PricingLightStyle.channelStatusTint(isActive: channel.isActive)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(channel.note.title)
                    .font(EnergyTypography.Detail.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if let label = channel.note.discountLabel {
                    Text(label)
                        .font(EnergyTypography.Detail.chip)
                        .foregroundStyle(dealTint)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(dealTint.opacity(0.13), in: Capsule())
                        .fixedSize()
                }
                Spacer(minLength: 4)
                Text(channel.statusText)
                    .font(EnergyTypography.Detail.caption)
                    .foregroundStyle(statusTint)
                    .lineLimit(1)
                    .fixedSize()
            }
            Text(channel.note.detail + (channel.note.note.map { " · \($0)" } ?? ""))
                .font(EnergyTypography.Detail.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let transition = channel.nextTransition, channel.note.ruleID != nil {
                Text(PricingFormatting.transitionText(transition, now: now, timeZone: snapshot.timeZone))
                    .font(EnergyTypography.Detail.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(channel.note.title)，\(channel.note.detail)，\(channel.statusText)")
        .accessibilityValue(channel.nextTransition.map {
            PricingFormatting.transitionText($0, now: now, timeZone: snapshot.timeZone)
        } ?? "")
    }

    private func detailLine(for quote: PricingQuote) -> String {
        let capability = capabilityMeta(quote.model.capabilityScore)
        if quote.model.isFlatPriced {
            let note = quote.model.note.map { " · \($0)" } ?? ""
            return "\(capability) · 无分时折扣\(note)"
        }
        guard let transition = quote.nextTransition else {
            return "\(capability) · 工作日高峰外为谷时；周末及法定节假日全天谷时"
        }
        let next = PricingFormatting.transitionText(transition, now: now, timeZone: snapshot.timeZone)
        if quote.kind == .peak, let discount = quote.discountLabel {
            return "\(capability) · 谷时 \(discount) · \(next)"
        }
        return "\(capability) · \(next)"
    }

    private func lightCount(_ light: PricingLight, count: Int) -> some View {
        HStack(spacing: 3) {
            Image(systemName: light.symbol)
                .font(EnergyTypography.Icon.compact)
                .foregroundStyle(PricingLightStyle.color(for: light))
                .accessibilityHidden(true)
            Text("\(count) \(light.title)")
                .font(EnergyTypography.Detail.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var nextChangeText: String {
        let deepSeek = snapshot.quotes.first { $0.id == PricingEngine.flashID }
        let headline: String
        if let deepSeek {
            headline = "DeepSeek Flash：\(deepSeek.tierLabel) \(PricingFormatting.mixedPriceText(deepSeek.mixedPrice))"
        } else {
            headline = "模型价格"
        }
        guard let transition = snapshot.nextTransition else {
            return "\(headline)；近期没有模型分时变价。"
        }
        let moment = PricingFormatting.relativeMoment(transition.date, now: now, timeZone: snapshot.timeZone)
        let countdown = PricingFormatting.countdownText(until: transition.date, now: now)
        return "\(headline)；下一次变价：\(moment) \(transition.context) · \(countdown)"
    }

    private var accessibilitySummary: String {
        let lights = "绿灯 \(snapshot.greenCount) 个，黄灯 \(snapshot.yellowCount) 个，红灯 \(snapshot.redCount) 个"
        let next = snapshot.nextTransition.map {
            "下一个变价 \(PricingFormatting.transitionText($0, now: now, timeZone: snapshot.timeZone))"
        } ?? "近期没有模型分时变价"
        let pick = summaryPickText.map { "\($0)；" } ?? ""
        return "\(lights)；\(pick)\(next)"
    }

    /// 免费额度严格优先于付费；没有免费时才给出能力达标模型里性价比最高的一条。
    private var summaryPickText: String? {
        if let free = snapshot.recommendations.first(where: { $0.kind == .free }) {
            return "免费 \(free.name) · 能力 \(PricingEngine.capabilityText(free.capabilityScore))"
        }
        guard let best = snapshot.bestValue,
              let score = best.model.capabilityScore,
              PricingEngine.valueScore(of: best) != nil else { return nil }
        return "性价比 \(best.model.shortName) \(PricingFormatting.mixedPriceText(best.mixedPrice)) · 能力 \(PricingEngine.capabilityText(score))"
    }
}
