import SwiftUI

/// One account cell in the redesigned compact bar: title above, big number
/// below, whole cell clickable.
struct CompactAccountCell: View {
    let reading: BalanceReading
    let isRecommended: Bool
    let target: CompactActionTarget
    /// Five simultaneously open clients leave about 61 pt per cell. In that
    /// transient case drop the window suffix from the title and shorten large
    /// balances so the cell never truncates its headline number.
    var isDense = false
    let action: () -> Void
    @State<Bool> private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 2) {
                    if isRecommended {
                        Image(systemName: "sparkles")
                            .font(EnergyTypography.Icon.tiny)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    Text(shortTitle)
                        .font(EnergyTypography.Mini.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(isDense ? 0.8 : 1)
                }
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    if reading.id == "deepseek", reading.hasReading, let prefix = reading.unitPrefix {
                        Text(prefix).font(EnergyTypography.Mini.unit).foregroundStyle(.secondary)
                    }
                    Text(valueText)
                        .font(EnergyTypography.Mini.value)
                        .foregroundStyle(isAvailable ? .primary : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(isDense ? 0.65 : 0.85)
                }
                Text(secondaryText ?? " ")
                    .font(EnergyTypography.Mini.sub)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .background(
                hovered || isRecommended ? EnergyVisualStyle.hoverFill : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .background(CompactActionRegion(target: target))
        .buttonStyle(EnergyPressStyle())
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : EnergyVisualStyle.quickAnimation, value: hovered)
        .help(helpText)
        .accessibilityLabel("\(reading.title)账户详情")
        .accessibilityValue(accessibilityValue)
    }

    private var isAvailable: Bool {
        reading.hasReading
    }

    private var stateText: String {
        switch reading.state {
        case .ok: return ""
        case .stale: return "旧数据"
        case .loading: return "读取中"
        case .unconfigured: return "未配置"
        case .failed(let message): return message.contains("未运行") || message.contains("启动") ? "未运行" : "读取失败"
        }
    }

    private var shortTitle: String {
        // "豆包 5h" / "Codex 7d": name the window the headline number belongs
        // to, so the two quotas are never mixed up. The dense five-account bar
        // keeps only the account name to avoid a truncated title.
        guard !isDense else { return reading.title }
        guard let tag = primaryWindow?.shortTag else { return reading.title }
        return "\(reading.title) \(tag)"
    }

    private var valueText: String {
        switch reading.state {
        case .ok, .stale:
            if reading.id == "qwenwork", let number = numericValue {
                // Keep the exact balance (one decimal) instead of "2K"; this is
                // the number the user checks against 千问办公 itself.
                return String(format: "%.1f", number)
            }
            if isDense, ["deepseek", "workbuddy", "workbuddyintl"].contains(reading.id),
               let number = numericValue {
                return compactDecimal(number)
            }
            switch reading.id {
            case "deepseek":
                if let number = numericValue { return compactDecimal(number) }
            case "workbuddy", "workbuddyintl":
                if let number = numericValue { return compactDecimal(number) }
            default:
                break
            }
            if let value = reading.valueText {
                return reading.unitSuffix == "%" ? "\(value)%" : value
            }
            return "—"
        case .loading:
            return "…"
        case .unconfigured, .failed:
            return "—"
        }
    }

    /// Second line: the quota window that is *not* the headline, otherwise the
    /// unit the headline number is measured in. The headline window is found by
    /// its explicit marker, falling back to a percentage match so accounts that
    /// only publish "current window" stay correct.
    private var secondaryText: String? {
        guard reading.hasReading else { return stateText }
        if case .stale = reading.state { return "旧数据" }
        if reading.windows.count > 1, let other = secondaryWindow {
            return "\(other.shortTag) \(other.remainingPercent)%"
        }
        switch reading.id {
        case "workbuddy", "workbuddyintl": return "积分"
        case "deepseek": return "余额"
        case "qwenwork": return "Credits"
        default: return nil
        }
    }

    private var secondaryWindow: BalanceWindowReading? {
        guard let primary = primaryWindow else { return nil }
        return reading.windows.first { $0.id != primary.id }
    }

    private var primaryWindow: BalanceWindowReading? {
        guard reading.windows.count > 1 else { return nil }
        if let marked = reading.windows.first(where: { $0.isPrimary }) { return marked }
        if let percent = reading.percent,
           let matched = reading.windows.first(where: { $0.remainingPercent == percent }) {
            return matched
        }
        return reading.windows.first
    }

    /// Keeps one decimal on small balances so a leftover ¥0.90 never reads as
    /// ¥1, while large round numbers stay short.
    private func compactDecimal(_ number: Double) -> String {
        let units: [(Double, String)] = [(1_000_000_000_000_000, "P"), (1_000_000_000_000, "T"), (1_000_000_000, "B"), (1_000_000, "M"), (1_000, "K")]
        for (index, unit) in units.enumerated() where abs(number) >= unit.0 {
            let value = number / unit.0
            let scaled = abs(value) >= 999.5 && index > 0 ? value / 1_000 : value
            let suffix = abs(value) >= 999.5 && index > 0 ? units[index - 1].1 : unit.1
            var text = String(format: abs(scaled) >= 10 ? "%.0f" : "%.1f", scaled)
            if text.hasSuffix(".0") { text.removeLast(2) }
            return text + suffix
        }
        let rounded = (number * 10).rounded() / 10
        if rounded == rounded.rounded() && abs(rounded) >= 100 {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }

    private var numericValue: Double? {
        guard let number = reading.numericValue, number.isFinite else { return nil }
        return number
    }

    private var helpText: String {
        "\(isRecommended ? "推荐使用；" : "")\(reading.stateMessage ?? "") 单击打开\(reading.title)；按住可拖动算力条"
    }

    private var accessibilityValue: String {
        switch reading.state {
        case .ok, .stale:
            let value = [reading.unitPrefix, reading.valueText, reading.unitSuffix].compactMap { $0 }.joined()
            return [isRecommended ? "推荐使用" : nil, value, secondaryText].compactMap { $0 }.joined(separator: "，")
        case .loading:
            return "正在读取"
        case .unconfigured(let message), .failed(let message):
            return message
        }
    }
}
