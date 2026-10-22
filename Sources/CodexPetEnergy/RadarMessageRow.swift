import SwiftUI

struct RadarMessageRow: View {
    let title: String
    let date: String
    let text: String
    let translation: String?
    let url: String?
    let explanation: String?

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                if let translation, !translation.isEmpty, translation != text {
                    Text("来源中文译文").font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
                    Text(ResetRadarSources.cleanText(translation)).font(EnergyTypography.Detail.body)
                }
                Text("原文").font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
                Text(ResetRadarSources.cleanText(text)).font(EnergyTypography.Detail.body).textSelection(.enabled)
                if let explanation, !explanation.isEmpty {
                    Text("来源解读：" + explanation).font(EnergyTypography.Detail.body).foregroundStyle(.secondary)
                }
                if let link = ResetRadarSources.safeLink(url) {
                    SourceLink("打开原帖 ↗", destination: link).font(EnergyTypography.Detail.body)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title).font(EnergyTypography.Detail.caption)
                    Spacer(minLength: 4)
                    Text(ResetRadarSources.beijing(ResetRadarSources.date(date)))
                        .font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
                }
                Text(ResetRadarSources.cleanText(translation ?? text))
                    .font(EnergyTypography.Detail.body).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .tint(EnergyVisualStyle.computeAccent)
        .help("点击展开完整消息；时间均为北京时间")
    }
}
