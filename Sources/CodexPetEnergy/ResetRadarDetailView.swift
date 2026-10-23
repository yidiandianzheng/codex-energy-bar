import SwiftUI

struct ResetRadarDetailView: View {
    let snapshot: ResetRadarSnapshot?
    let loading: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: snapshot?.countdownTarget(now: .now) == nil ? 60 : 1)) { context in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let snapshot {
                        forecastCard(snapshot, now: context.date)
                        primaryMessages(snapshot, now: context.date)
                        forecastReasons(snapshot, now: context.date)
                        Text("公开全局重置信号与个人每周额度独立；是否到账以账户额度为准。")
                            .font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
                    } else {
                        Text(loading ? "正在读取重置雷达…" : "重置雷达暂不可用")
                            .font(EnergyTypography.Detail.body).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, EnergyVisualStyle.panelInset).padding(.bottom, 18)
            }
        }
        .tint(EnergyVisualStyle.computeAccent)
    }

    private func forecastCard(_ snapshot: ResetRadarSnapshot, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.probabilityTitle(now: now)).font(EnergyTypography.Detail.section)
                Spacer()
                if let probability = snapshot.probability(now: now) {
                    Text("\(probability)%").font(EnergyTypography.Detail.metric).foregroundStyle(.primary)
                } else {
                    Text(snapshot.primaryIsFresh(now: now) ? "暂无概率" : "待同步")
                        .font(EnergyTypography.Detail.section).foregroundStyle(.secondary)
                }
            }
            if snapshot.commitmentProbability(now: now) != nil {
                Text("codex-reset.com 发布 Tibo 承诺窗口的投票预测：\(snapshot.commitmentWindowDescription(now: now) ?? "来源未给出截止时间")。")
                    .font(EnergyTypography.Detail.body)
                Text("主数字采用该站公开的承诺信号；Codex Resets 的来源预告只说明时间，实际到账以账户额度为准。")
                    .font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
            } else if snapshot.usesOfficialConfirmation(now: now) {
                Text("Codex Resets 已发布额度重置预告。")
                    .font(EnergyTypography.Detail.body)
                Text("来源预告与概率独立；实际到账以账户额度为准。")
                    .font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
            } else if snapshot.isAveraged(now: now) {
                Text("两站有效的未来 24 小时概率各占 50%，取算术平均。")
                    .font(EnergyTypography.Detail.body)
                Text("综合参考值由本机计算，未经过校准，不代表任一站点的原始预测。")
                    .font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
            } else if snapshot.usesReferenceProbability(now: now) {
                Text("Codex Resets 当前没有有效概率，采用 codex-reset.com 的 24 小时公开预测。")
                    .font(EnergyTypography.Detail.body)
            } else if snapshot.primaryIsFresh(now: now), let watch = snapshot.activeWatch(now: now) {
                Text("来源窗口：\(watch.forecast_window)").font(EnergyTypography.Detail.body)
                Text("预警截至 \(ResetRadarSources.beijing(ResetRadarSources.date(watch.expires_at))) 北京时间")
                    .font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
                if snapshot.probability(now: now) == nil {
                    Text("主站有预警消息，尚未提供有效概率。")
                        .font(EnergyTypography.Detail.body).foregroundStyle(.secondary)
                }
            } else if snapshot.primaryIsFresh(now: now) {
                Text("Codex Resets 已同步，当前没有有效的重置预警。")
                    .font(EnergyTypography.Detail.body)
                Text(snapshot.officialConfirmation(now: now) == nil
                         ? "暂无下一次概率或预告时间；最新重置消息可在下方查看。"
                         : "已发布的预告时间见下方；概率未提供时不显示倒计时。")
                    .font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
            } else {
                Text("Codex Resets 预警状态暂未同步；稍后可刷新。")
                    .font(EnergyTypography.Detail.body).foregroundStyle(.secondary)
            }
            if let schedule = snapshot.scheduleText(now: now) {
                Text(schedule + " · 北京时间").font(EnergyTypography.Detail.label)
            }
            if let countdown = snapshot.countdownText(now: now) {
                VStack(alignment: .leading, spacing: 3) {
                    if let target = snapshot.countdownTarget(now: now), target > now {
                        Text("更新倒计时").font(EnergyTypography.Detail.body).foregroundStyle(.secondary)
                    }
                    Text(snapshot.countdownValue(now: now) ?? countdown)
                        .font(EnergyTypography.Detail.countdown)
                        .monospacedDigit().foregroundStyle(.primary)
                }
                Text("按 Codex Resets 的预告时刻倒数，实际到账以账户额度为准。")
                    .font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
            }
            sourceReadings(snapshot, now: now)
            Text("本机检查：\(ResetRadarSources.beijing(snapshot.checkedAt)) · 北京时间")
                .font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
            if !snapshot.errors.isEmpty {
                Text(snapshot.errors.joined(separator: "；")).font(EnergyTypography.Detail.caption).foregroundStyle(EnergyVisualStyle.warningAccent)
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).energyCardSurface()
    }

    private func sourceReadings(_ snapshot: ResetRadarSnapshot, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                SourceLink("Codex Resets", destination: ResetRadarSources.primaryURL)
                Spacer()
                Text(snapshot.usesOfficialConfirmation(now: now)
                     ? "来源已预告" : sourceValue(snapshot.announcementProbability(now: now)))
            }.font(EnergyTypography.Detail.caption)
            Text("来源更新：\(ResetRadarSources.beijing(ResetRadarSources.date(snapshot.primary?.meta.generated_at))) · 北京时间")
                .font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
            HStack {
                SourceLink("codex-reset.com", destination: ResetReferenceForecast.pageURL)
                Spacer()
                Text(sourceValue(snapshot.referenceHeadlineProbability(now: now)))
            }.font(EnergyTypography.Detail.caption)
            Text("来源更新：\(ResetRadarSources.beijing(ResetRadarSources.date(snapshot.reference?.updated_at))) · 北京时间")
                .font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
            if snapshot.commitmentProbability(now: now) != nil {
                let pace24 = snapshot.referenceProbability(now: now)
                let pace48 = snapshot.referenceProbability48h(now: now)
                if pace24 != nil || pace48 != nil {
                    Text("节奏模型参考：24h \(sourceValue(pace24))" + (pace48.map { " · 48h " + sourceValue($0) } ?? "") + "；仅作趋势参考，不参与承诺预测。")
                        .font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
                }
            }
            if snapshot.commitmentProbability(now: now) != nil {
                Text("主数字来自 codex-reset.com 的公开承诺信号；预告时间来自 Codex Resets，两者相互独立。")
                    .font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
            } else if snapshot.usesOfficialConfirmation(now: now) {
                Text("预告时间来自 Codex Resets；codex-reset.com 的 24 小时数值独立列示，属于节奏模型参考。")
                    .font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
            } else if snapshot.reference != nil, !snapshot.referenceIsFresh(now: now) {
                Text("参考站读数已过期、数值无效或尚未反映最新重置，未参与计算。")
                    .font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
            }
            if snapshot.commitmentProbability(now: now) == nil,
               snapshot.announcementProbability(now: now) != nil, snapshot.referenceProbability(now: now) != nil,
               !snapshot.announcementIs24h(now: now) {
                Text("两站预测窗口不同，分别列示；主数字采用 Codex Resets，不跨窗口平均。")
                    .font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func sourceValue(_ value: Double?) -> String {
        guard let value else { return "暂无有效概率" }
        return value == value.rounded() ? "\(Int(value))%" : String(format: "%.1f%%", value)
    }

    private func primaryMessages(_ snapshot: ResetRadarSnapshot, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("重置消息").font(EnergyTypography.Detail.section)
                Spacer()
                SourceLink("Codex Resets ↗", destination: ResetRadarSources.primaryURL).font(EnergyTypography.Detail.caption)
            }
            if !snapshot.primaryIsFresh(now: now) {
                Text("主站状态暂未同步，以下记录不代表当前预告。")
                    .font(EnergyTypography.Detail.caption).foregroundStyle(EnergyVisualStyle.warningAccent)
            }
            if let scheduled = snapshot.officialConfirmation(now: now) {
                RadarMessageRow(title: scheduled.reset_type == "banked" ? "重置卡预告" : "额度重置预告",
                    date: scheduled.announced_at, text: scheduled.text, translation: nil,
                    url: scheduled.source.url, explanation: snapshot.scheduleText(now: now))
            }
            if let events = snapshot.archive?.events, !events.isEmpty {
                ForEach(events.prefix(8)) { event in
                    RadarMessageRow(title: event.reset_type == "banked" ? "重置卡发放记录" : "额度重置记录",
                        date: event.announced_at, text: event.text, translation: event.display_text,
                        url: event.tweet_url, explanation: nil)
                }
            } else if let latest = snapshot.primary?.data.latest_reset {
                RadarMessageRow(title: latest.reset_type == "banked" ? "重置卡发放记录" : "额度重置记录",
                    date: latest.announced_at, text: latest.text, translation: nil,
                    url: latest.source.url, explanation: nil)
            } else {
                Text("消息暂不可用，稍后可点击右上角刷新。")
                    .font(EnergyTypography.Detail.body).foregroundStyle(.secondary)
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).energyCardSurface()
    }

    private func forecastReasons(_ snapshot: ResetRadarSnapshot, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("预警依据").font(EnergyTypography.Detail.section)
            if let signal = snapshot.commitmentSignal(now: now) {
                Text("codex-reset.com Tibo 承诺预测 \(sourceValue(signal.percent))")
                    .font(EnergyTypography.Detail.label)
                Text("来源对已发布承诺窗口的投票预测：\(snapshot.commitmentWindowDescription(now: now) ?? "来源未给出截止时间")。该数值由来源发布，本应用只读取并展示，未做校准。")
                    .font(EnergyTypography.Detail.body).foregroundStyle(.secondary)
            }
            if let watch = snapshot.activeWatch(now: now) {
                RadarMessageRow(title: "Codex Resets 预警依据", date: watch.observed_at,
                    text: watch.text, translation: nil, url: watch.source.url, explanation: nil)
            }
            if snapshot.referenceIsFresh(now: now) {
                SourceLink("codex-reset.com 节奏模型 ↗", destination: ResetReferenceForecast.pageURL)
                    .font(EnergyTypography.Detail.label)
                let pace24 = snapshot.referenceProbability(now: now)
                let pace48 = snapshot.referenceProbability48h(now: now)
                Text("节奏模型：24h \(sourceValue(pace24))" + (pace48.map { " · 48h " + sourceValue($0) } ?? "")
                     + (snapshot.commitmentProbability(now: now) != nil
                        ? "；仅作趋势参考，主数字采用该站的承诺预测。"
                        : "；采用该站公开接口中的网页展示值。"))
                    .font(EnergyTypography.Detail.body).foregroundStyle(.secondary)
                if snapshot.reference?.confidence == "low" {
                    Text("来源置信度：低；属于实验性预测。")
                        .font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
                }
            } else if snapshot.commitmentProbability(now: now) != nil {
                SourceLink("codex-reset.com 承诺信号 ↗", destination: ResetReferenceForecast.pageURL)
                    .font(EnergyTypography.Detail.label)
            }
            if snapshot.activeWatch(now: now) == nil, !snapshot.referenceIsFresh(now: now),
               snapshot.commitmentProbability(now: now) == nil {
                Text("两站当前都没有有效预测依据；缺失或过期读数不按 0% 处理。")
                    .font(EnergyTypography.Detail.body).foregroundStyle(.secondary)
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).energyCardSurface()
    }
}
