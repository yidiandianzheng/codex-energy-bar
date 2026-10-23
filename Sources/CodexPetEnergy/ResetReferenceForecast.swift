import Foundation

/// Documented display probabilities from /api/forecast; units are 0–100.
/// `probabilities.rounded_24h` / `rounded_48h` are that site's cadence model.
/// `official_signal` is its published Tibo-commitment signal and a documented
/// field to build on; when present the source website shows its score as the
/// headline probability for the committed window, so the app mirrors that
/// value instead of substituting the cadence model.
struct ResetReferenceForecast: Decodable {
    static let pageURL = URL(string: "https://codex-reset.com/zh/")!
    static let endpoint = "https://codex-reset.com/api/forecast"
    let mode: String?
    let updated_at: String?
    let last_reset_at: String?
    let probabilities: Probabilities?
    let confidence: String?
    let official_signal: Signal?
    struct Probabilities: Decodable {
        let rounded_24h: Double?
        let rounded_48h: Double?
        let signal_percent: Double?
    }
    struct Signal: Decodable {
        let at: String?
        let signal_type: String?
        let score: Score?
        let window: Window?
        struct Score: Decodable { let value: Double? }
        struct Window: Decodable {
            let label: String?
            let target_at: String?
            let end_at: String?
            let time_zone: String?
        }
    }
}
