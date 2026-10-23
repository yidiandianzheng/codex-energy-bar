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

    var body: some View {
        VStack(spacing: 0) {
            // Row 1: one cell per account (Codex first), tap to open its page.
            HStack(spacing: 0) {
                PanelDragMark()
                ForEach(Array(readings.enumerated()), id: \.element.id) { index, reading in
                    if index > 0 {
                        Rectangle().fill(EnergyVisualStyle.hairline)
                            .frame(width: 0.5, height: 40)
                            .accessibilityHidden(true)
                    }
                    CompactAccountCell(
                        reading: reading,
                        isRecommended: advice.recommendedID == reading.id,
                        target: .account(reading.id),
                        action: { showAccount(reading.id) }
                    )
                }
            }
            .padding(.horizontal, 4).padding(.vertical, 3)
            .frame(maxWidth: .infinity).frame(height: EnergyPanelLayout.compactAccountRowHeight)

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

            CompactRadarButton(snapshot: radarSnapshot, loading: radarLoading, action: showRadar)
                .frame(height: 22)
                .overlay(alignment: .top) { Rectangle().fill(EnergyVisualStyle.hairline).frame(height: 0.5).padding(.horizontal, 8) }
            if showsCountdown {
                CompactCountdownButton(snapshot: radarSnapshot, action: showRadar)
                    .frame(height: EnergyPanelLayout.countdownRowHeight)
                    .overlay(alignment: .top) { Rectangle().fill(EnergyVisualStyle.hairline).frame(height: 0.5).padding(.horizontal, 8) }
            }
        }
    }
}
