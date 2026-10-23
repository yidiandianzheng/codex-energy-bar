import SwiftUI

struct QuotaLimitRow: View {
    let reading: QuotaLimitReading
    let subtitle: String
    let systemImage: String
    let identityColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(reading.title).font(EnergyTypography.Detail.section)
                    Text(subtitle).font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(reading.remainingPercent.map { "\($0)%" } ?? "—")
                    .font(EnergyTypography.Detail.gridValue)
                Text("剩余").font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(EnergyVisualStyle.hairline)
                    Capsule().fill(Color.primary.opacity(0.7))
                        .frame(width: proxy.size.width * CGFloat(min(100, max(0, reading.remainingPercent ?? 0))) / 100)
                }
            }.frame(height: 4).accessibilityHidden(true)
            HStack(alignment: .top) {
                Text("恢复 \(EnergyLogic.compactResetDateText(reading.resetsAt))")
                Spacer(minLength: 8)
                Text(EnergyLogic.shortResetText(until: reading.resetsAt))
            }.font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 14)
            .overlay(alignment: .bottom) { Divider() }
            .accessibilityElement(children: .ignore).accessibilityLabel(reading.title)
            .accessibilityValue("剩余 \(reading.remainingPercent.map { "\($0)%" } ?? "暂不可用")，恢复 \(EnergyLogic.compactResetDateText(reading.resetsAt))")
    }
}
