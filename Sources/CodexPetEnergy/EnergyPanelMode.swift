enum EnergyPanelMode: String, Hashable {
    case compact
    case projects
    case quota
    case radar

    static let dashboardModes: [EnergyPanelMode] = [.quota, .projects, .radar]

    var title: String {
        switch self {
        case .compact: "Codex 算力条"
        case .projects: "今日算力"
        case .quota: "额度"
        case .radar: "重置雷达"
        }
    }

    var systemImage: String {
        switch self {
        case .compact: "gauge.with.dots.needle.50percent"
        case .projects: "chart.bar.xaxis"
        case .quota: "battery.75percent"
        case .radar: "dot.radiowaves.left.and.right"
        }
    }
}
