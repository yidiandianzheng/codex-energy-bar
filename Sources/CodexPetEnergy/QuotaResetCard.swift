import SwiftUI

struct QuotaResetCard: View {
    let resetsAt: Date?
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.clockwise").font(EnergyTypography.Detail.body).foregroundStyle(.secondary)
                .padding(.top, 2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("重置时间").font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
                Text(EnergyLogic.compactResetDateText(resetsAt)).font(EnergyTypography.Detail.section.monospacedDigit())
            }
            Spacer(minLength: 8)
            Text(EnergyLogic.shortResetText(until: resetsAt)).font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
                .padding(.top, 2)
        }.padding(.horizontal, 4).padding(.vertical, 8)
            .accessibilityElement(children: .combine)
    }
}
