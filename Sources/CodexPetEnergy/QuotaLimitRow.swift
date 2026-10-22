import SwiftUI

struct QuotaLimitRow: View {
    let reading: QuotaLimitReading
    let subtitle: String
    let systemImage: String
    let identityColor: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(reading.title).font(EnergyTypography.Detail.section).lineLimit(2)
                Spacer()
                Text(subtitle).font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(EnergyVisualStyle.subtleFill, in: Capsule())
            }
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(reading.remainingPercent.map(String.init) ?? "—")
                            .font(EnergyTypography.Detail.heroMetric)
                        if reading.remainingPercent != nil {
                            Text("%").font(EnergyTypography.Detail.unit).foregroundStyle(.secondary)
                        }
                    }
                    Text(reading.remainingPercent == nil ? "额度暂不可用" : "剩余可用额度")
                        .font(EnergyTypography.Detail.body).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle().stroke(EnergyVisualStyle.hairline, lineWidth: 7)
                    Circle().trim(from: 0, to: Double(reading.remainingPercent ?? 0) / 100)
                        .stroke(EnergyToneStyle.color(for: reading.remainingPercent), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "bolt.fill")
                        .font(EnergyTypography.Icon.metric)
                        .foregroundStyle(EnergyToneStyle.color(for: reading.remainingPercent))
                }.frame(width: 70, height: 70).padding(.trailing, 4).accessibilityHidden(true)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: reading.remainingPercent)
            }
            Divider().overlay(EnergyVisualStyle.hairline)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.clockwise").font(EnergyTypography.Detail.body).foregroundStyle(.secondary).padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text("下次重置").font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
                    Text(EnergyLogic.compactResetDateText(reading.resetsAt)).font(EnergyTypography.Detail.label.monospacedDigit())
                }
                Spacer(minLength: 4)
                Text(EnergyLogic.shortResetText(until: reading.resetsAt)).font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }.padding(16).energyCardSurface()
            .accessibilityElement(children: .ignore).accessibilityLabel(reading.title)
            .accessibilityValue("剩余 \(reading.remainingPercent.map { "\($0)%" } ?? "暂不可用")，重置 \(EnergyLogic.compactResetDateText(reading.resetsAt))")
    }
}
