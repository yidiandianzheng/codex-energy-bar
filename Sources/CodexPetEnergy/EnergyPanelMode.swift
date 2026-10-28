enum EnergyPanelMode: String, Hashable {
    case compact
    case projects
    case quota
    case balance
    case radar
    case pricing
    case leaderboard

    /// 汇总在前，账户详情其次：先看全局，再点进单个账户。
    static let dashboardModes: [EnergyPanelMode] = [.balance, .quota, .projects, .radar, .leaderboard]

    var title: String {
        switch self {
        case .compact: "算力环"
        case .projects: "今日用量"
        case .quota: "账户"
        case .balance: "总览"
        case .radar: "重置雷达"
        case .pricing: "省钱灯"
        case .leaderboard: "模型榜"
        }
    }

    var systemImage: String {
        switch self {
        case .compact: "gauge.with.dots.needle.50percent"
        case .projects: "chart.bar.xaxis"
        case .quota: "person.crop.circle"
        case .balance: "square.grid.2x2"
        case .radar: "dot.radiowaves.left.and.right"
        case .pricing: "yensign.circle"
        case .leaderboard: "chart.line.uptrend.xyaxis"
        }
    }
}
