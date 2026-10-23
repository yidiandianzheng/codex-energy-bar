import SwiftUI

/// Semantic type roles at size level 1. EnergyPanelLayout scales the whole panel once.
/// Components select a role; new sizes and weights belong here, not in individual views.
enum EnergyTypography {
    enum Mini {
        static let caption = Font.system(size: 10)
        static let label = Font.system(size: 10)
        static let sub = Font.system(size: 10, design: .rounded).monospacedDigit()
        static let value = Font.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit()
        static let signal = Font.system(size: 12, weight: .bold, design: .rounded).monospacedDigit()
        static let unit = Font.system(size: 12, design: .rounded)
    }

    enum Detail {
        static let caption = Font.system(size: 11)
        static let body = Font.system(size: 13)
        static let label = Font.system(size: 13, weight: .medium)
        static let section = Font.system(size: 13, weight: .semibold)
        static let chip = Font.system(size: 11, weight: .semibold)
        static let title = Font.system(size: 16, weight: .semibold)
        static let rowValue = Font.system(size: 15, weight: .bold, design: .rounded).monospacedDigit()
        static let gridValue = Font.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit()
        static let countdown = Font.system(size: 20, weight: .bold, design: .rounded).monospacedDigit()
        static let metric = Font.system(size: 28, weight: .bold, design: .rounded).monospacedDigit()
        static let heroMetric = Font.system(size: 36, weight: .bold, design: .rounded).monospacedDigit()
        static let unit = Font.system(size: 20, design: .rounded)
        static let tab = Font.system(size: 12)
        static let selectedTab = section
    }

    enum Icon {
        static let tiny = Font.system(size: 7, weight: .semibold)
        static let small = Font.system(size: 8)
        static let compact = Font.system(size: 9, weight: .medium)
        static let standard = Font.system(size: 12, weight: .medium)
        static let section = Font.system(size: 17)
        static let metric = Font.system(size: 22)
        static let empty = Font.system(size: 26, weight: .light)
        static let statusDot = Font.system(size: 4)
    }
}
