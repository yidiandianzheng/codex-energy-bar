import Foundation

enum TokenFormatting {
    static func compact(_ value: Int) -> String {
        let magnitude: Double
        let suffix: String

        if value >= 100_000_000 {
            magnitude = Double(value) / 100_000_000
            suffix = "亿"
        } else if value >= 10_000 {
            magnitude = Double(value) / 10_000
            suffix = "万"
        } else {
            return String(value)
        }

        let fractionLength = magnitude >= 10 ? 0 : 1
        let number = magnitude.formatted(
            .number
                .precision(.fractionLength(fractionLength))
                .grouping(.never)
                .locale(Locale(identifier: "zh_CN"))
        )
        return "\(number)\(suffix)"
    }

    static func exact(_ value: Int) -> String {
        value.formatted(
            .number
                .grouping(.automatic)
                .locale(Locale(identifier: "zh_CN"))
        )
    }
}
