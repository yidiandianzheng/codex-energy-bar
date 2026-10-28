import SwiftUI

struct CompactEnergyBar: View {
    let readings: [BalanceReading]
    let advice: UsageAdvice
    let todayTokens: Int?
    let projectError: String?
    let showAccount: (String) -> Void
    let showAccounts: () -> Void
    let showProjects: () -> Void

    var radarSnapshot: ResetRadarSnapshot? = nil
    var radarLoading = false
    var showsCountdown = false
    var showRadar: () -> Void = {}

    var pricingSnapshot: PricingSnapshot? = nil
    var showsPricing = false
    var showPricing: () -> Void = {}

    var nightWatchActive = false
    var nightWatchElapsed: String? = nil
    var nightWatchNotice: String? = nil
    var toggleNightWatch: () -> Void = {}

    var body: some View {
        let columns = EnergyPanelLayout.compactAccountColumns
        let rows = stride(from: 0, to: readings.count, by: columns).map {
            Array(readings[$0..<min($0 + columns, readings.count)])
        }
        VStack(spacing: 0) {
            // Row 1..n: three accounts per row, tap to open that account's page.
            HStack(spacing: 0) {
                PanelDragMark()
                VStack(spacing: 0) {
                    ForEach(rows.indices, id: \.self) { rowIndex in
                        HStack(spacing: 0) {
                            ForEach(Array(rows[rowIndex].enumerated()), id: \.element.id) { index, reading in
                                if index > 0 {
                                    Rectangle().fill(EnergyVisualStyle.hairline)
                                        .frame(width: 0.5, height: 34)
                                        .accessibilityHidden(true)
                                }
                                CompactAccountCell(
                                    reading: reading,
                                    isRecommended: advice.recommendedID == reading.id,
                                    target: .account(reading.id),
                                    action: { showAccount(reading.id) }
                                )
                            }
                            if rows[rowIndex].count < columns {
                                ForEach(0..<(columns - rows[rowIndex].count), id: \.self) { _ in
                                    Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }
                        }
                        .frame(height: EnergyPanelLayout.compactAccountRowHeight)
                    }
                }
            }
            .padding(.horizontal, 4).padding(.vertical, 3)

            // Row 2: local recommendation + today's Token.
            HStack(spacing: 0) {
                CompactAdviceButton(advice: advice, action: showAccounts)
                Rectangle().fill(EnergyVisualStyle.hairline)
                    .frame(width: 0.5, height: 11)
                    .accessibilityHidden(true)
                CompactTokenButton(todayTokens: todayTokens, error: projectError, action: showProjects)
                    .frame(width: 94)
            }
            .frame(height: 22)
            .overlay(alignment: .top) {
                Rectangle().fill(EnergyVisualStyle.hairline).frame(height: 0.5).padding(.horizontal, 8)
            }

            if showsPricing, let pricingSnapshot {
                CompactPricingButton(snapshot: pricingSnapshot, action: showPricing)
                    .frame(height: EnergyPanelLayout.pricingRowHeight)
                    .overlay(alignment: .top) {
                        Rectangle().fill(EnergyVisualStyle.hairline).frame(height: 0.5).padding(.horizontal, 8)
                    }
            }

            CompactRadarButton(snapshot: radarSnapshot, loading: radarLoading, action: showRadar)
                .frame(height: 22)
                .overlay(alignment: .top) { Rectangle().fill(EnergyVisualStyle.hairline).frame(height: 0.5).padding(.horizontal, 8) }
            if showsCountdown {
                CompactCountdownButton(snapshot: radarSnapshot, action: showRadar)
                    .frame(height: EnergyPanelLayout.countdownRowHeight)
                    .overlay(alignment: .top) { Rectangle().fill(EnergyVisualStyle.hairline).frame(height: 0.5).padding(.horizontal, 8) }
            }

            CompactNightWatchButton(isActive: nightWatchActive, elapsedText: nightWatchElapsed,
                notice: nightWatchNotice, action: toggleNightWatch)
                .frame(height: EnergyPanelLayout.nightWatchRowHeight)
                .overlay(alignment: .top) {
                    Rectangle().fill(EnergyVisualStyle.hairline).frame(height: 0.5).padding(.horizontal, 8)
                }
        }
    }
}
