import SwiftUI

struct ProjectUsageContent: View {
    let summary: ProjectUsageDaySummary
    var codexTokens: Int? = nil
    var accountReadings: [BalanceReading] = []
    var todayUsage: TodayUsageSnapshot = .empty
    @State<Bool> private var showAll = false
    @State<String?> private var selectedID = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
        if let project = summary.projects.first(where: { $0.id == selectedID }) {
            ProjectUsageDetail(project: project, back: { selectedID = nil })
                .transition(.opacity)
        } else {
            VStack(spacing: 14) {
                AccountUsageGrid(codexTokens: codexTokens ?? summary.allProjectTotals.totalTokens,
                                 readings: accountReadings, todayUsage: todayUsage)
                HStack {
                    Text("今日项目用量").font(EnergyTypography.Detail.section)
                    Spacer()
                    if summary.projects.count > 5 {
                        Button(showAll ? "前 5 名" : "全部 \(summary.projects.count) 个") { showAll.toggle() }
                            .buttonStyle(.plain).font(EnergyTypography.Detail.label).foregroundStyle(EnergyVisualStyle.computeAccent)
                    }
                    Text("按用量排序").font(EnergyTypography.Detail.caption).foregroundStyle(.tertiary)
                }
                if summary.projects.isEmpty {
                    PanelEmptyState(title: "今天还没有项目记录", systemImage: "chart.bar.xaxis",
                        description: "开始使用 Codex 后，这里会显示当天的本地 Token。")
                        .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(visibleProjects.enumerated()), id: \.element.id) { index, project in
                                Button { selectedID = project.id } label: {
                                    ProjectUsageRow(rank: index + 1, project: project,
                                        maxTokens: summary.allProjectTotals.totalTokens)
                                }.buttonStyle(EnergyPressStyle())
                                .accessibilityLabel("查看 \(project.projectName) 的 Token 明细")
                            }
                        }.padding(6)
                    }.energyCardSurface()
                }
            }.transition(.opacity)
        }
        }.animation(reduceMotion ? nil : EnergyVisualStyle.contentAnimation, value: selectedID)
    }

    private var visibleProjects: [ProjectUsageReading] {
        showAll ? summary.projects : Array(summary.projects.prefix(5))
    }
}
