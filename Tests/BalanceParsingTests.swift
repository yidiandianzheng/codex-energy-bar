import CryptoKit
import Foundation

var failures: [String] = []
func check(_ condition: Bool, _ message: String) { if !condition { failures.append(message) } }

// ── formatting ────────────────────────────────────────────────────────────
check(BalanceFormatting.money("51.2") == "51.20", "money keeps two fraction digits")
check(BalanceFormatting.money("6.06") == "6.06", "money keeps cents")
check(BalanceFormatting.credits("195.12000212") == "195.12", "credits round for display")
check(BalanceFormatting.credits("1000") == "1,000", "credits group thousands")
check(BalanceFormatting.percent(70.6) == 71, "percent rounds")
check(BalanceFormatting.percent(-5) == 0, "percent clamps low")
check(BalanceFormatting.percent(140) == 100, "percent clamps high")

// ── DeepSeek ──────────────────────────────────────────────────────────────
let deepSeekJSON = #"""
{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"6.06","granted_balance":"0.00","topped_up_balance":"6.06"}]}
"""#
let deepSeek = DeepSeekBalanceParser.reading(from: Data(deepSeekJSON.utf8))
check(deepSeek.state == .ok, "deepseek fixture should decode as ok")
check(deepSeek.valueText == "6.06" && deepSeek.unitPrefix == "¥", "deepseek shows CNY balance")
check(deepSeek.detail?.contains("充值 ¥6.06") == true, "deepseek keeps topped-up detail")
let mixedCurrency = DeepSeekBalanceParser.reading(from: Data(#"{"balance_infos":[{"currency":"USD","total_balance":"99"},{"currency":"CNY","total_balance":"6.06"}]}"#.utf8))
check(mixedCurrency.currency == "CNY" && mixedCurrency.numericValue == 6.06, "deepseek chooses CNY even when USD arrives first")


let deepSeekUnavailable = DeepSeekBalanceParser.reading(from: Data(#"{"is_available":false,"balance_infos":[]}"#.utf8))
if case .failed = deepSeekUnavailable.state {} else { failures.append("deepseek unavailable account must fail") }

let deepSeekBroken = DeepSeekBalanceParser.reading(from: Data("not json".utf8))
if case .failed = deepSeekBroken.state {} else { failures.append("deepseek malformed payload must fail") }

// ── WorkBuddy ─────────────────────────────────────────────────────────────
let workBuddyJSON = #"""
{"code":0,"msg":"OK","data":{"TotalCredits":"195.12000212","SubscriptionPackageName":"体验版","IsPaidUser":false,"Packages":[{"CycleTotalCapacity":"500","CycleRemainCapacity":"195.12","CycleUsedCapacity":"304.88"}]}}
"""#
let workBuddy = WorkBuddyBalanceParser.reading(from: Data(workBuddyJSON.utf8))
check(workBuddy.state == .ok, "workbuddy fixture should decode as ok")
check(workBuddy.valueText == "195.12" && workBuddy.unitSuffix == " 积分", "workbuddy shows credits")
check(workBuddy.detail?.contains("体验版") == true, "workbuddy keeps plan name")
check(workBuddy.percent == 39, "workbuddy percent derives from package capacity")

let workBuddyError = WorkBuddyBalanceParser.reading(from: Data(#"{"code":401,"msg":"token invalid"}"#.utf8))
if case .failed(let message) = workBuddyError.state, message.contains("token invalid") {
} else {
    failures.append("workbuddy business error must surface the upstream message")
}

// ── 豆包 ──────────────────────────────────────────────────────────────────
let doubaoJSON = #"""
{"code":0,"msg":"","data":{"current_subscription":{"display":{"short_name":"标准套餐"}},
"incentive_quota_section":{"window_limit_groups":[{"window_limits":[{"end_time":1795163975573,"used_percent":100,"window_type":3}]}]},
"window_limit_section":{"window_limit_groups":[{"window_limits":[
{"end_time":1792666313006,"used_percent":84,"window_type":1},
{"end_time":1792819135023,"used_percent":29,"window_type":2}]}]}}}
"""#
let doubao = DoubaoQuotaParser.reading(from: Data(doubaoJSON.utf8))
check(doubao.state == .ok, "doubao fixture should decode as ok")
check(doubao.valueText == "16", "doubao features the current rolling window")
check(doubao.caption?.contains("当前时段") == true, "doubao labels the rolling window like the client")
check(doubao.windows.map(\.id) == ["H5", "D7"], "doubao keeps membership windows and drops spent incentive pools")
check(doubao.detail?.contains("近 7 天 71%") == true, "doubao keeps the weekly window detail")

let doubaoExpired = DoubaoQuotaParser.reading(from: Data(#"{"code":710012001,"msg":"登录已过期，请重新登录"}"#.utf8))
if case .failed(let message) = doubaoExpired.state, message.contains("重新登录") {
} else {
    failures.append("doubao should explain an expired login")
}

let doubaoEmpty = DoubaoQuotaParser.reading(from: Data(#"{"code":0,"data":{}}"#.utf8))
if case .failed = doubaoEmpty.state {} else { failures.append("doubao without windows must fail") }


// ── 千问办公 ──────────────────────────────────────────────────────────────
let qwenFreeJSON = #"""
{"ok":true,"data":{"available":true,"aggregateRemainingPercent":null,"isQuotaExceeded":false,
"planCredits":{"total":0,"used":0,"remaining":1989.5875,"percentage":0,"unit":"credits"},
"addOnCredits":null,"sharedResourcePackage":null,"isTeamPlan":false}}
"""#
let qwenProfileJSON = #"{"ok":true,"data":{"tier":"个人免费版","email":"demo@example.com"}}"#
let qwenFree = QwenWorkUsageParser.reading(from: Data(qwenFreeJSON.utf8), profile: Data(qwenProfileJSON.utf8))
check(qwenFree.state == .ok, "qwenwork fixture should decode as ok")
check(qwenFree.valueText == "1,989.6" && qwenFree.unitSuffix == " 积分", "qwenwork shows the remaining points")
check(qwenFree.percent == nil, "qwenwork without a plan denominator has no percentage")
check(qwenFree.detail?.contains("个人免费版") == true, "qwenwork keeps the account tier")
check(qwenFree.sourceIdentity?.hasPrefix("qwenwork:") == true, "qwenwork derives an identity for today's usage ledger")
check(QwenWorkUsageParser.reading(from: Data(qwenFreeJSON.utf8)).sourceIdentity == nil,
      "qwenwork without a profile keeps today's usage unknown")

let qwenPaidJSON = #"""
{"ok":true,"data":{"available":true,"aggregateRemainingPercent":null,"isQuotaExceeded":false,
"planCredits":{"total":1000,"used":250,"remaining":750,"percentage":25,"unit":"credits"}}}
"""#
let qwenPaid = QwenWorkUsageParser.reading(from: Data(qwenPaidJSON.utf8))
check(qwenPaid.percent == 75 && qwenPaid.caption?.contains("套餐") == true,
      "qwenwork derives a remaining percentage from plan credits")
check(qwenPaid.detail?.contains("套餐 剩 750 / 1,000") == true, "qwenwork keeps both the remaining and total plan credits")
check(QwenWorkUsageParser.reading(from: Data(qwenPaidJSON.utf8)).sourceIdentity == nil, "missing profile never guesses account identity")

let qwenExceeded = QwenWorkUsageParser.reading(from: Data(#"""
{"ok":true,"data":{"available":true,"isQuotaExceeded":true,
"planCredits":{"total":100,"used":100,"remaining":0,"percentage":100}}}
"""#.utf8))
check(qwenExceeded.percent == 0 && qwenExceeded.caption == "额度已用尽", "qwenwork marks an exhausted plan")

let qwenLoggedOut = QwenWorkUsageParser.reading(from: Data(#"{"ok":true,"data":{"available":false,"message":"User not logged in"}}"#.utf8))
if case .unconfigured(let message) = qwenLoggedOut.state, message.contains("登录") {
} else {
    failures.append("qwenwork should explain a signed-out client")
}

let qwenBroken = QwenWorkUsageParser.reading(from: Data("not json".utf8))
if case .failed = qwenBroken.state {} else { failures.append("qwenwork malformed payload must fail") }

let qwenEnvelopeError = QwenWorkUsageParser.reading(from: Data(#"""
{"ok":false,"error":{"message":"quota backend unavailable"}}
"""#.utf8))
if case .failed(let message) = qwenEnvelopeError.state, message.contains("quota backend unavailable") {
} else {
    failures.append("qwenwork must surface the MCP error envelope")
}

let qwenInvalid = QwenWorkUsageParser.reading(from: Data(#"""
{"ok":true,"data":{"available":true,"planCredits":{"total":"1e300","used":"nan","remaining":"inf"}}}
"""#.utf8))
if case .failed = qwenInvalid.state {} else {
    failures.append("qwenwork must not turn invalid points into an exhausted quota")
}

let qwenTokenMissing = QwenWorkUsageParser.reading(from: Data(#"{"ok":true,"data":{"available":false,"message":"Access token not available"}}"#.utf8))
if case .unconfigured = qwenTokenMissing.state {} else {
    failures.append("qwenwork signed-out token state must hide like an unconfigured account")
}

// ── Qoder CN ──────────────────────────────────────────────────────────────
let qoderJSON = #"""
{"userId":"qoder-demo","isQuotaExceeded":false,"expiresAt":1794076800,
"userQuota":{"total":300,"used":2,"remaining":298},"addOnQuota":{"total":100,"used":25,"remaining":75}}
"""#
let qoderPlan = #"{"plan_tier_name":"Pro Trial"}"#
let qoder = QoderUsageParser.reading(usage: Data(qoderJSON.utf8), plan: Data(qoderPlan.utf8))
check(qoder.state == .ok, "qoder fixture should decode as ok")
check(qoder.valueText == "373" && qoder.unitSuffix == " 积分", "qoder sums plan and add-on points")
check(qoder.percent == 93, "qoder derives the remaining percentage from its own capacity")
check(qoder.detail?.contains("Pro Trial") == true && qoder.detail?.contains("附加") == true,
      "qoder keeps the plan tier and the add-on portion")
check(qoder.sourceIdentity?.hasPrefix("qoder:") == true, "qoder derives an identity for today's usage ledger")

let qoderExceeded = QoderUsageParser.reading(usage: Data(#"""
{"isQuotaExceeded":true,"userQuota":{"total":300,"used":300,"remaining":0}}
"""#.utf8))
check(qoderExceeded.percent == 0 && qoderExceeded.caption == "额度已用尽", "qoder marks an exhausted plan")

let qoderMissingQuota = QoderUsageParser.reading(usage: Data(#"{"userId":"qoder-demo"}"#.utf8))
if case .failed = qoderMissingQuota.state {} else {
    failures.append("qoder without quota sections must fail instead of inventing a balance")
}

let qoderBroken = QoderUsageParser.reading(usage: Data("not json".utf8))
if case .failed = qoderBroken.state {} else { failures.append("qoder malformed payload must fail") }

// ── Trae CN ───────────────────────────────────────────────────────────────
let traeJSON = #"""
{"code":0,"usage_summary":{"total_amount":600,"consumed_amount":23.1},
"user_entitlement_pack_list":[
{"group_name":"每月登录积分","expire_time":1793376000000,"entitlement_base_info":{"user_id":"trae-demo","quota":{"credits_limit":500}},"usage":{"credits_amount":20}},
{"group_name":"每日签到","expire_time":1793376000000,"entitlement_base_info":{"quota":{"credits_limit":100}},"usage":{"credits_amount":3.1}}]}
"""#
let trae = TraeUsageParser.reading(usage: Data(traeJSON.utf8))
check(trae.state == .ok, "trae fixture should decode as ok")
check(trae.valueText == "576.9" && trae.unitSuffix == " 积分", "trae uses the usage summary for the remaining points")
check(trae.percent == 96, "trae derives the remaining percentage from the summary")
check(trae.detail?.contains("已用 23.1 / 600") == true, "trae keeps the used and total points")
check(trae.sourceIdentity?.hasPrefix("trae:") == true, "trae falls back to the pack user id for identity")

let traeNoPacks = TraeUsageParser.reading(usage: Data(#"{"code":0,"user_entitlement_pack_list":[]}"#.utf8))
if case .unconfigured = traeNoPacks.state {} else {
    failures.append("trae without entitlement packs should ask for a refresh")
}

let traeUnlimited = TraeUsageParser.reading(usage: Data(#"""
{"code":0,"user_entitlement_pack_list":[{"entitlement_base_info":{"quota":{"credits_limit":-1}}}]}
"""#.utf8))
check(traeUnlimited.state == .ok && traeUnlimited.percent == nil && traeUnlimited.caption == "积分不限",
      "trae unlimited packs stay unrated instead of becoming 100%")

let traeError = TraeUsageParser.reading(usage: Data(#"{"code":40001,"message":"token expired"}"#.utf8))
if case .failed(let message) = traeError.state, message.contains("token expired") {
} else {
    failures.append("trae business errors must surface the upstream message")
}

let traeBroken = TraeUsageParser.reading(usage: Data("not json".utf8))
if case .failed = traeBroken.state {} else { failures.append("trae malformed payload must fail") }

// ── Gemini ────────────────────────────────────────────────────────────────
let geminiJSON = #"""
{"userTier":"TIER1","usage":[
{"budgetPoolType":"GXU_WEEKLY","gxu":{"windowRefreshesAt":"2026-10-27T14:23:06.029147Z","pctUsed":0.02,"title":"Weekly limit"}},
{"budgetPoolType":"GXU_FIVE_HOURLY","gxu":{"windowRefreshesAt":"2026-10-26T09:23:06.029036Z","pctUsed":0.4,"title":"Current usage"}}]}
"""#
let gemini = GeminiUsageParser.reading(usage: Data(geminiJSON.utf8), gaiaID: "gaia-demo")
check(gemini.state == .ok, "gemini fixture should decode as ok")
check(gemini.valueText == "60" && gemini.unitSuffix == "%", "gemini headline is the remaining 5-hour window")
check(gemini.percent == 60, "gemini converts pctUsed into remaining percentage")
check(gemini.windows.count == 2 && gemini.windows[0].id == GeminiUsageParser.fiveHourID
      && gemini.windows[0].isPrimary, "gemini promotes the 5-hour window")
check(gemini.windows[1].id == GeminiUsageParser.weeklyID && gemini.windows[1].remainingPercent == 98,
      "gemini keeps the weekly window as a secondary line")
check(gemini.detail?.contains("Pro") == true && gemini.detail?.contains("本周已用 2%") == true,
      "gemini keeps the plan tier and weekly usage")
check(gemini.sourceIdentity?.hasPrefix("gemini:") == true, "gemini derives an identity from the Gaia ID")

let geminiExhausted = GeminiUsageParser.reading(usage: Data(#"""
{"userTier":"TIER1","usage":[{"budgetPoolType":"GXU_FIVE_HOURLY","gxu":{"pctUsed":1.0}}]}
"""#.utf8))
check(geminiExhausted.percent == 0 && geminiExhausted.caption == "当前用量已用尽",
      "gemini marks an exhausted current window")

let geminiMissing = GeminiUsageParser.reading(usage: Data(#"{"userTier":"TIER1","usage":[]}"#.utf8))
if case .failed = geminiMissing.state {} else {
    failures.append("gemini without usage windows must fail instead of inventing a quota")
}

let geminiBroken = GeminiUsageParser.reading(usage: Data("not json".utf8))
if case .failed = geminiBroken.state {} else { failures.append("gemini malformed payload must fail") }

func sampleVarint(_ value: UInt64) -> [UInt8] {
    var remaining = value
    var bytes: [UInt8] = []
    repeat {
        var byte = UInt8(remaining & 0x7f)
        remaining >>= 7
        if remaining > 0 { byte |= 0x80 }
        bytes.append(byte)
    } while remaining > 0
    return bytes
}
func sampleField(_ field: UInt64, _ payload: [UInt8]) -> [UInt8] {
    sampleVarint((field << 3) | 2) + sampleVarint(UInt64(payload.count)) + payload
}

let sampleKey = Data(repeating: 0x5c, count: 32)
let sampleNonce = Data(repeating: 0x2a, count: 12)
let samplePlain = Data(sampleField(4, Array("1//sample-refresh-token".utf8)))
let sealed = try! AES.GCM.seal(samplePlain, using: SymmetricKey(data: sampleKey),
                               nonce: AES.GCM.Nonce(data: sampleNonce))
let samplePayload = [UInt8](sealed.ciphertext) + [UInt8](sealed.tag)
var samplePreamble: [UInt8] = [0x08, 0x01, 0x10, 0x01, 0x18, 0x01]
samplePreamble += sampleField(4, [UInt8](sampleNonce))
samplePreamble += sampleVarint((5 << 3) | 0) + sampleVarint(UInt64(samplePayload.count))
let sampleContainer = Data([0x2e, 0xba, 0xfe, 0xca, 0x2e, 0xba, 0xfe, 0xca])
    + Data([UInt8(samplePreamble.count & 0xff), UInt8((samplePreamble.count >> 8) & 0xff), 0, 0])
    + Data(samplePreamble) + Data(samplePayload)
let decrypted = GeminiCredentialVault.decryptContainer(sampleContainer, key: sampleKey)
check(decrypted != nil, "gemini container decrypts with the credentials key")
check(decrypted.flatMap { GeminiCredentialVault.parseStringField(4, in: $0) } == "1//sample-refresh-token",
      "gemini reads the refresh token from the decrypted container")
check(GeminiCredentialVault.decryptContainer(sampleContainer, key: Data(repeating: 0, count: 32)) == nil,
      "gemini container rejects the wrong key")

let sampleKeyData: [UInt8] = sampleVarint((1 << 3) | 0) + sampleVarint(1) + sampleField(4, [UInt8](sampleKey))
let sampleKeystore = Data(sampleField(2, sampleKeyData))
check(GeminiCredentialVault.extractCredentialsKey(from: sampleKeystore) == sampleKey,
      "gemini extracts KEY_ID_CREDENTIALS (id 1) from the keychain protobuf")
check(GeminiBalanceClient.clientSecret.hasPrefix("GOCSPX-") && GeminiBalanceClient.clientSecret.count == 35,
      "gemini client secret decodes to a Google desktop credential")

// ── usage advisor ─────────────────────────────────────────────────────────
func reading(_ id: String, _ title: String, value: String?, prefix: String? = nil, suffix: String? = nil,
             percent: Int?, windows: [BalanceWindowReading] = []) -> BalanceReading {
    BalanceReading(id: id, title: title, systemImage: "circle", valueText: value,
                   unitPrefix: prefix, unitSuffix: suffix, caption: "\(title)剩余", detail: nil,
                   percent: percent, windows: windows, state: .ok, sourceURL: nil, updatedAt: Date(),
                   numericValue: value.flatMap(Double.init), currency: prefix == "¥" ? "CNY" : nil)
}

let now = Date()
let advisorReadings: [BalanceReading] = [
    reading("codex", "Codex", value: "3", suffix: "%", percent: 3,
            windows: [BalanceWindowReading(id: "w", title: "周额度", remainingPercent: 3, resetAt: now.addingTimeInterval(6 * 86400))]),
    reading("deepseek", "DeepSeek", value: "43.06", prefix: "¥", percent: nil),
    reading("doubao", "豆包", value: "71", suffix: "%", percent: 71, windows: [
        BalanceWindowReading(id: "H5", title: "5 小时", remainingPercent: 15, resetAt: now.addingTimeInterval(3600)),
        BalanceWindowReading(id: "D7", title: "近 7 天", remainingPercent: 71, resetAt: now.addingTimeInterval(3 * 86400)),
    ]),
    reading("workbuddy", "WorkBuddy", value: "195.12", suffix: " 积分", percent: 3),
]
let advice = AIUsageAdvisor.advise(readings: advisorReadings, now: now)
check(advice.recommendedID == "doubao" && advice.levels["doubao"] == .tight, "advisor prefers usable subscription quota while respecting its tighter rolling window")
check(advice.levels["codex"] == .critical && advice.levels["workbuddy"] == .critical, "advisor flags depleted accounts")
check(advice.levels["deepseek"] == .ample, "advisor treats a healthy cash balance as ample")
check(advice.compactText.contains("推荐"), "compact advice starts with the recommendation")
check(advice.detail.contains("15%") && !advice.detail.contains("71%"), "advice explains the actual limiting window")
check(AIUsageAdvisor.level(for: qwenFree, now: Date()) == .unknown,
      "a usable credit balance without a quota percentage is unrated, not unavailable")
let qwenAdvice = AIUsageAdvisor.advise(readings: [qwenFree, reading("doubao", "豆包", value: "71", suffix: "%", percent: 71,
    windows: [BalanceWindowReading(id: "H5", title: "5 小时", remainingPercent: 71, resetAt: nil)])], now: Date())
check(qwenAdvice.recommendedID == "doubao", "percentage-based quota outranks an unrated credit balance")
let qwenFallback = AIUsageAdvisor.advise(readings: [qwenFree, reading("codex", "Codex", value: "1", suffix: "%", percent: 1)], now: Date())
check(qwenFallback.recommendedID == "codex" && qwenFallback.levels["qwenwork"] == .unknown,
      "credit balances never become a fallback recommendation")

let allCritical = AIUsageAdvisor.advise(readings: [
    reading("codex", "Codex", value: "2", suffix: "%", percent: 2),
    reading("deepseek", "DeepSeek", value: "5", prefix: "¥", percent: nil),
    reading("workbuddy", "WorkBuddy", value: "10", suffix: " 积分", percent: 1),
], now: now)
check(allCritical.headline.contains("偏低"), "advisor warns when every account is critical")
check(allCritical.recommendedID == "codex", "advisor can choose a still-usable critical account")

let exhausted = AIUsageAdvisor.advise(readings: [
    reading("codex", "Codex", value: "0", suffix: "%", percent: 0),
    reading("deepseek", "DeepSeek", value: "0", prefix: "¥", percent: nil),
], now: now)
check(exhausted.recommendedID == nil, "no exhausted account is recommended")

// ── compact-bar visibility (auto-hide inactive accounts) ─────────────────
let visibilityReadings: [BalanceReading] = [
    reading("codex", "Codex", value: "2", suffix: "%", percent: 2),
    reading("deepseek", "DeepSeek", value: "18.54", prefix: "¥", percent: nil),
    reading("doubao", "豆包", value: "55", suffix: "%", percent: 55),
    BalanceProvider.workbuddy.failed("WorkBuddy 未运行（找不到本地通道）"),
    BalanceProvider.qwenwork.failed("千问办公未运行（找不到本地 MCP 通道）"),
]
let closedClients = AccountVisibility.visibleReadings(visibilityReadings, runningClients: [], autoHide: true)
check(closedClients.map(\.id) == ["codex", "deepseek"],
      "clients closed: compact bar keeps Codex and the server-side DeepSeek balance")
let openClients = AccountVisibility.visibleReadings(visibilityReadings,
                                                     runningClients: ["doubao", "workbuddy", "qwenwork"], autoHide: true)
check(openClients.map(\.id) == ["codex", "deepseek", "doubao", "workbuddy", "qwenwork"],
      "running clients make their accounts visible in provider order")
check(AccountVisibility.visibleReadings(visibilityReadings, runningClients: [], autoHide: false).count == 5,
      "turning auto-hide off shows every account again")
let hiddenWithUnconfigured = AccountVisibility.hiddenIDs(
    readings: [BalanceProvider.deepseek.unconfigured("未找到 DeepSeek API Key"),
               BalanceProvider.workbuddy.unconfigured("已在配置中关闭 WorkBuddy 读取")],
    runningClients: ["doubao", "workbuddy"], autoHide: true)
check(hiddenWithUnconfigured == ["deepseek", "workbuddy"],
      "unconfigured accounts leave the compact bar even while their client runs")
check(AccountVisibility.hiddenIDs(
    readings: [BalanceProvider.qwenwork.unconfigured("请先在千问办公客户端登录后重试")],
    runningClients: ["qwenwork"], autoHide: true) == ["qwenwork"],
    "signed-out 千问办公 hides even while its client is open")
check(AccountVisibility.hiddenIDs(readings: [visibilityReadings[0]], runningClients: [], autoHide: true).isEmpty,
      "Codex is never hidden")
check(AccountVisibility.hiddenIDs(
    readings: [BalanceProvider.gemini.placeholder()],
    runningClients: [], autoHide: true).isEmpty,
    "Gemini stays on the compact bar even when its app is closed")
check(AccountVisibility.clientBundleIdentifiers["gemini"] == nil,
      "Gemini has no client-running dependency")
check(AccountVisibility.clientBundleIdentifiers["doubao"] == "com.work.pc.doubao"
      && AccountVisibility.clientBundleIdentifiers["workbuddy"] == "com.tencent.workbuddy.mac"
      && AccountVisibility.clientBundleIdentifiers["qwenwork"] == "cn.qwenwork.desktop.mac"
      && AccountVisibility.clientBundleIdentifiers["qoder"] == "com.qodercn.app"
      && AccountVisibility.clientBundleIdentifiers["trae"] == "cn.trae.app",
      "client bundle identifiers stay pinned to their desktop apps")
check(AccountVisibility.hiddenIDs(
    readings: [BalanceProvider.qoder.placeholder(), BalanceProvider.trae.placeholder()],
    runningClients: [], autoHide: true) == ["qoder", "trae"],
    "closed Qoder CN / Trae CN clients leave the compact bar")

if failures.isEmpty {
    print("Balance parsing tests passed")
} else {
    print(failures.joined(separator: "\n"))
    exit(1)
}
