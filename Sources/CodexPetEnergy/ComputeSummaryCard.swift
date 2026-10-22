import SwiftUI

struct ComputeSummaryCard: View {
    let summary: ProjectUsageDaySummary
    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Label("今日本地 Token", systemImage: "chart.bar.xaxis")
                    .font(EnergyTypography.Detail.label).foregroundStyle(.secondary)
                Text(TokenFormatting.compact(summary.allProjectTotals.totalTokens))
                    .font(EnergyTypography.Detail.heroMetric)
                    .foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(EnergyVisualStyle.hairline).frame(width: 1, height: 44)
            VStack(alignment: .leading, spacing: 8) {
                Text("活跃项目").font(EnergyTypography.Detail.body).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(summary.projects.count)").font(EnergyTypography.Detail.metric)
                    Text("个").font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
                }
            }.frame(minWidth: 58)
        }.padding(EnergyVisualStyle.cardInset).energyCardSurface()
            .accessibilityElement(children: .ignore).accessibilityLabel("今日本地 Token")
            .accessibilityValue("共 \(TokenFormatting.exact(summary.allProjectTotals.totalTokens)) Token，\(summary.projects.count) 个活跃项目")
    }
}
