import SwiftUI

/// Cost-light row in the compact bar. The dot answers "is it cheap right now";
/// the secondary text names the DeepSeek discount state because that is the
/// time window the user asked to follow. The full discount table lives one
/// click away, so the Mini row never tries to fit every "x 折".
struct CompactPricingButton: View {
    let snapshot: PricingSnapshot
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: PricingLightStyle.symbol(for: cheapestLight))
                    .font(EnergyTypography.Icon.compact)
                    .foregroundStyle(PricingLightStyle.color(for: cheapestLight))
                    .accessibilityHidden(true)
                Text("最省")
                    .font(EnergyTypography.Mini.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Text(cheapestText)
                    .font(EnergyTypography.Mini.label)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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
        .accessibilityLabel("查看省钱灯")
        .accessibilityValue(accessibilityValue)
    }

    private var cheapestLight: PricingLight {
        snapshot.cheapest?.light ?? .unknown
    }

    private var cheapestText: String {
        guard let cheapest = snapshot.cheapest else { return "暂无价格" }
        return "\(cheapest.model.shortName) \(PricingFormatting.mixedPriceText(cheapest.mixedPrice))"
    }

    private var deepSeekQuote: PricingQuote? {
        snapshot.quotes.first { $0.id == PricingEngine.flashID }
    }

    private var hintColor: Color {
        if snapshot.isStale { return EnergyVisualStyle.warningAccent }
        if deepSeekQuote?.kind == .offPeak { return EnergyVisualStyle.pricingDeal }
        return .secondary
    }

    private var hintText: String {
        if snapshot.isStale { return "价格待核对" }
        guard let deepSeek = deepSeekQuote else { return "\(snapshot.greenCount) 个绿灯" }
        switch deepSeek.kind {
        case .offPeak: return "DeepSeek 谷时↓"
        case .peak: return "DeepSeek 峰时↑"
        case .flat: return "\(snapshot.greenCount) 个绿灯"
        }
    }

    private var helpText: String {
        var parts: [String] = []
        if let cheapest = snapshot.cheapest {
            parts.append("现在最省：\(cheapest.model.name)，折算 \(PricingFormatting.mixedPriceText(cheapest.mixedPrice))。")
        }
        if let deepSeek = deepSeekQuote {
            parts.append("DeepSeek Flash 当前\(deepSeek.kind == .offPeak ? "谷时" : "峰时")。")
        }
        parts.append("绿灯 \(snapshot.greenCount) 个，黄灯 \(snapshot.yellowCount) 个，红灯 \(snapshot.redCount) 个。")
        parts.append("单击查看全部折扣、时段和下次变价。")
        return parts.joined(separator: "")
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        if let cheapest = snapshot.cheapest {
            parts.append("现在最省 \(cheapest.model.name)，\(PricingFormatting.mixedPriceText(cheapest.mixedPrice))")
        }
        if let deepSeek = deepSeekQuote {
            parts.append("DeepSeek Flash \(deepSeek.kind == .offPeak ? "谷时" : "峰时")")
        }
        parts.append("绿灯 \(snapshot.greenCount) 个，黄灯 \(snapshot.yellowCount) 个，红灯 \(snapshot.redCount) 个")
        return parts.joined(separator: "；")
    }
}
