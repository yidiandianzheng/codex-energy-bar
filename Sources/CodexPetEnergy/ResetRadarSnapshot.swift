import Foundation

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
        if referenceIsFresh(now: now), let completed = ResetRadarSources.date(reference?.last_reset_at),
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

    func referenceIsFresh(now: Date) -> Bool {
        guard let value = reference?.probabilities?.rounded_24h, value.isFinite, (0...100).contains(value),
              let updated = ResetRadarSources.date(reference?.updated_at),
              let lastReset = ResetRadarSources.date(reference?.last_reset_at),
              now.timeIntervalSince(checkedAt) <= 1800, now.timeIntervalSince(updated) <= 1800,
              updated <= now.addingTimeInterval(300), lastReset <= updated.addingTimeInterval(300) else { return false }
        // The sites record observation and announcement at different instants of one reset.
        if let latest = primary?.data.latest_reset, latest.reset_type == "regular",
           let completed = ResetRadarSources.date(latest.announced_at),
           completed.timeIntervalSince(lastReset) > 3600 { return false }
        return true
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
        announcementProbability(now: now) != nil && referenceProbability(now: now) != nil && announcementIs24h(now: now)
    }

    func usesReferenceProbability(now: Date) -> Bool {
        referenceProbability(now: now) != nil && (announcementProbability(now: now) == nil || isAveraged(now: now))
    }

    func rawProbability(now: Date) -> Double? {
        let primaryValue = announcementProbability(now: now)
        let referenceValue = referenceProbability(now: now)
        if isAveraged(now: now), let primaryValue, let referenceValue { return (primaryValue + referenceValue) / 2 }
        return primaryValue ?? referenceValue
    }

    func probability(now: Date) -> Int? { rawProbability(now: now).map { Int($0.rounded()) } }

    func forecastIsFresh(now: Date) -> Bool { probability(now: now) != nil }

    func probabilitySourceName(now: Date) -> String {
        if isAveraged(now: now) { return "双源平均" }
        return usesReferenceProbability(now: now) ? "codex-reset.com" : "Codex Resets"
    }

    func probabilitySourceURL(now: Date) -> URL? {
        if isAveraged(now: now) { return nil }
        return usesReferenceProbability(now: now) ? ResetReferenceForecast.pageURL : ResetRadarSources.primaryURL
    }

    func compactForecastDetail(now: Date) -> String {
        if let schedule = compactScheduleText(now: now) { return schedule }
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
        if isAveraged(now: now) { return "24h参考" }
        if usesReferenceProbability(now: now) { return "24h预测" }
        guard activeWatch(now: now) != nil else { return "重置预警" }
        return announcementIs24h(now: now) ? "24h预警" : "来源预警"
    }

    func scheduleText(now: Date) -> String? {
        guard primaryIsFresh(now: now), let scheduled = primary?.data.scheduled_reset else { return nil }
        guard let time = ResetRadarSources.date(scheduled.scheduled_for) else { return "已预告，未公布时刻" }
        return (time < now ? "预告已过，待确认：" : "预告：") + ResetRadarSources.beijing(time)
    }

    /// Only a fresh probability and a dated primary reset announcement can start a countdown.
    /// Historical time windows and watch expiry timestamps are never reset deadlines.
    func countdownTarget(now: Date) -> Date? {
        guard primaryIsFresh(now: now), forecastIsFresh(now: now),
              let scheduled = primary?.data.scheduled_reset, scheduled.reset_type == "regular",
              let target = ResetRadarSources.date(scheduled.scheduled_for),
              let announced = ResetRadarSources.date(scheduled.announced_at),
              announced <= now.addingTimeInterval(300), target > announced else { return nil }
        // Compare the unrounded selection; display rounding must not start a countdown.
        let chance = rawProbability(now: now)
        guard let chance, chance >= 90 else { return nil }
        if let latest = primary?.data.latest_reset, latest.reset_type == "regular",
           let completed = ResetRadarSources.date(latest.announced_at), completed >= announced {
            return nil
        }
        if referenceIsFresh(now: now), let completed = ResetRadarSources.date(reference?.last_reset_at),
           completed >= announced { return nil }
        return target
    }

    func countdownText(now: Date) -> String? {
        guard let value = countdownValue(now: now), let target = countdownTarget(now: now) else { return nil }
        return target > now ? "更新倒计时 " + value : value
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
        guard primaryIsFresh(now: now), let scheduled = primary?.data.scheduled_reset,
              scheduled.reset_type == "regular", let date = ResetRadarSources.date(scheduled.scheduled_for) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "M/d HH:mm"
        return "预计" + formatter.string(from: date)
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
