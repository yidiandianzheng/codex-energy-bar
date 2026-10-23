import Foundation

/// One action contract shared by AppKit hit regions and SwiftUI buttons.
enum CompactActionTarget: Hashable {
    case account(String)
    case page(EnergyPanelMode)
    static let quota = Self.account(BalanceReading.codexID)
    static let balance = Self.page(.balance)
    static let projects = Self.page(.projects)
    static let radar = Self.page(.radar)
}
