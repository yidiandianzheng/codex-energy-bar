import Foundation

struct EnergyRefreshRequest: Equatable {
    var codex = false
    var projects = false
    var radar = false
    var leaderboard = false
    var balances: Set<BalanceProvider> = []

    static func forPage(_ mode: EnergyPanelMode, accountID: String) -> Self {
        switch mode {
        case .quota:
            if accountID == BalanceReading.codexID { return Self(codex: true) }
            return Self(balances: BalanceProvider(rawValue: accountID).map { [$0] } ?? [])
        case .balance, .compact: return Self(codex: true, balances: Set(BalanceProvider.allCases))
        case .projects: return Self(projects: true, balances: Set(BalanceProvider.allCases))
        case .radar: return Self(radar: true)
        case .pricing: return Self()
        case .leaderboard: return Self(leaderboard: true)
        }
    }
}
