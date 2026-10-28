import Foundation

var failures: [String] = []
func check(_ condition: Bool, _ message: String) { if !condition { failures.append(message) } }

// ── 账户网格双排名排序（AccountRanking） ──────────────────────────────────

let suite = "AccountRankingTests"
UserDefaults.standard.removePersistentDomain(forName: suite)

func freshTracker() -> AccountUsageTracker {
    AccountUsageTracker(defaults: UserDefaults(suiteName: suite)!)
}

let now = Date(timeIntervalSince1970: 1_800_000_000)
let ids = ["codex", "deepseek", "doubao", "workbuddy", "workbuddyintl", "dumate", "qwenwork", "qoder", "trae"]

// 1. 无任何使用记录 → 纯能力排序，百度搭子垫底
let idle = AccountRankingEngine(tracker: freshTracker()).orderedIDs(ids, now: now)
check(idle.first == "codex", "zero usage: codex ranks first (capability 100)")
check(idle.last == "dumate", "zero usage: 百度搭子 ranks last (user feedback: weakest)")
check(idle == ["codex", "deepseek", "workbuddy", "workbuddyintl", "qwenwork", "qoder", "doubao", "trae", "dumate"],
      "zero usage: full order follows capability weights, got \(idle)")

// 2. 高频使用也不能把 Codex 挤下第一；豆包在其余账户中升到最前
let heavyTracker = freshTracker()
for _ in 0..<20 { heavyTracker.recordOpen(id: "doubao", now: now) }
let heavy = AccountRankingEngine(tracker: heavyTracker).orderedIDs(ids, now: now)
check(heavy.first == "codex", "heavy usage: codex stays first, got \(heavy.first ?? "nil")")
check(heavy.count > 1 && heavy[1] == "doubao", "heavy usage: 豆包 moves to second, got \(heavy.prefix(2))")
check(heavy.last == "dumate", "heavy usage: 百度搭子 still last")

// 3. 频率让同档账户拉开：豆包用 5 次 → 排在 trae 前面（两者能力同为 70）
let midTracker = freshTracker()
for _ in 0..<5 { midTracker.recordOpen(id: "doubao", now: now) }
let mid = AccountRankingEngine(tracker: midTracker).orderedIDs(ids, now: now)
check((mid.firstIndex(of: "doubao") ?? 99) < (mid.firstIndex(of: "trae") ?? 99),
      "mid usage: 豆包 outranks trae (same capability, frequency breaks tie)")

// 4. Codex 固定第一；手动置顶决定其余账户的顺序
let pinSuite = "AccountRankingPinTests"
UserDefaults.standard.removePersistentDomain(forName: suite)
let pins = AccountPinStore(defaults: UserDefaults(suiteName: pinSuite)!)
pins.toggle("trae")
pins.toggle("doubao")
let pinned = AccountRankingEngine(tracker: freshTracker(), pinnedIDs: pins.orderedIDs).orderedIDs(ids, now: now)
check(pinned.first == "codex", "pin: codex stays first, got \(pinned.first ?? "nil")")
check(pinned.count > 2 && pinned[1] == "doubao", "pin: last pinned (豆包) sorts first after codex")
check(pinned[2] == "trae", "pin: earlier pinned (trae) third")
pins.toggle("doubao")
let unpinned = AccountRankingEngine(tracker: freshTracker(), pinnedIDs: pins.orderedIDs).orderedIDs(ids, now: now)
check(unpinned.first == "codex" && unpinned[1] == "trae",
      "unpin: codex first, trae still pinned second, got \(unpinned.prefix(2))")
pins.toggle("trae")
let cleared = AccountRankingEngine(tracker: freshTracker(), pinnedIDs: pins.orderedIDs).orderedIDs(ids, now: now)
check(cleared.first == "codex", "unpin: clearing all pins keeps codex first, got \(cleared.first ?? "nil")")

// 5. 稳定排序：同分保持原始顺序（doubao 与 trae 能力同为 70 且都无记录）
check(idle.firstIndex(of: "doubao")! < idle.firstIndex(of: "trae")!, "stable: tie keeps original order")

// 6. 衰减：3 天前的一次打开 ≈ 今天 0.5 次；10 天后只剩 ~0.1
let decayTracker = freshTracker()
decayTracker.recordOpen(id: "deepseek", now: now.addingTimeInterval(-3 * 86_400))
let half = decayTracker.decayedScore(id: "deepseek", now: now)
check(abs(half - 0.5) < 0.01, "decay: one open 3 days ago scores 0.5, got \(half)")
decayTracker.recordOpen(id: "deepseek", now: now.addingTimeInterval(-10 * 86_400))
let far = decayTracker.decayedScore(id: "deepseek", now: now)
check(far < 0.65 && far > 0.5, "decay: 10-day-old open adds only ~0.1, got \(far)")

// 7. 窗口裁剪：14 天前的事件被丢弃
let windowTracker = freshTracker()
windowTracker.recordOpen(id: "qwenwork", now: now.addingTimeInterval(-20 * 86_400))
check(windowTracker.decayedScore(id: "qwenwork", now: now) == 0, "window: events older than 14 days are dropped")

// 8. 每账户 500 条上限
let capTracker = freshTracker()
for _ in 0..<600 { capTracker.recordOpen(id: "codex", now: now) }
let capped = capTracker.decayedScore(id: "codex", now: now)
check(abs(capped - 500) < 0.01, "cap: at most 500 events counted, got \(capped)")

// 9. 单元素与空列表不崩
check(AccountRankingEngine(tracker: freshTracker()).orderedIDs(["codex"], now: now) == ["codex"], "single id passthrough")
check(AccountRankingEngine(tracker: freshTracker()).orderedIDs([], now: now).isEmpty, "empty list passthrough")

// 10. reset 清空后回到能力排序
let resetTracker = freshTracker()
for _ in 0..<10 { resetTracker.recordOpen(id: "doubao", now: now) }
resetTracker.reset()
check(AccountRankingEngine(tracker: resetTracker).orderedIDs(ids, now: now).first == "codex", "reset: usage log cleared, capability order restored")

UserDefaults.standard.removePersistentDomain(forName: suite)
UserDefaults.standard.removePersistentDomain(forName: pinSuite)

if failures.isEmpty {
    print("Account ranking tests passed")
} else {
    print(failures.joined(separator: "\n"))
    exit(1)
}
