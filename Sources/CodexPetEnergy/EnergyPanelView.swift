import SwiftUI

struct EnergyPanelView: View {
    @ObservedObject var store: EnergyStore
    let refresh: () -> Void
    let showMore: () -> Void
    @AppStorage("energy-panel-compact-size-level") private var sizeLevel = "level1"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let compactBase = EnergyPanelLayout.compactBaseSize(showsCountdown: store.showsResetCountdown)
        let base = store.mode == .compact ? compactBase : EnergyPanelLayout.expandedSize
        let scale = CompactPanelSize(rawValue: sizeLevel)?.scale ?? 1
        ZStack(alignment: .topLeading) {
            if store.mode == .compact {
                CompactEnergyBar(readings: store.compactBalanceReadings, advice: store.compactAdvice,
                    todayTokens: store.hasLoadedProjects ? store.projectSummary.allProjectTotals.totalTokens : nil,
                    projectError: store.projectRefreshError,
                    showAccount: { store.activate(.account($0)) },
                    showAccounts: { store.setMode(.balance) },
                    showProjects: { store.setMode(.projects) },
                    radarSnapshot: store.radarSnapshot, radarLoading: store.isRefreshingRadar,
                    showsCountdown: store.showsResetCountdown,
                    showRadar: { store.setMode(.radar) })
                    .frame(width: compactBase.width, height: compactBase.height)
                    .transition(.opacity)
            } else {
                EnergyDashboardView(store: store, selectMode: { store.setMode($0) }, refresh: refresh,
                    showMore: showMore, collapse: { store.setCompactMode() })
                    .frame(width: EnergyPanelLayout.expandedSize.width, height: EnergyPanelLayout.expandedSize.height)
                    .transition(.opacity)
            }
        }.animation(reduceMotion ? .linear(duration: 0.08) : EnergyVisualStyle.contentAnimation, value: store.mode)
            .frame(width: base.width, height: base.height)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: base.width * scale, height: base.height * scale, alignment: .topLeading)
            .energyPanelSurface(cornerRadius: (store.mode == .compact
                ? EnergyVisualStyle.compactCornerRadius : EnergyVisualStyle.panelCornerRadius) * scale)
    }
}
