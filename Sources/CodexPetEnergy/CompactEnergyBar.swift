import SwiftUI

struct CompactEnergyBar: View {
    let limits: [QuotaLimitReading]
    let quotaError: String?
    let projectError: String?
    let todayTokens: Int?
    let showQuota: () -> Void
    let showProjects: () -> Void

    var radarSnapshot: ResetRadarSnapshot? = nil
    var radarLoading = false
    var showsCountdown = false
    var showRadar: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                PanelDragMark()
                CompactQuotaButton(limits: limits, error: quotaError, action: showQuota)
                Rectangle().fill(EnergyVisualStyle.strongHairline)
                    .frame(width: 0.5, height: 24).accessibilityHidden(true)
                CompactComputeButton(todayTokens: todayTokens, error: projectError, action: showProjects)
            }
            .padding(.horizontal, 4).padding(.vertical, 3)
            .frame(maxWidth: .infinity).frame(height: 44)
            CompactRadarButton(snapshot: radarSnapshot, loading: radarLoading, action: showRadar)
                .frame(height: 18)
                .overlay(alignment: .top) { Rectangle().fill(EnergyVisualStyle.hairline).frame(height: 0.5).padding(.horizontal, 8) }
            if showsCountdown {
                CompactCountdownButton(snapshot: radarSnapshot, action: showRadar)
                    .frame(height: EnergyPanelLayout.countdownRowHeight)
                    .overlay(alignment: .top) { Rectangle().fill(EnergyVisualStyle.hairline).frame(height: 0.5).padding(.horizontal, 8) }
            }
        }
    }
}
