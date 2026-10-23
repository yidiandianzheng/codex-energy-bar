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
                lastUpdated: lastUpdated,
                isRefreshing: store.currentPageIsRefreshing,
                refreshError: refreshError,
                sourceTitle: sourceTitle,
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
                if store.mode == .balance {
                    AccountOverviewPanel(
                        readings: store.allBalanceReadings,
                        advice: store.balanceAdvice,
                        todayUsage: store.todayUsage,
                        lastUpdated: store.lastBalanceUpdate,
                        refreshError: store.balanceRefreshError,
                        isLoading: store.isRefreshingBalances,
                        select: { id in
                            store.selectAccount(id)
                            selectMode(.quota)
                        }
                    )
                    .transition(pageTransition)
                } else if store.mode == .quota {
                    AccountDetailPanel(
                        readings: store.allBalanceReadings,
                        advice: store.balanceAdvice,
                        todayUsage: store.todayUsage,
                        quotaLimits: store.quotaLimits,
                        resetCredits: store.resetCredits,
                        selectedAccountID: store.selectedAccountID,
                        select: { store.selectAccount($0) },
                        quotaLastUpdated: store.lastQuotaUpdate,
                        quotaRefreshError: store.quotaRefreshError,
                        balanceLastUpdated: store.lastBalanceUpdate,
                        balanceRefreshError: store.balanceRefreshError,
                        quotaIsRefreshing: store.isRefreshing,
                        balanceIsRefreshing: store.isRefreshingBalances
                    )
                    .transition(pageTransition)
                } else if store.mode == .radar {
                    ResetRadarDetailView(snapshot: store.radarSnapshot, loading: store.isRefreshingRadar)
                        .transition(pageTransition)
                } else {
                    EnergyDetailPanel(
                        summary: store.projectSummary,
                        isLoading: !store.hasLoadedProjects,
                        error: store.projectRefreshError,
                        codexTokens: store.hasLoadedProjects ? store.projectSummary.allProjectTotals.totalTokens : nil,
                        accountReadings: store.allBalanceReadings,
                        todayUsage: store.todayUsage
                    )
                        .transition(pageTransition)
                }
            }
            .animation(pageAnimation, value: store.mode)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var lastUpdated: Date? { store.currentPageLastUpdated }
    private var refreshError: String? { store.currentPageError }

    private var sourceTitle: String {
        switch store.mode {
        case .radar: "公开重置信号"
        case .projects: "本地日志"
        case .balance: "本机账户"
        default: "账户额度"
        }
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
