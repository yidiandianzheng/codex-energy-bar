import SwiftUI

/// 模型榜页面（一级 Tab）：四榜切换 + KPI + 手动刷新。
/// 与 Python 版同口径；抓取失败时保留缓存快照并在页头提示。
struct ModelLeaderboardDetailView: View {
    let snapshot: LeaderboardSnapshot?
    let loading: Bool
    let error: String?
    let refresh: () -> Void

    @State private var board: LeaderboardBoard = .radar

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                if let snapshot {
                    kpi(snapshot)
                    picker
                    note(snapshot)
                    rows(snapshot)
                    footer(snapshot)
                } else if loading {
                    loadingState
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, EnergyVisualStyle.panelInset)
            .padding(.bottom, 18)
        }
    }

    // MARK: 页头

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("模型榜").font(EnergyTypography.Detail.title)
                Spacer(minLength: 0)
                if loading {
                    ProgressView().scaleEffect(0.6).frame(width: 16, height: 16)
                } else {
                    Button(action: refresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(EnergyTypography.Detail.caption)
                            .foregroundStyle(.secondary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("刷新榜单")
                }
            }
            Text("谁强、谁划算、什么新出来了——每天更新一次。")
                .font(EnergyTypography.Detail.caption)
                .foregroundStyle(.secondary)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(EnergyTypography.Detail.caption)
                    .foregroundStyle(EnergyVisualStyle.warningAccent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let snapshot {
                Text("更新于 \(Self.dateText(snapshot.checkedAt)) · 数据源 OpenRouter")
                    .font(EnergyTypography.Detail.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: KPI

    private func kpi(_ snapshot: LeaderboardSnapshot) -> some View {
        HStack(spacing: 8) {
            stat("收录", snapshot.totalCount)
            stat("新上线", snapshot.radarCount)
            stat("已标定", snapshot.scoredCount)
            Spacer(minLength: 4)
        }
    }

    private func stat(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(value)")
                .font(EnergyTypography.Detail.gridValue)
                .monospacedDigit()
            Text(label).font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
    }

    // MARK: 选择器与说明

    private var picker: some View {
        Picker("榜单", selection: $board) {
            ForEach(LeaderboardBoard.allCases) { item in
                Text(item.shortTitle).tag(item)
            }
        }
        .pickerStyle(.segmented)
    }

    private func note(_ snapshot: LeaderboardSnapshot) -> some View {
        Text(board.note)
            .font(EnergyTypography.Detail.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: 列表

    private func rows(_ snapshot: LeaderboardSnapshot) -> some View {
        let rows = snapshot.rows(board)
        return LazyVStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                rowView(rank: index + 1, row: row)
                if index < rows.count - 1 {
                    Rectangle().fill(EnergyVisualStyle.hairline).frame(height: 0.5).padding(.leading, 26)
                }
            }
        }
        .padding(.vertical, 6)
        .energyCardSurface()
    }

    private func rowView(rank: Int, row: LeaderboardRow) -> some View {
        HStack(spacing: 8) {
            Text("\(rank)")
                .font(EnergyTypography.Detail.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name)
                    .font(EnergyTypography.Detail.chip)
                    .lineLimit(1)
                Text("\(row.vendor) · \(row.contextText)")
                    .font(EnergyTypography.Detail.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(trailingValue(row))
                    .font(EnergyTypography.Detail.chip.monospacedDigit())
                    .lineLimit(1)
                if let caption = trailingCaption(row) {
                    Text(caption)
                        .font(EnergyTypography.Detail.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 40)
        .accessibilityElement(children: .combine)
    }

    private func trailingValue(_ row: LeaderboardRow) -> String {
        switch board {
        case .capability: row.scoreText
        case .value: row.valueIndex.map { String(format: "%.0f", $0) } ?? "—"
        case .price: row.priceText
        case .radar: row.priceText
        case .popularity: row.usageTokens.map { ModelLeaderboardEngine.tokenText($0) } ?? "—"
        }
    }

    private func trailingCaption(_ row: LeaderboardRow) -> String? {
        switch board {
        case .capability: row.priceText
        case .value: row.priceText
        case .price: nil
        case .radar: row.noteText
        case .popularity: row.noteText
        }
    }

    // MARK: 状态与脚注

    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("正在拉取模型榜单…")
                .font(EnergyTypography.Detail.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(EnergyTypography.Icon.section)
                .foregroundStyle(.secondary)
            Text("暂无榜单数据")
                .font(EnergyTypography.Detail.chip)
            Button("重试", action: refresh)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(EnergyVisualStyle.computeAccent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func footer(_ snapshot: LeaderboardSnapshot) -> some View {
        Text("口径：混合单价 = 0.75×输入 + 0.25×输出（$/M token）；性价比 = 能力分 ÷ 混合单价，指数 100 = 本榜最强。性价比榜只收近半年上线的已标定模型，更早的旧模型仍可在能力/价格榜查看。价格来自 OpenRouter 聚合标价，可能与官网直连价有差异；能力分为人工静态表（2026-10 基线），新模型多为待标定，请以实际体验为准。免费 \(snapshot.freeCount) 个 / 收费 \(snapshot.paidCount) 个。")
            .font(EnergyTypography.Detail.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}
