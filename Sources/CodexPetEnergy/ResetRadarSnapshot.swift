import Foundation

/// A Tibo-commitment probability published by codex-reset.com. Unlike the
/// cadence model, it is tied to a committed window and is the number the
/// source website shows as its headline.
struct ResetCommitmentSignal {
    let percent: Double
    let target: Date?
    let windowLabel: String?
    let announcedAt: Date?
    let signalType: String?
}

struct ResetRadarSnapshot {
    var primary: ResetRadarSources.Primary?
    var archive: ResetRadarSources.Archive?
    var reference: ResetReferenceForecast?
    var checkedAt: Date
    var errors: [String]

    func activeWatch(now: Date) -> ResetRadarSources.Primary.Watch? {
        guard primaryIsFresh(now: now), let watch = primary?.data.active_watch,
              let observed = ResetRadarSources.date(watch.observed_at), observed <= now.addingTimeInterval(300),
              let expiry = ResetRadarSources.date(watch.expires_at), expiry > now, expiry > observed else { return nil }
        if let latest = primary?.data.latest_reset, latest.reset_type == "regular",
           let completed = ResetRadarSources.date(latest.announced_at), completed >= observed { return nil }
        if referenceMetadataIsFresh(now: now), let completed = ResetRadarSources.date(reference?.last_reset_at),
           completed >= observed { return nil }
        return watch
    }

    func primaryIsFresh(now: Date) -> Bool {
        guard let generated = ResetRadarSources.date(primary?.meta.generated_at) else { return false }
        return now.timeIntervalSince(checkedAt) <= 1800 && now.timeIntervalSince(generated) <= 1800
            && generated <= now.addingTimeInterval(300)
    }

    func usesAnnouncementProbability(now: Date) -> Bool {
        guard primaryIsFresh(now: now), let value = activeWatch(now: now)?.reset_chance_percent else { return false }
        return value.isFinite && (0...100).contains(value)
    }

    func announcementProbability(now: Date) -> Double? {
        guard usesAnnouncementProbability(now: now), let value = activeWatch(now: now)?.reset_chance_percent else { return nil }
        return value
    }

    /// Third-party schedule metadata is a source announcement, never official
    /// confirmation or a probability. One validity rule gates all its UI.
    static let officialGraceInterval: TimeInterval = 2 * 3600

    func officialConfirmation(now: Date) -> ResetRadarSources.Primary.Scheduled? {
        guard primaryIsFresh(now: now), let scheduled = primary?.data.scheduled_reset else { return nil }
        if let status = scheduled.status?.lowercased(), !["scheduled", "announced", "pending"].contains(status) {
            return nil
        }
        guard scheduled.reset_type == "regular",
              let announced = ResetRadarSources.date(scheduled.announced_at),
              announced <= now.addingTimeInterval(300),
              let target = ResetRadarSources.date(scheduled.scheduled_for),
              target > announced,
              now <= target.addingTimeInterval(Self.officialGraceInterval) else { return nil }
        if let latest = primary?.data.latest_reset, latest.reset_type == "regular",
           let completed = ResetRadarSources.date(latest.announced_at), completed >= announced { return nil }
        if referenceMetadataIsFresh(now: now), let completed = ResetRadarSources.date(reference?.last_reset_at),
           completed >= announced { return nil }
        return scheduled
    }

    func usesOfficialConfirmation(now: Date) -> Bool { officialConfirmation(now: now) != nil }

    /// Compatibility entry point; a dated source announcement has no implied odds.
    func officialProbability(now: Date) -> Double? { nil }

    /// Timestamp and reset-cycle freshness of the codex-reset.com response.
    /// Each published number is validated separately so one unusable field does
    /// not discard another documented reading from the same fresh response.
    func referenceMetadataIsFresh(now: Date) -> Bool {
        guard let updated = ResetRadarSources.date(reference?.updated_at),
              let lastReset = ResetRadarSources.date(reference?.last_reset_at),
              now.timeIntervalSince(checkedAt) <= 1800, now.timeIntervalSince(updated) <= 1800,
              updated <= now.addingTimeInterval(300), lastReset <= updated.addingTimeInterval(300) else { return false }
        // The sites record observation and announcement at different instants of one reset.
        if let latest = primary?.data.latest_reset, latest.reset_type == "regular",
           let completed = ResetRadarSources.date(latest.announced_at),
           completed.timeIntervalSince(lastReset) > 3600 { return false }
        return true
    }

    func referenceIsFresh(now: Date) -> Bool {
        guard referenceMetadataIsFresh(now: now),
              let value = reference?.probabilities?.rounded_24h, value.isFinite, (0...100).contains(value) else { return false }
        return true
    }

    /// The source's own published 48-hour cadence value; only metadata gated so
    /// the 24-hour and 48-hour readings remain independent.
    func referenceProbability48h(now: Date) -> Double? {
        guard referenceMetadataIsFresh(now: now),
              let value = reference?.probabilities?.rounded_48h, value.isFinite, (0...100).contains(value) else { return nil }
        return value
    }

    /// The source website headlines its published Tibo-commitment signal for the
    /// committed window. Use that documented value while it is fresh, in range,
    /// not superseded by a confirmed reset, and not long past its deadline.
    func commitmentSignal(now: Date) -> ResetCommitmentSignal? {
        guard referenceMetadataIsFresh(now: now), let signal = reference?.official_signal,
              let value = signal.score?.value ?? reference?.probabilities?.signal_percent,
              value.isFinite, (0...100).contains(value) else { return nil }
        let announced = ResetRadarSources.date(signal.at)
        if let announced, announced > now.addingTimeInterval(300) { return nil }
        let target = ResetRadarSources.date(signal.window?.target_at)
            ?? ResetRadarSources.date(signal.window?.end_at)
        if let target {
            if let announced, target <= announced { return nil }
            guard now <= target.addingTimeInterval(Self.officialGraceInterval) else { return nil }
        }
        if let announced {
            if let latest = primary?.data.latest_reset, latest.reset_type == "regular",
               let completed = ResetRadarSources.date(latest.announced_at), completed >= announced { return nil }
            if let lastReset = ResetRadarSources.date(reference?.last_reset_at), lastReset >= announced { return nil }
        }
        return ResetCommitmentSignal(percent: value, target: target, windowLabel: signal.window?.label,
                                     announcedAt: announced, signalType: signal.signal_type)
    }

    func commitmentProbability(now: Date) -> Double? { commitmentSignal(now: now)?.percent }

    /// Localized description of the committed window, for the detail page.
    func commitmentWindowDescription(now: Date) -> String? {
        guard let signal = commitmentSignal(now: now) else { return nil }
        if let target = signal.target { return ResetRadarSources.beijing(target) + "（北京时间）前" }
        if let label = signal.windowLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            return "来源窗口「\(label)」"
        }
        return "来源未给出截止时间"
    }

    /// What the source website itself displays as its headline probability.
    func referenceHeadlineProbability(now: Date) -> Double? {
        commitmentProbability(now: now) ?? referenceProbability(now: now)
    }

    func referenceProbability(now: Date) -> Double? {
        referenceIsFresh(now: now) ? reference?.probabilities?.rounded_24h : nil
    }

    func announcementIs24h(now: Date) -> Bool {
        guard let watch = activeWatch(now: now) else { return false }
        let window = watch.forecast_window.lowercased().replacingOccurrences(of: "_", with: " ")
        return window.range(of: #"(?<![0-9])24\s*(?:h(?:ours?)?|小时)(?![a-z0-9])"#,
                            options: .regularExpression) != nil
            && window.range(of: #"(?<![0-9])48\s*(?:h(?:ours?)?|小时)"#,
                            options: .regularExpression) == nil
    }

    func isAveraged(now: Date) -> Bool {
        commitmentProbability(now: now) == nil
            && announcementProbability(now: now) != nil
            && referenceProbability(now: now) != nil
            && announcementIs24h(now: now)
    }

    func usesReferenceProbability(now: Date) -> Bool {
        commitmentProbability(now: now) != nil
            || (referenceProbability(now: now) != nil
                && (announcementProbability(now: now) == nil || isAveraged(now: now)))
    }

    func rawProbability(now: Date) -> Double? {
        // The source's committed-window signal is its displayed headline and
        // describes a different question than the rolling 24h cadence model.
        if let committed = commitmentProbability(now: now) { return committed }
        let primaryValue = announcementProbability(now: now)
        let referenceValue = referenceProbability(now: now)
        if isAveraged(now: now), let primaryValue, let referenceValue { return (primaryValue + referenceValue) / 2 }
        return primaryValue ?? referenceValue
    }

    func probability(now: Date) -> Int? { rawProbability(now: now).map { Int($0.rounded()) } }

    func forecastIsFresh(now: Date) -> Bool { probability(now: now) != nil }

    func probabilitySourceName(now: Date) -> String {
        if commitmentProbability(now: now) != nil { return "codex-reset.com" }
        if isAveraged(now: now) { return "双源平均" }
        return usesReferenceProbability(now: now) ? "codex-reset.com" : "Codex Resets"
    }

    func probabilitySourceURL(now: Date) -> URL? {
        if commitmentProbability(now: now) != nil { return ResetReferenceForecast.pageURL }
        if isAveraged(now: now) { return nil }
        return usesReferenceProbability(now: now) ? ResetReferenceForecast.pageURL : ResetRadarSources.primaryURL
    }

    func compactForecastDetail(now: Date) -> String {
        if let schedule = compactScheduleText(now: now) { return schedule }
        if let target = commitmentSignal(now: now)?.target {
            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "M/d HH:mm"
            return "承诺至 " + formatter.string(from: target)
        }
        if isAveraged(now: now) { return "双源平均" }
        if usesReferenceProbability(now: now) { return "codex-reset.com" }
        if let watch = activeWatch(now: now), let expiry = ResetRadarSources.date(watch.expires_at) {
            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "M/d HH:mm"
            return "观察至" + formatter.string(from: expiry)
        }
        return "查看依据"
    }

    func probabilityTitle(now: Date) -> String {
        if commitmentProbability(now: now) != nil { return "承诺预测" }
        if isAveraged(now: now) { return "24h参考" }
        if usesReferenceProbability(now: now) { return "24h预测" }
        guard activeWatch(now: now) != nil else { return "重置预警" }
        return announcementIs24h(now: now) ? "24h预警" : "来源预警"
    }

    func scheduleText(now: Date) -> String? {
        guard let scheduled = officialConfirmation(now: now),
              let time = ResetRadarSources.date(scheduled.scheduled_for) else { return nil }
        return (time < now ? "来源预告已到，待确认：" : "来源预告：") + ResetRadarSources.beijing(time)
    }

    /// Countdown tracks the third-party source's dated announcement only;
    /// completed, withdrawn, invalid or stale metadata removes it everywhere.
    func countdownTarget(now: Date) -> Date? {
        guard let scheduled = officialConfirmation(now: now) else { return nil }
        return ResetRadarSources.date(scheduled.scheduled_for)
    }

    func countdownText(now: Date) -> String? {
        guard let value = countdownValue(now: now), let target = countdownTarget(now: now) else { return nil }
        return target > now ? "来源预告倒计时 " + value : value
    }

    func countdownValue(now: Date) -> String? {
        guard let target = countdownTarget(now: now) else { return nil }
        let remaining = target.timeIntervalSince(now)
        guard remaining > 0 else { return "时间已到·待确认" }
        let seconds = Int(ceil(remaining))
        let days = seconds / 86400
        let clock = String(format: "%02d:%02d:%02d", seconds / 3600 % 24, seconds / 60 % 60, seconds % 60)
        return (days > 0 ? "\(days)天 " : "") + clock
    }

    func compactScheduleText(now: Date) -> String? {
        guard let scheduled = officialConfirmation(now: now),
              let date = ResetRadarSources.date(scheduled.scheduled_for) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "M/d HH:mm"
        return "来源预告 " + formatter.string(from: date)
    }

    func compactText(now: Date) -> String {
        if let probability = probability(now: now) {
            let window = compactForecastDetail(now: now)
            return "\(probabilityTitle(now: now)) \(probability)% · \(window)" + (countdownText(now: now).map { " · \($0)" } ?? "")
        }
        if primaryIsFresh(now: now) {
            if let schedule = compactScheduleText(now: now) { return "重置预告 · " + schedule }
            if activeWatch(now: now) != nil { return "重置观察 · " + compactForecastDetail(now: now) }
            return archive == nil && !errors.isEmpty ? "暂无预警 · 消息待同步" : "重置雷达 · 暂无预警"
        }
        if archive != nil && !errors.isEmpty { return "消息已更新 · 预警待同步" }
        if primary != nil || reference != nil { return "重置雷达 · 数据已过期" }
        return errors.isEmpty ? "重置雷达 · 等待同步" : "重置雷达 · 同步失败"
    }
}
