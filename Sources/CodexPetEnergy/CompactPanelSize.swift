import CoreGraphics
import Foundation

enum CompactPanelSize: String, CaseIterable, Identifiable {
    case level1
    case level2
    case level3
    case level4
    case level5

    static let `default` = CompactPanelSize.level1

    private static let defaultsKey = "energy-panel-compact-size-level"

    var id: String { rawValue }

    var scale: CGFloat {
        switch self {
        case .level1: 1.00
        case .level2: 1.08
        case .level3: 1.16
        case .level4: 1.24
        case .level5: 1.32
        }
    }

    var title: String {
        switch self {
        case .level1: "1档 · 标准界面"
        case .level2: "2档 · 界面 +8%"
        case .level3: "3档 · 界面 +16%"
        case .level4: "4档 · 界面 +24%"
        case .level5: "5档 · 界面 +32%"
        }
    }

    static func load(defaults: UserDefaults = .standard) -> CompactPanelSize {
        guard let rawValue = defaults.string(forKey: defaultsKey),
              let size = CompactPanelSize(rawValue: rawValue)
        else { return .default }
        return size
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}
