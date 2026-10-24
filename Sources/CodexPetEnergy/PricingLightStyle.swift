import SwiftUI

/// Traffic-light primitives. Colour never travels alone: every call site also
/// renders the light's title or symbol so the meaning survives colour blindness.
enum PricingLightStyle {
    static func color(for light: PricingLight) -> Color {
        switch light {
        case .green: EnergyVisualStyle.pricingGreen
        case .yellow: EnergyVisualStyle.pricingYellow
        case .red: EnergyVisualStyle.pricingRed
        case .unknown: Color.secondary
        }
    }

    static func fill(for light: PricingLight) -> Color {
        color(for: light).opacity(0.13)
    }

    static func symbol(for light: PricingLight) -> String {
        light.symbol
    }

    /// Chip colour separates "activity price" from "ordinary price": orange is
    /// a limited-time deal, gray is the normal / peak price. The dot keeps the
    /// absolute cost colour, so both dimensions remain readable.
    static func tierChipTint(for quote: PricingQuote) -> Color {
        quote.kind == .offPeak ? EnergyVisualStyle.pricingDeal : .secondary
    }

    static func tierChipFill(for quote: PricingQuote) -> Color {
        quote.kind == .offPeak ? EnergyVisualStyle.pricingDeal.opacity(0.13) : EnergyVisualStyle.elevatedFill
    }

    static func channelDealTint() -> Color { EnergyVisualStyle.pricingDeal }

    static func channelStatusTint(isActive: Bool) -> Color {
        isActive ? EnergyVisualStyle.pricingDeal : .secondary
    }
}
