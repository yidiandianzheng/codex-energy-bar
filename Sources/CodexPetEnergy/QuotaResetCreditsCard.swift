import SwiftUI

struct QuotaResetCreditsCard: View {
    let summary: RateLimitResetCreditsSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.counterclockwise.circle")
                    .font(EnergyTypography.Icon.section).foregroundStyle(EnergyVisualStyle.computeAccent).accessibilityHidden(true)
                Text("使用限额重置").font(EnergyTypography.Detail.section)
                Spacer()
                Text(summary.map { "可用 \($0.availableCount) 次" } ?? "暂不可用")
                    .font(EnergyTypography.Detail.caption).foregroundStyle(.primary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(EnergyVisualStyle.computeAccent.opacity(0.10), in: Capsule())
            }
            if let summary {
                if let credits = summary.credits, !credits.isEmpty {
                    ForEach(credits) { credit in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(credit.displayTitle).font(EnergyTypography.Detail.label)
                            Text(credit.expirationText()).font(EnergyTypography.Detail.body).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    Text(summary.availableCount > 0 ? "到期时间暂未返回" : "暂无可用重置额度")
                        .font(EnergyTypography.Detail.body).foregroundStyle(.secondary)
                }
            } else {
                Text("账户暂未返回重置额度信息").font(EnergyTypography.Detail.body).foregroundStyle(.secondary)
            }
            Text("一次恢复 5 小时限额、每周限额或两者。")
                .font(EnergyTypography.Detail.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).energyCardSurface()
        .accessibilityElement(children: .combine)
    }
}
