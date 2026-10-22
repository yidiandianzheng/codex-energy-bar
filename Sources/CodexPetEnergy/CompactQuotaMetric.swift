import SwiftUI

struct CompactQuotaMetric: View {
    let title: String
    let reading: EnergyReading

    var body: some View {
        HStack(spacing: 3) {
            Text(title)
                .font(EnergyTypography.Mini.label)
                .foregroundStyle(.secondary)
            Text(percentText)
                .font(EnergyTypography.Mini.signal)
                .foregroundStyle(EnergyToneStyle.color(for: reading.remainingPercent))
                .contentTransition(.numericText())
                .animation(nil, value: reading.remainingPercent)
        }
    }

    private var percentText: String {
        reading.remainingPercent.map { "\($0)%" } ?? "—"
    }
}
