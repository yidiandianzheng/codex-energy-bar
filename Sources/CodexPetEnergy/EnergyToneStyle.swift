import SwiftUI

enum EnergyToneStyle {
    static func color(for remainingPercent: Int?) -> Color {
        switch EnergyLogic.tone(for: remainingPercent) {
        case .green: EnergyVisualStyle.computeAccent
        case .yellow, .red: EnergyVisualStyle.warningAccent
        case .unavailable: Color.secondary
        }
    }

    static func symbol(for remainingPercent: Int?) -> String {
        switch EnergyLogic.tone(for: remainingPercent) {
        case .green: "checkmark.circle.fill"
        case .yellow: "exclamationmark.circle.fill"
        case .red: "exclamationmark.triangle.fill"
        case .unavailable: "questionmark.circle"
        }
    }
}
