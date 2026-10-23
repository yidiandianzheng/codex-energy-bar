import Foundation

var failures: [String] = []
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { failures.append(message) }
}
let now = ISO8601DateFormatter.standard.date(from: "2026-10-23T04:00:00Z")!
let start = ProjectUsageLogic.startOfDay(containing: now)
func metadata(_ id: String = "session", _ cwd: String = "/tmp/project") -> String {
    "{\"type\":\"session_meta\",\"payload\":{\"id\":\"\(id)\",\"cwd\":\"\(cwd)\"}}"
}
func event(_ seconds: TimeInterval, _ input: Int = 10, _ output: Int = 2,
           cumulative: Int? = nil) -> String {
    let stamp = ISO8601DateFormatter.withFractionalSeconds.string(from: start.addingTimeInterval(seconds))
    let total = cumulative.map { ",\"total_token_usage\":{\"input_tokens\":\($0),\"output_tokens\":4}" } ?? ""
    return "{\"timestamp\":\"\(stamp)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"last_token_usage\":{\"input_tokens\":\(input),\"output_tokens\":\(output)}\(total)}}}"
}
func parse(_ rows: [String]) -> ProjectUsageSession? {
    ProjectUsageMonitor.parseSession(rows.joined(separator: "\n"), fallbackID: "fallback", now: now)
}
let original = event(60, cumulative: 1000)
check(parse([metadata(), original, original])?.totals.totalTokens == 12, "exact repeated event is counted once")
check(parse([metadata(), event(60), event(60)])?.totals.turnCount == 1, "exact duplicate without cumulative fields is idempotent")
check(parse([metadata(), original, event(61, cumulative: 1010)])?.totals.totalTokens == 24,
      "same-sized turns at different timestamps both count")
check(parse([metadata(), original, event(60, cumulative: 1010)])?.totals.turnCount == 2,
      "same timestamp and usage with different cumulative fields both count")
let reordered = original.replacingOccurrences(of: "\"input_tokens\":10,\"output_tokens\":2", with: "\"output_tokens\":2, \"input_tokens\":10.0")
check(parse([metadata(), original, reordered])?.totals.turnCount == 1, "key ordering and numeric notation normalize")
check(parse([metadata(), event(-1, 500, 50, cumulative: 5000), event(0, 10, 2, cumulative: 5010),
             event(86399, 7, 3, cumulative: 9000), event(86400, 99, 1)])?.totals.totalTokens == 22,
      "Shanghai midnight is inclusive; yesterday and tomorrow do not enter today's sum")
check(parse([metadata(), event(1, 10, 2, cumulative: 5000)])?.totals.totalTokens == 12,
      "first event uses last usage, not the historical cumulative baseline")
check(parse([metadata(), event(-1, 500, 20, cumulative: 9000), event(1, 4, 2, cumulative: 6)])?.totals.totalTokens == 6,
      "cumulative reset across days does not erase today's first event")
check(parse([metadata(), event(1), event(2)])?.totals.totalTokens == 24, "legacy logs without cumulative fields remain supported")
check(parse([metadata(), event(1, -10, 3)])?.totals.totalTokens == 3, "negative tokens are clamped")
let huge = event(1).replacingOccurrences(of: "\"input_tokens\":10", with: "\"input_tokens\":1e100")
let hugeSession = parse([metadata(), huge, event(2, Int.max, Int.max)])!
check(hugeSession.totals.totalTokens == Int.max, "oversized inputs and repeated sums saturate without traps")
let aggregated = ProjectUsageLogic.aggregate([hugeSession, ProjectUsageSession(id: "second", directory: "/tmp/project", totals: hugeSession.totals, lastActivity: now)])
check(aggregated.first?.totals.totalTokens == Int.max, "same-project aggregation saturates")
let other = ProjectUsageReading(directory: "/other", projectName: "other", totals: hugeSession.totals, lastActivity: now)
check(ProjectUsageDaySummary(projects: aggregated + [other], sessionSwitchCount: 0).allProjectTotals.totalTokens == Int.max,
      "cross-project summary aggregation saturates")
let boolean = event(1).replacingOccurrences(of: "\"input_tokens\":10", with: "\"input_tokens\":true")
check(parse([metadata(), boolean])?.totals.totalTokens == 2, "JSON booleans are not token integers")

let root = FileManager.default.temporaryDirectory.appendingPathComponent("project-usage-tests-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: root) }
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let file = root.appendingPathComponent("session.jsonl")
func write(_ text: String, atomic: Bool = false) throws {
    try text.write(to: file, atomically: atomic, encoding: .utf8)
    try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)
}
func append(_ text: String) throws {
    let handle = try FileHandle(forWritingTo: file)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(text.utf8))
    try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)
}
var reads: [(UInt64, Int)] = []
let monitor = ProjectUsageMonitor(roots: [root], fileReadObserver: { _, offset, count in reads.append((offset, count)) })
func scan(_ force: Bool = false, at date: Date = now) -> ProjectUsageDaySummary {
    monitor.readTodayUsingCache(now: date, force: force)
}
// The very first metadata line is delivered over two real file reads.
let meta = metadata()
let split = meta.index(meta.startIndex, offsetBy: meta.count / 2)
try write(String(meta[..<split]))
check(scan().projects.isEmpty, "half metadata alone has no project")
let firstSize = Data(String(meta[..<split]).utf8).count
try append(String(meta[split...]) + "\n" + event(60) + "\n")
check(scan().allProjectTotals.totalTokens == 12, "metadata completed in second read is consumed")
check(reads.last?.0 == UInt64(firstSize), "normal growth reads new payload only after the old byte offset")
let readCount = reads.count
_ = scan()
check(reads.count == readCount, "unchanged snapshots reuse cache")
let oldSize = try Data(contentsOf: file).count
let second = event(61) + "\n"
try append(second)
check(scan().allProjectTotals.totalTokens == 24, "append adds one turn")
check(reads.last?.0 == UInt64(oldSize) && reads.last?.1 == second.utf8.count,
      "append payload is limited to newly appended bytes")
try append(second)
check(scan().allProjectTotals.totalTokens == 24, "repeated appended event remains idempotent")
let beforeForce = reads.count
check(scan(true).allProjectTotals.totalTokens == 24 && reads.count == beforeForce + 1 && reads.last?.0 == 0,
      "force=true rebuilds even an unchanged cache from byte zero")
try write(metadata() + "\n" + event(62, 4, 2) + "\n")
check(scan().allProjectTotals.totalTokens == 6 && reads.last?.0 == 0, "truncation rebuilds the accumulator")
let equalSize = metadata() + "\n" + event(62, 8, 2) + "\n"
let replacementSize = try Data(contentsOf: file).count
check(equalSize.utf8.count == replacementSize, "same-size fixture really has equal length")
let beforeRewrite = ProjectUsageFileSnapshot.read(file)!
try write(equalSize)
let afterRewrite = ProjectUsageFileSnapshot.read(file)!
check(beforeRewrite.hasSameIdentity(as: afterRewrite) && beforeRewrite.modified == afterRewrite.modified,
      "rewrite fixture preserves inode and mtime")
check(scan().allProjectTotals.totalTokens == 10 && reads.last?.0 == 0,
      "same inode/size/mtime rewrite invalidates via change time")
let beforeReplacement = ProjectUsageFileSnapshot.read(file)!
try write(metadata() + "\n" + event(62, 9, 2) + "\n", atomic: true)
let afterReplacement = ProjectUsageFileSnapshot.read(file)!
check(!beforeReplacement.hasSameIdentity(as: afterReplacement) && beforeReplacement.size == afterReplacement.size
      && beforeReplacement.modified == afterReplacement.modified, "replacement fixture changes identity, preserves size and mtime")
check(scan().allProjectTotals.totalTokens == 11 && reads.last?.0 == 0,
      "same-size atomic replacement with restored mtime invalidates by identity")
// A rewrite followed by growth must not be mistaken for a plain append.
try write(metadata() + "\n" + event(62, 3, 2) + "\n" + event(63) + "\n")
check(scan().allProjectTotals.totalTokens == 17 && reads.last?.0 == 0, "changed old prefix on growth rebuilds")
try append(String(event(64).prefix(30)))
check(scan().allProjectTotals.totalTokens == 17, "partial token line remains pending")
try append(String(event(64).dropFirst(30)) + "\n")
check(scan().allProjectTotals.totalTokens == 29, "completed partial token line counts exactly once")
try write("{\"type\":\"other\"}\n" + metadata() + "\n" + event(65) + "\n")
check(scan().allProjectTotals.totalTokens == 12, "metadata after a preamble is recognized")
try append(event(86401, 6, 2) + "\n")
check(scan().allProjectTotals.totalTokens == 12, "future-day event excluded from current day")
try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(86400)], ofItemAtPath: file.path)
check(scan(at: now.addingTimeInterval(86400)).allProjectTotals.totalTokens == 8,
      "day rollover clears dedup and cache and attributes next day's first event")
try FileManager.default.removeItem(at: file)
check(scan().projects.isEmpty, "removed files leave no cached contribution")

if failures.isEmpty {
    print("Project usage regression tests passed: exact-event deduplication, numeric bounds, Shanghai day attribution, partial JSONL, append-only payload reads, truncation/rewrite/replacement, force and rollover")
} else {
    failures.forEach { print("FAIL: \($0)") }
    exit(1)
}
