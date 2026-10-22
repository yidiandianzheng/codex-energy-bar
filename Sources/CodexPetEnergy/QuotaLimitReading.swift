import Foundation

struct QuotaLimitReading: Identifiable, Equatable {
    let id: String
    let title: String
    let remainingPercent: Int?
    let resetsAt: Date?
    let windowDurationMins: Int?
}
