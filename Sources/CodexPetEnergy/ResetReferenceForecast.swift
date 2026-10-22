import Foundation

/// Documented display probability from /api/forecast; units are 0–100.
/// raw_24h is a different historical baseline and must not replace the displayed value.
struct ResetReferenceForecast: Decodable {
    static let pageURL = URL(string: "https://codex-reset.com/zh/")!
    static let endpoint = "https://codex-reset.com/api/forecast"
    let updated_at: String?
    let last_reset_at: String?
    let probabilities: Probabilities?
    let confidence: String?
    struct Probabilities: Decodable { let rounded_24h: Double? }
}
