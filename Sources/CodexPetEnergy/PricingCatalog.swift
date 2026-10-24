import Foundation

extension PricingCatalog {
    /// Verified on 2026-10-23 20:50 (Asia/Shanghai) from the public price pages.
    /// Prices are static local data: the app never fetches price pages at runtime.
    static let builtIn: PricingCatalog = {
        let timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        func moment(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? Date()
        }

        let deepseekRule = PricingRule.weekdayPeak(
            weekdays: [2, 3, 4, 5, 6],
            ranges: [
                PricingTimeRange(start: "09:00", end: "12:00"),
                PricingTimeRange(start: "14:00", end: "18:00"),
            ],
            excludeHolidays: true,
            weekendOffPeak: true
        )
        let workBuddyNightRule = PricingRule.dailyDiscount(startMinute: 23 * 60, endMinute: 8 * 60)
        let qwenNightRule = PricingRule.dailyDiscount(startMinute: 22 * 60, endMinute: 8 * 60)

        let flashPeak = PricingTokenPrice(inputMiss: 2, inputHit: 0.04, output: 8)
        let flashOffPeak = PricingTokenPrice(inputMiss: 1, inputHit: 0.02, output: 4)
        let proPeak = PricingTokenPrice(inputMiss: 9, inputHit: 0.30, output: 27)
        let proOffPeak = PricingTokenPrice(inputMiss: 4.5, inputHit: 0.15, output: 13.5)

        let models: [PricingModel] = [
            PricingModel(
                id: "deepseek-flash",
                name: "DeepSeek Flash",
                shortName: "DeepSeek Flash",
                vendor: "DeepSeek",
                channel: "官方 API",
                tier: .peakValley(peak: flashPeak, offPeak: flashOffPeak, ruleID: "deepseek-peak"),
                note: "1M 上下文 · 支持图像 · 费用按请求完成时段计",
                capability: "推理 / 编程 / 多模态",
                sourceURL: "https://api-docs.deepseek.com/zh-cn/quick_start/pricing/"
            ),
            PricingModel(
                id: "deepseek-v4-pro",
                name: "DeepSeek V4 Pro",
                shortName: "DeepSeek Pro",
                vendor: "DeepSeek",
                channel: "官方 API",
                tier: .peakValley(peak: proPeak, offPeak: proOffPeak, ruleID: "deepseek-peak"),
                note: "1M 上下文 · 不支持图像 · 费用按请求完成时段计",
                capability: "强推理 / 复杂任务",
                sourceURL: "https://api-docs.deepseek.com/zh-cn/quick_start/pricing/"
            ),
            PricingModel(
                id: "doubao-seed-2.0-mini",
                name: "豆包 Seed 2.0 Mini",
                shortName: "豆包 Mini",
                vendor: "字节跳动",
                channel: "火山方舟",
                tier: .flat(PricingTokenPrice(inputMiss: 0.2, inputHit: 0.04, output: 2)),
                note: "≤32K 档；32–128K / 128–256K 逐档上浮",
                capability: "轻量文本 / 批量",
                sourceURL: "https://docs.volcengine.com/docs/ark/model-pricing?lang=zh"
            ),
            PricingModel(
                id: "doubao-seed-2.0-lite",
                name: "豆包 Seed 2.0 Lite",
                shortName: "豆包 Lite",
                vendor: "字节跳动",
                channel: "火山方舟",
                tier: .flat(PricingTokenPrice(inputMiss: 0.6, inputHit: 0.12, output: 3.6)),
                note: "≤32K 档；超档上浮",
                capability: "日常文本 / 内容",
                sourceURL: "https://docs.volcengine.com/docs/ark/model-pricing?lang=zh"
            ),
            PricingModel(
                id: "doubao-seed-2.1-pro",
                name: "豆包 Seed 2.1 Pro",
                shortName: "豆包 Pro",
                vendor: "字节跳动",
                channel: "火山方舟",
                tier: .flat(PricingTokenPrice(inputMiss: 6, inputHit: 1.2, output: 30)),
                note: "≤1024K 档",
                capability: "强推理 / 多模态",
                sourceURL: "https://docs.volcengine.com/docs/ark/model-pricing?lang=zh"
            ),
            PricingModel(
                id: "qwen3.8-flash",
                name: "千问 Qwen3.8 Flash",
                shortName: "千问 Flash",
                vendor: "阿里云",
                channel: "百炼 API",
                tier: .flat(PricingTokenPrice(inputMiss: 0.8, inputHit: 0.1, output: 2.7)),
                note: "标准价 · Batch 限时 5 折 · 夜间 4 折仅 Qoder / Meoo 渠道",
                capability: "多模态 / 长上下文",
                sourceURL: "https://developer.aliyun.com/article/1761526"
            ),
        ]

        let channels: [PricingChannelNote] = [
            PricingChannelNote(
                id: "workbuddy-deepseek",
                title: "WorkBuddy 内置 DeepSeek",
                detail: "Flash / V4 Pro · 非高峰 5 折",
                discountLabel: "5折",
                discount: 0.5,
                ruleID: "deepseek-peak",
                note: "积分渠道，不与人民币混排；以客户端夜间折扣标识为准",
                isSubscription: false
            ),
            PricingChannelNote(
                id: "workbuddy-glm52",
                title: "WorkBuddy 内置 GLM-5.2",
                detail: "23:00–08:00 积分立减",
                discountLabel: "立减",
                discount: nil,
                ruleID: "workbuddy-night",
                note: "活动幅度以客户端为准",
                isSubscription: false
            ),
            PricingChannelNote(
                id: "qwen-night",
                title: "千问 Night Plan",
                detail: "22:00–08:00 4 折",
                discountLabel: "4折",
                discount: 0.4,
                ruleID: "qwen-night",
                note: "Qoder / Meoo 客户端专属，不适用于百炼通用 API",
                isSubscription: false
            ),
            PricingChannelNote(
                id: "qwen-batch",
                title: "千问 Batch Chat",
                detail: "限时 5 折，非分时",
                discountLabel: "5折",
                discount: 0.5,
                ruleID: nil,
                note: "按 Batch 模式生效，不随钟点变化",
                isSubscription: false
            ),
            PricingChannelNote(
                id: "codex",
                title: "Codex",
                detail: "订阅额度，不按 token 计价",
                discountLabel: nil,
                discount: nil,
                ruleID: nil,
                note: "价格灯只回答 API / 积分渠道的边际成本",
                isSubscription: true
            ),
            PricingChannelNote(
                id: "qwenwork",
                title: "千问办公 Credits",
                detail: "订阅 Credits，无分时价",
                discountLabel: nil,
                discount: nil,
                ruleID: nil,
                note: "用量随订阅额度变化，不参与价格灯排序",
                isSubscription: true
            ),
        ]

        let changes: [PricingChangeEvent] = [
            PricingChangeEvent(
                id: "deepseek-search-fetch",
                date: moment(2026, 11, 1, 0, 0),
                title: "DeepSeek Search / Fetch 开始计费",
                detail: "按成功请求计费：¥5 / 1,000 次。Codex 等服务端搜索届时不再免费。"
            ),
            PricingChangeEvent(
                id: "holiday-2027",
                date: moment(2026, 11, 1, 0, 0),
                title: "2027 年节假日表待更新",
                detail: "国务院公布 2027 年放假安排后更新；未更新前，2027 年元旦会按工作日峰时显示。"
            ),
        ]

        return PricingCatalog(
            version: "2026-10-23",
            checkedAt: moment(2026, 10, 23, 20, 50),
            timeZone: timeZone,
            models: models,
            rules: [
                "deepseek-peak": deepseekRule,
                "workbuddy-night": workBuddyNightRule,
                "qwen-night": qwenNightRule,
            ],
            holidays: PricingHolidayCalendar(days: [
                // 2026 中秋：9/25–9/27；国庆：10/1–10/7（国务院办公厅通知）。
                // 这些日期已过去，保留用于边界回归；2027 年表待公布。
                2026 * 10_000 + 9 * 100 + 25,
                2026 * 10_000 + 9 * 100 + 26,
                2026 * 10_000 + 9 * 100 + 27,
                2026 * 10_000 + 10 * 100 + 1,
                2026 * 10_000 + 10 * 100 + 2,
                2026 * 10_000 + 10 * 100 + 3,
                2026 * 10_000 + 10 * 100 + 4,
                2026 * 10_000 + 10 * 100 + 5,
                2026 * 10_000 + 10 * 100 + 6,
                2026 * 10_000 + 10 * 100 + 7,
            ]),
            channels: channels,
            changes: changes,
            profile: .default,
            thresholds: PricingThresholds(greenMax: 2, redMin: 6),
            sourceLine: "价格核对 2026-10-23 20:50（北京时间）· DeepSeek 官方 / 火山方舟 / 阿里云百炼 / WorkBuddy 公开页"
        )
    }()
}
