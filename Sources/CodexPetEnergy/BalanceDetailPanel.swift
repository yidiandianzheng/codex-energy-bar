import SwiftUI

struct BalanceDetailPanel: View {
    let codex: BalanceReading
    let balances: [BalanceReading]
    let advice: UsageAdvice
    let lastUpdated: Date?
    let refreshError: String?
    let isLoading: Bool

    private var readings: [BalanceReading] {
        [codex] + balances.filter { $0.id != BalanceReading.codexID }
    }

    private var hasAnyValue: Bool {
        readings.contains { $0.hasReading }
    }

    private var allLoading: Bool {
        readings.allSatisfy { if case .loading = $0.state { return true }; return false }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        VStack(spacing: 8) {
            if readings.isEmpty || (allLoading && lastUpdated == nil) {
                PanelEmptyState(
                    title: "正在读取账户余额",
                    systemImage: "creditcard",
                    description: "Codex、DeepSeek、豆包、WorkBuddy、千问办公的剩余额度会分别显示；未配置的账户会给出配置指引。"
                )
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        BalanceAdviceCard(advice: advice)
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(readings) { reading in
                                BalanceProviderCard(
                                    reading: reading,
                                    isRecommended: advice.recommendedID == reading.id,
                                    level: advice.level(for: reading.id)
                                )
                            }
                        }
                        if !hasAnyValue, let refreshError {
                            Text(refreshError)
                                .font(EnergyTypography.Detail.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            Text(footer)
                .font(EnergyTypography.Detail.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, EnergyVisualStyle.panelInset)
        .padding(.bottom, EnergyVisualStyle.panelInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var footer: String {
        if isLoading { return "正在刷新账户余额…" }
        if let refreshError { return refreshError }
        if let lastUpdated {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            formatter.dateFormat = "HH:mm"
            return "更新于 \(formatter.string(from: lastUpdated)) · 每 5 分钟自动刷新 · 只读本机账户数据"
        }
        return "每 5 分钟自动刷新 · 账户数据只在本机读取"
    }
}

/// Local, rule-based usage advice (no network, no external model).
private struct BalanceAdviceCard: View {
    let advice: UsageAdvice

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(EnergyTypography.Detail.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("使用建议").font(EnergyTypography.Detail.section)
                Spacer(minLength: 4)
                Text(advice.headline)
                    .font(EnergyTypography.Detail.label)
                    .lineLimit(1)
            }
            Text(advice.detail)
                .font(EnergyTypography.Detail.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .energyCardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("使用建议：\(advice.headline)")
        .accessibilityValue(advice.detail)
    }
}
