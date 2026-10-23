import SwiftUI

/// One account card on the balance page. Cards are laid out two per row, so
/// the layout is compact: title, value, one wrapped summary line and an
/// optional progress bar. The corner status slot marks the recommendation,
/// a critical quota or an unavailable account; fill, outline and weight carry
/// the state without introducing a hue.
struct BalanceProviderCard: View {
    let reading: BalanceReading
    let isRecommended: Bool
    let level: UsageLevel

    private var isAvailable: Bool {
        reading.hasReading
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: reading.systemImage)
                    .font(EnergyTypography.Detail.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(reading.title)
                    .font(EnergyTypography.Detail.section)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                statusBadge
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                if let prefix = reading.unitPrefix, let value = reading.valueText {
                    Text(prefix).font(EnergyTypography.Detail.body).foregroundStyle(.secondary)
                    Text(value).font(EnergyTypography.Detail.metric)
                } else if let value = reading.valueText {
                    Text(value).font(EnergyTypography.Detail.metric)
                } else {
                    Text("—").font(EnergyTypography.Detail.metric).foregroundStyle(.secondary)
                }
                if let suffix = reading.unitSuffix, reading.valueText != nil {
                    Text(suffix).font(EnergyTypography.Detail.body).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            Text(summary)
                .font(EnergyTypography.Detail.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if let percent = reading.percent, isAvailable {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(EnergyVisualStyle.hairline)
                        Capsule()
                            .fill(EnergyToneStyle.color(for: percent))
                            .frame(width: max(2, proxy.size.width * CGFloat(percent) / 100))
                    }
                }
                .frame(height: 3)
                .accessibilityHidden(true)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .energyCardSurface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.title)
        .accessibilityValue(accessibilityValue)
    }

    /// The corner carries one status at a time, highest priority first:
    /// recommendation → critical quota → unavailable account → tight quota.
    /// Every state uses the same capsule slot so the four cards line up.
    private var statusBadge: some View {
        Group {
            if isRecommended {
                Text("推荐")
                    .font(EnergyTypography.Detail.chip)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(EnergyVisualStyle.selectedFill, in: Capsule())
            } else if level == .critical {
                BalanceStatusChip(title: level.title, kind: .critical)
            } else if let stateTitle = unavailableStateTitle {
                BalanceStatusChip(title: stateTitle, kind: .unavailable)
            } else if level.isWarning {
                Text(level.title)
                    .font(EnergyTypography.Detail.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var unavailableStateTitle: String? {
        switch reading.state {
        case .failed: return "读取失败"
        case .stale: return "旧数据"
        case .unconfigured: return "未配置"
        default: return nil
        }
    }

    private var summary: String {
        switch reading.state {
        case .loading:
            return "正在读取…"
        case .unconfigured(let message), .failed(let message), .stale(let message):
            return message
        case .ok:
            return [reading.caption, reading.detail].compactMap { $0 }.joined(separator: " · ")
        }
    }

    private var accessibilityValue: String {
        switch reading.state {
        case .ok:
            let value = [reading.unitPrefix, reading.valueText, reading.unitSuffix].compactMap { $0 }.joined()
            let caption = "\(reading.caption ?? "剩余") \(value)"
            if isRecommended { return "推荐，\(caption)" }
            if level.isWarning { return "\(level.title)，\(caption)" }
            return caption
        case .loading:
            return "正在读取"
        case .unconfigured(let message):
            return "未配置，\(message)"
        case .failed(let message):
            return "读取失败，\(message)"
        case .stale(let message):
            return "旧数据，\(reading.valueText ?? "—")，\(message)"
        }
    }
}

/// Shared corner chip for a critical quota or an unavailable account.
/// Fill, outline, icon and weight carry the meaning; no hue is introduced.
private struct BalanceStatusChip: View {
    enum Kind: Equatable {
        case critical
        case unavailable
    }

    let title: String
    let kind: Kind

    var body: some View {
        HStack(spacing: 3) {
            if kind == .critical {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(EnergyTypography.Icon.small)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(EnergyTypography.Detail.chip)
        }
        .foregroundStyle(kind == .critical ? Color.primary : Color.secondary)
        .padding(.horizontal, 6).padding(.vertical, 1)
        .background {
            Capsule().strokeBorder(
                kind == .critical ? EnergyVisualStyle.statusChipStroke : EnergyVisualStyle.strongHairline,
                lineWidth: 1)
        }
    }
}
