import SwiftUI

struct ProjectUsageDetail: View {
    let project: ProjectUsageReading
    let back: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button("项目列表", systemImage: "chevron.left", action: back)
                .buttonStyle(EnergyPressStyle()).font(EnergyTypography.Detail.label)
                .foregroundStyle(EnergyVisualStyle.computeAccent).help("返回项目列表")
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(project.projectName).font(EnergyTypography.Detail.title).textSelection(.enabled)
                        Text(project.directory).font(EnergyTypography.Detail.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("今日总 Token").font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
                        Text(TokenFormatting.exact(project.totals.totalTokens))
                            .font(EnergyTypography.Detail.metric)
                            .lineLimit(1).minimumScaleFactor(0.8).textSelection(.enabled)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(EnergyVisualStyle.subtleFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(spacing: 0) {
                        TokenDetailRow(title: "输入", value: TokenFormatting.exact(project.totals.inputTokens))
                        TokenDetailRow(title: "其中缓存输入", value: TokenFormatting.exact(project.totals.cachedInputTokens), secondary: true)
                        Divider().overlay(EnergyVisualStyle.hairline)
                        TokenDetailRow(title: "输出", value: TokenFormatting.exact(project.totals.outputTokens))
                        TokenDetailRow(title: "其中推理输出", value: TokenFormatting.exact(project.totals.reasoningTokens), secondary: true)
                        Divider().overlay(EnergyVisualStyle.hairline)
                        TokenDetailRow(title: "Token 记录", value: "\(project.totals.turnCount) 条")
                    }
                    Text("总量 = 输入 + 输出。缓存与推理是子项。\n上海时区今日 · 本机会话日志")
                        .font(EnergyTypography.Detail.caption).foregroundStyle(.secondary).lineSpacing(4)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 2)
            }
        }
    }
}
