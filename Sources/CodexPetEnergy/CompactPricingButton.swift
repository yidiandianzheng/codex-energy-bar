import SwiftUI

/// Cost-light row in the compact bar. It answers "which strong model is the best
/// value right now" with up to two capability-gated picks: free windows first,
/// then discounts ranked by value (capability ÷ blended price). Weak or unrated
/// models stay in the pricing page and never take a Mini slot. The full table is
/// one click away.
struct CompactPricingButton: View {
    let snapshot: PricingSnapshot
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: PricingLightStyle.symbol(for: rowLight))
                    .font(EnergyTypography.Icon.compact)
                    .foregroundStyle(PricingLightStyle.color(for: rowLight))
                    .accessibilityHidden(true)
                Text(rowTitle)
                    .font(EnergyTypography.Mini.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Text(mainText)
                    .font(EnergyTypography.Mini.label)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .layoutPriority(1)
                Text("·")
                    .font(EnergyTypography.Mini.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Text(hintText)
                    .font(EnergyTypography.Mini.caption)
                    .foregroundStyle(hintColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(EnergyTypography.Icon.tiny)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(hovered ? EnergyVisualStyle.hoverFill : .clear)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .background(CompactActionRegion(target: .pricing))
        .help(helpText)
        .accessibilityLabel("查看模型优惠与省钱灯")
        .accessibilityValue(accessibilityValue)
    }

    private var picks: [PricingRecommendation] {
        Array(snapshot.recommendations.prefix(2))
    }

    private var rowLight: PricingLight {
        guard let first = picks.first else { return snapshot.bestValue?.light ?? .unknown }
        switch first.kind {
        case .free:
            return .green
        case .discount:
            let quote = snapshot.quotes.first { "discount:" + $0.id == first.id }
            return quote?.light ?? .yellow
        case .upcomingFree:
            return snapshot.bestValue?.light ?? .unknown
        }
    }

    private var rowTitle: String {
        picks.isEmpty ? "性价比" : "优惠"
    }

    private var mainText: String {
        if picks.isEmpty {
            guard let best = snapshot.bestValue else { return "暂无达标强模型" }
            return "\(best.model.shortName) \(PricingFormatting.mixedPriceText(best.mixedPrice))"
        }
        return picks.map(\.shortText).joined(separator: " · ")
    }

    private var hintColor: Color {
        if snapshot.isStale { return EnergyVisualStyle.warningAccent }
        return picks.isEmpty ? .secondary : EnergyVisualStyle.pricingDeal
    }

    private var hintText: String {
        if snapshot.isStale { return "价格待核对" }
        if snapshot.recommendations.count > picks.count { return "共 \(snapshot.recommendations.count) 条" }
        return picks.isEmpty ? "\(snapshot.greenCount) 个绿灯" : "看全部"
    }

    private var helpText: String {
        var parts: [String] = []
        if snapshot.recommendations.isEmpty {
            if let best = snapshot.bestValue, let score = best.model.capabilityScore {
                parts.append("当前没有达标的强模型优惠；性价比最高 \(best.model.name)（能力 \(PricingEngine.capabilityText(score))），折算 \(PricingFormatting.mixedPriceText(best.mixedPrice))。")
            } else {
                parts.append("当前没有达标的强模型优惠。")
            }
        } else {
            parts.append("强模型优惠：" + snapshot.recommendations.map(\.detail).joined(separator: " "))
        }
        parts.append("单击查看全部折扣、免费时段和下次变价。")
        return parts.joined(separator: "")
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        if snapshot.recommendations.isEmpty {
            if let best = snapshot.bestValue, let score = best.model.capabilityScore {
                parts.append("当前没有达标的强模型优惠；性价比最高 \(best.model.name)，能力 \(PricingEngine.capabilityText(score))，\(PricingFormatting.mixedPriceText(best.mixedPrice))")
            } else {
                parts.append("当前没有达标的强模型优惠")
            }
        } else {
            parts.append(snapshot.recommendations.map(\.shortText).joined(separator: "，"))
        }
        parts.append("绿灯 \(snapshot.greenCount) 个，黄灯 \(snapshot.yellowCount) 个，红灯 \(snapshot.redCount) 个")
        return parts.joined(separator: "；")
    }
}
