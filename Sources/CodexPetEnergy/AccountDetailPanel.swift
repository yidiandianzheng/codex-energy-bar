import SwiftUI

/// 账户页：顶部在四个账户之间切换，下方只看选中账户的额度细节。
///
/// - Codex：复用现有额度卡（周窗口/5 小时窗口 + 重置券）。
/// - 豆包：当前时段与近 7 天两个窗口。
/// - DeepSeek：余额（无额度周期）。
/// - WorkBuddy：积分（未运行/读取失败时给出恢复提示）。
struct AccountDetailPanel: View {
    let readings: [BalanceReading]
    let advice: UsageAdvice
    let todayUsage: TodayUsageSnapshot
    let quotaLimits: [QuotaLimitReading]
    let resetCredits: RateLimitResetCreditsSummary?
    let selectedAccountID: String
    let select: (String) -> Void
    let quotaLastUpdated: Date?
    let quotaRefreshError: String?
    let balanceLastUpdated: Date?
    let balanceRefreshError: String?
    let quotaIsRefreshing: Bool
    let balanceIsRefreshing: Bool

    private var selected: BalanceReading? {
        readings.first { $0.id == selectedAccountID } ?? readings.first
    }

    var body: some View {
        VStack(spacing: 10) {
            switcher
            if let selected {
                detail(selected)
            } else {
                PanelEmptyState(
                    title: "正在读取账户",
                    systemImage: "person.crop.circle",
                    description: "账户额度会在读取完成后显示。"
                )
            }
        }
        .padding(.horizontal, EnergyVisualStyle.panelInset)
        .padding(.bottom, EnergyVisualStyle.panelInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - 账户切换

    private var switcher: some View {
        HStack(spacing: 4) {
            ForEach(readings) { reading in
                Button { select(reading.id) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: reading.systemImage)
                            .font(EnergyTypography.Icon.compact)
                        Text(reading.title)
                            .font(EnergyTypography.Detail.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(1)
                    }
                    .foregroundStyle(reading.id == selectedAccountID ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .padding(.horizontal, 2)
                    .contentShape(Rectangle())
                    .background {
                        if reading.id == selectedAccountID {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(EnergyVisualStyle.selectedFill)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(reading.id == selectedAccountID ? .isSelected : [])
            }
        }
        .padding(3)
        .background(EnergyVisualStyle.subtleFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 详情

    @ViewBuilder
    private func detail(_ reading: BalanceReading) -> some View {
        ScrollView {
            if reading.id == BalanceReading.codexID {
                VStack(alignment: .leading, spacing: 8) {
                    if let message = reading.stateMessage {
                        Text((reading.hasReading ? "旧数据 · " : "") + message)
                            .font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
                    }
                    codexDetail
                }
            } else {
                genericDetail(reading)
            }
        }
    }

    private var codexDetail: some View {
        VStack(spacing: 10) {
            if quotaLimits.isEmpty {
                PanelEmptyState(
                    title: quotaRefreshError == nil ? "正在读取账户额度" : "暂无可用额度",
                    systemImage: "gauge",
                    description: quotaRefreshError ?? "等待 Codex 返回账户额度。"
                )
                .frame(height: 220)
            } else {
                ForEach(quotaLimits) { limit in
                    QuotaLimitRow(
                        reading: limit,
                        subtitle: "\(EnergyLogic.windowDurationText(limit.windowDurationMins))周期",
                        systemImage: "gauge.with.dots.needle.50percent",
                        identityColor: EnergyVisualStyle.computeAccent
                    )
                }
                QuotaResetCreditsCard(summary: resetCredits)
            }
        }
    }

    private func genericDetail(_ reading: BalanceReading) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: reading.systemImage)
                    .font(EnergyTypography.Detail.label)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(reading.title).font(EnergyTypography.Detail.section)
                Spacer(minLength: 4)
                stateChip(reading)
            }

            switch reading.state {
            case .loading:
                Text("正在读取…").font(EnergyTypography.Detail.body).foregroundStyle(.secondary)
            case let .unconfigured(message):
                Text(message)
                    .font(EnergyTypography.Detail.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case let .failed(message):
                Text(message)
                    .font(EnergyTypography.Detail.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(recoveryHint(reading))
                    .font(EnergyTypography.Detail.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .ok, .stale:
                if case .stale(let message) = reading.state {
                    Text("旧数据 · " + message).font(EnergyTypography.Detail.caption).foregroundStyle(.secondary)
                }
                headlineValue(reading)
                if let percent = reading.referencePercent {
                    progressBar(percent: percent)
                }
                let secondaryWindows = reading.windows.filter { window in
                    !(window.isPrimary && window.remainingPercent == reading.percent)
                }
                if !secondaryWindows.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(secondaryWindows) { window in
                            windowRow(window)
                        }
                    }
                }
                HStack(spacing: 4) {
                    Text(reading.id == "doubao" ? "本窗口已用" : "今日已用·本机").font(EnergyTypography.Detail.body).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text(usageText(reading))
                        .font(EnergyTypography.Detail.label.monospacedDigit())
                }
                if let detail = reading.detail, !detail.isEmpty {
                    Text(detail)
                        .font(EnergyTypography.Detail.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(sourceNote(reading))
                .font(EnergyTypography.Detail.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func headlineValue(_ reading: BalanceReading) -> some View {
        if let percent = reading.percent {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(percent)").font(EnergyTypography.Detail.heroMetric)
                Text("%").font(EnergyTypography.Detail.unit).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if let caption = reading.caption {
                    Text(caption).font(EnergyTypography.Detail.body).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                if let prefix = reading.unitPrefix {
                    Text(prefix).font(EnergyTypography.Detail.unit).foregroundStyle(.secondary)
                }
                Text(reading.valueText ?? "—").font(EnergyTypography.Detail.heroMetric)
                if let suffix = reading.unitSuffix {
                    Text(suffix).font(EnergyTypography.Detail.unit).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let caption = reading.caption {
                    Text(caption).font(EnergyTypography.Detail.body).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func windowRow(_ window: BalanceWindowReading) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(window.title).font(EnergyTypography.Detail.body).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if let reset = window.resetAt {
                    Text("\(Self.relativeReset(reset))重置")
                        .font(EnergyTypography.Detail.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(window.remainingPercent)%")
                    .font(EnergyTypography.Detail.label.monospacedDigit())
            }
            progressBar(percent: window.remainingPercent)
        }
    }

    private func progressBar(percent: Int) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(EnergyVisualStyle.hairline)
                Capsule()
                    .fill(EnergyToneStyle.color(for: percent))
                    .frame(width: max(2, proxy.size.width * CGFloat(percent) / 100))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func stateChip(_ reading: BalanceReading) -> some View {
        switch reading.state {
        case .loading:
            chip("读取中")
        case .unconfigured:
            chip("未配置")
        case .failed:
            chip("读取失败")
        case .stale:
            chip("旧数据")
        case .ok:
            if advice.recommendedID == reading.id {
                Text("推荐")
                    .font(EnergyTypography.Detail.chip)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(EnergyVisualStyle.selectedFill, in: Capsule())
            } else {
                chip(advice.level(for: reading.id).title)
            }
        }
    }

    private func chip(_ title: String) -> some View {
        Text(title)
            .font(EnergyTypography.Detail.chip)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background {
                Capsule().strokeBorder(EnergyVisualStyle.statusChipStroke, lineWidth: 1)
            }
    }

    private func usageText(_ reading: BalanceReading) -> String {
        if reading.id == "doubao", let percent = reading.percent { return "\(100 - percent)%" }
        guard let value = todayUsage.valueText(for: reading.id) else { return reading.id == "workbuddy" ? "今日观测未知" : "采样不足" }
        if reading.id == "workbuddy" { return value + " 积分" }
        let prefix = todayUsage.currencyPrefixes[reading.id] ?? reading.unitPrefix ?? ""
        return prefix.isEmpty || value.hasPrefix(prefix) ? value : prefix + value
    }

    private func recoveryHint(_ reading: BalanceReading) -> String {
        switch reading.id {
        case "workbuddy": "打开 WorkBuddy 客户端后会自动恢复读取。"
        case "doubao": "打开豆包客户端并保持登录后重试。"
        case "deepseek": "在 sources.json 配置 API Key 后重试。"
        default: "检查本机客户端状态后重试。"
        }
    }

    private func sourceNote(_ reading: BalanceReading) -> String {
        switch reading.id {
        case "doubao": "使用当前登录态读取豆包官方额度接口，Cookie 不额外落盘。"
        case "deepseek": "按余额计费，没有额度窗口与重置时间。"
        case "workbuddy": "需要 WorkBuddy 客户端保持运行；不读取或保存其 token。"
        default: reading.id == BalanceReading.codexID
            ? "来自本机 Codex 账户额度，与本地 Token 独立计量。"
            : "只读本机账户数据。"
        }
    }

    // MARK: - 页脚

    private func footer(_ reading: BalanceReading) -> some View {
        Text(footerText(reading))
            .font(EnergyTypography.Detail.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func footerText(_ reading: BalanceReading) -> String {
        if reading.id == BalanceReading.codexID {
            if quotaIsRefreshing { return "正在刷新账户额度…" }
            if let quotaRefreshError { return quotaRefreshError }
            if let quotaLastUpdated {
                return "更新于 \(Self.clockText(quotaLastUpdated)) · 账户额度与本地 Token 独立计量"
            }
            return "账户额度与本地 Token 独立计量"
        }
        if balanceIsRefreshing { return "正在刷新账户余额…" }
        if case .ok = reading.state {} else if let balanceRefreshError { return balanceRefreshError }
        if let date = reading.updatedAt ?? balanceLastUpdated {
            return "更新于 \(Self.clockText(date)) · 只读本机账户数据"
        }
        return "只读本机账户数据"
    }

    private static func relativeReset(_ date: Date, now: Date = .now) -> String {
        let interval = date.timeIntervalSince(now)
        guard interval > 0 else { return "即将" }
        if interval < 3_600 { return "\(max(1, Int(interval / 60))) 分钟后" }
        if interval < 86_400 { return "\(Int(interval / 3_600)) 小时后" }
        return "\(Int(interval / 86_400)) 天后"
    }

    private static func clockText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
