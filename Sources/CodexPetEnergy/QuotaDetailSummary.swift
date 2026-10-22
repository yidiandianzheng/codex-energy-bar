import Foundation

struct QuotaDetailSummary: Equatable {
    let overall: QuotaLimitReading?
    let modelLimits: [QuotaLimitReading]
    let availableResetCount: Int?

    var featuredCompactLimit: QuotaLimitReading? {
        modelLimits.first { $0.id == "codex_bengalfox" }
            ?? modelLimits.first {
                $0.title.localizedCaseInsensitiveContains("5.3")
            }
    }

    static let unavailable = QuotaDetailSummary(
        overall: nil,
        modelLimits: [],
        availableResetCount: nil
    )
}
