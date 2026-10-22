import SwiftUI

struct EnergyDashboardView: View {
    @ObservedObject var store: EnergyStore
    let selectMode: (EnergyPanelMode) -> Void
    let refresh: () -> Void
    let showMore: () -> Void
    let collapse: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            DashboardHeader(
                lastUpdated: store.mode == .radar ? store.radarSnapshot?.checkedAt : (store.mode == .projects ? store.lastProjectUpdate : store.lastQuotaUpdate),
                isRefreshing: store.currentPageIsRefreshing,
                refreshError: store.mode == .radar ? store.radarSnapshot?.errors.first : (store.mode == .projects ? store.projectRefreshError : store.quotaRefreshError),
                sourceTitle: store.mode == .radar ? "公开重置信号" : (store.mode == .projects ? "本地日志" : "账户额度"),
                refresh: refresh,
                showMore: showMore,
                collapse: collapse
            )

            DashboardTabPicker(
                selection: store.mode,
                select: selectMode
            )
            .padding(.horizontal, EnergyVisualStyle.panelInset)
            .padding(.bottom, 18)

            ZStack {
                if store.mode == .quota {
                    QuotaDetailPanel(
                        limits: store.quotaLimits,
                        resetCredits: store.resetCredits,
                        lastUpdated: store.lastQuotaUpdate,
                        refreshError: store.quotaRefreshError
                    )
                    .transition(pageTransition)
                } else if store.mode == .radar {
                    ResetRadarDetailView(snapshot: store.radarSnapshot, loading: store.isRefreshingRadar)
                        .transition(pageTransition)
                } else {
                    EnergyDetailPanel(
                        summary: store.projectSummary,
                        isLoading: !store.hasLoadedProjects,
                        error: store.projectRefreshError
                    )
                        .transition(pageTransition)
                }
            }
            .animation(pageAnimation, value: store.mode)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pageAnimation: Animation {
        reduceMotion ? .linear(duration: 0.1) : EnergyVisualStyle.contentAnimation
    }

    private var pageTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .offset(y: 3))
    }
}
