import Foundation
import Darwin

var failures: [String] = []
var checks = 0
func expect(_ value: Bool, _ message: String) { checks += 1; if !value { failures.append(message) } }
func expectThrow(_ message: String, _ body: () throws -> Void) {
    checks += 1
    do { try body(); failures.append(message) } catch {}
}
func payload(_ text: String) -> Data { Data(text.utf8) }
func deepseek(_ raw: String, currency: String = "USD") -> BalanceReading {
    DeepSeekBalanceParser.reading(from: payload("{\"balance_infos\":[{\"currency\":\"\(currency)\",\"total_balance\":\"\(raw)\"}]}"))
}
expect(deepseek("1234.567").numericValue == 1234.567, "raw money retains precision without parsing display separators")
expect(deepseek("1").currency == "USD" && deepseek("1").detail?.contains("¥") == false, "non-CNY currency is consistent in every detail")
expect(deepseek("1").detail?.contains("待提供") == true, "missing money breakdown is unknown")
for value in ["nan", "inf", "-inf", "1e300", "hello"] { expect(deepseek(value).numericValue == nil, "invalid money rejected: \(value)") }
expect(deepseek("1", currency: "").state != .ok, "missing currency cannot default to CNY")
let missingUsage = WorkBuddyBalanceParser.reading(from: payload(#"{"data":{"TotalCredits":"5","Packages":[{"CycleTotalCapacity":"100"}]}}"#))
expect(missingUsage.numericValue == 5 && missingUsage.numericUsedValue == nil && missingUsage.percent == nil, "missing used credits do not become zero")
for value in ["nan", "inf", "1e300", "-1"] {
    let reading = WorkBuddyBalanceParser.reading(from: payload("{\"data\":{\"TotalCredits\":\"\(value)\"}}"))
    expect(reading.state != .ok, "invalid credits rejected: \(value)")
}
let partial = WorkBuddyBalanceParser.reading(from: payload(#"{"data":{"TotalCredits":5,"Packages":[{"CycleTotalCapacity":100,"CycleUsedCapacity":10},{"CycleTotalCapacity":100}]}}"#))
expect(partial.numericUsedValue == nil && partial.percent == nil, "partial package arrays cannot undercount spend")
for value in ["nan", "inf", "1e300", "-1", "101"] {
    let text = "{\"data\":{\"window_limit_section\":{\"window_limit_groups\":[{\"window_limits\":[{\"window_type\":1,\"used_percent\":\"\(value)\"}]}]}}}"
    expect(DoubaoQuotaParser.reading(from: payload(text)).state != .ok, "invalid quota rejected: \(value)")
}
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("compute-ring-reliability-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
func addProfile(_ name: String) throws {
    let path = directory.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
    try Data().write(to: path.appendingPathComponent("Cookies"))
}
try addProfile("Default")
expect(try DoubaoCookieReader.activeProfile(in: directory).lastPathComponent == "Default", "one unambiguous local profile can be selected")
try addProfile("Profile 2")
expectThrow("multiple profiles without explicit active selection must fail") { _ = try DoubaoCookieReader.activeProfile(in: directory) }
try payload(#"{"profile":{"last_used":"Profile 2"}}"#).write(to: directory.appendingPathComponent("Local State"))
expect(try DoubaoCookieReader.activeProfile(in: directory).lastPathComponent == "Profile 2", "explicit active profile wins")
try payload(#"{"profile":{"last_used":"Profile 9"}}"#).write(to: directory.appendingPathComponent("Local State"))
expectThrow("missing active profile must not fall back to another account") { _ = try DoubaoCookieReader.activeProfile(in: directory) }

func socketPair() throws -> (Int32, Int32) {
    var pair: [Int32] = [0, 0]
    guard socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0 else { throw WbipcError(displayMessage: "test socketpair failed") }
    return (pair[0], pair[1])
}
do {
    let pair = try socketPair()
    let channel = try WbipcChannel(fileDescriptor: pair.0, timeout: 0.1)
    close(pair.1)
    expectThrow("peer disconnect throws without SIGPIPE terminating the test process") { try channel.send(["id": 1]) }
}
do {
    let pair = try socketPair()
    defer { close(pair.1) }
    var writes = 0
    let channel = try WbipcChannel(fileDescriptor: pair.0, timeout: 0.2, writer: { descriptor, bytes, count in
        writes += 1
        return Darwin.write(descriptor, bytes, min(3, count))
    })
    try channel.send(["id": 41, "method": "synthetic"])
    var bytes = [UInt8](repeating: 0, count: 1024)
    let count = Darwin.read(pair.1, &bytes, bytes.count)
    let frame = try JSONSerialization.jsonObject(with: Data(bytes.prefix(count - 1))) as? [String: Any]
    expect(writes > 1 && bytes[count - 1] == 10 && frame?["id"] as? Int == 41, "all partial writes complete the frame")
}
do {
    let pair = try socketPair()
    defer { close(pair.1) }
    let channel = try WbipcChannel(fileDescriptor: pair.0, timeout: 0.1)
    let frames = payload("{\"id\":2}\n{\"method\":\"notice\"}\n{\"id\":7,\"result\":{}}\n")
    _ = frames.withUnsafeBytes { Darwin.write(pair.1, $0.baseAddress, $0.count) }
    expect(try channel.response(matching: 7)?["id"] as? Int == 7, "unrelated messages are skipped within the request deadline")
}
do {
    let pair = try socketPair()
    defer { close(pair.1) }
    let channel = try WbipcChannel(fileDescriptor: pair.0, timeout: 0.04)
    let start = Date()
    expectThrow("silent peer times out") { _ = try channel.readFrame() }
    expect(Date().timeIntervalSince(start) < 0.3, "silent peer deadline is bounded")
}
do {
    let pair = try socketPair()
    defer { close(pair.1) }
    let channel = try WbipcChannel(fileDescriptor: pair.0, timeout: 0.08)
    let frames = payload(String(repeating: "{\"id\":9}\n", count: 260))
    _ = frames.withUnsafeBytes { Darwin.write(pair.1, $0.baseAddress, $0.count) }
    expectThrow("unrelated frame flood cannot reset the timeout or grow forever") { _ = try channel.response(matching: 1) }
}

final class SyntheticFetches {
    let lock = NSLock()
    var counts: [BalanceProvider: Int] = [:]
    var callbacks: [BalanceProvider: [(BalanceReading) -> Void]] = [:]
    func fetch(_ provider: BalanceProvider, callback: @escaping (BalanceReading) -> Void) {
        lock.lock(); defer { lock.unlock() }
        counts[provider, default: 0] += 1
        callbacks[provider, default: []].append(callback)
    }
    func count(_ provider: BalanceProvider) -> Int { lock.lock(); defer { lock.unlock() }; return counts[provider, default: 0] }
    func callback(_ provider: BalanceProvider, _ index: Int) -> ((BalanceReading) -> Void)? { lock.lock(); defer { lock.unlock() }; return callbacks[provider]?[safe: index] }
}
extension Array { subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil } }
func pump(_ duration: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(duration)) }
/// A fixed sleep turns queue scheduling into a race on loaded machines: wait
/// for the expected state instead, then assert it. `pump` only drives the main
/// run loop, so the deadline bounds how long an unreachable state is polled.
func waitUntil(_ timeout: TimeInterval = 2, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        pump(0.005)
    }
    return condition()
}
let synthetic = SyntheticFetches()
let monitor = BalanceMonitor(providerTimeout: 0.2, fetcher: synthetic.fetch)
var received: [BalanceReading] = []
var refreshing: [Set<String>] = []
var finished = 0
var callbacksOnMain = true
monitor.onReading = { callbacksOnMain = callbacksOnMain && Thread.isMainThread; received.append($0) }
monitor.onRefreshing = { callbacksOnMain = callbacksOnMain && Thread.isMainThread; refreshing.append($0) }
monitor.onFinished = { finished += 1 }
monitor.refresh()
pump(0.03)
monitor.refresh()
pump(0.02)
expect(BalanceProvider.allCases.allSatisfy { synthetic.count($0) == 1 }, "single-flight applies independently to every provider")
synthetic.callback(.deepseek, 0)?(deepseek("1"))
expect(waitUntil { received.count == 1 }, "fast provider publishes while other providers are pending")
expect(received.count == 1, "fast provider publishes while other providers are pending")
monitor.refresh(providers: [.deepseek])
pump(0.02)
expect(synthetic.count(.deepseek) == 2 && synthetic.count(.doubao) == 1, "finished provider can refresh while another provider is stuck")
// Count only this provider: an unrelated provider timing out on a slow runner
// must not decide whether the stale callback was rejected.
let publishedBeforeStaleCallback = received.filter { $0.id == "deepseek" }.count
synthetic.callback(.deepseek, 0)?(deepseek("999"))
pump(0.05)
expect(received.filter { $0.id == "deepseek" }.count == publishedBeforeStaleCallback,
       "duplicate old callback cannot overwrite a new attempt")
synthetic.callback(.deepseek, 1)?(deepseek("2"))
expect(waitUntil { received.count == 4 }, "stuck providers timeout independently")
expect(received.count == 4 && received.filter { $0.id != "deepseek" }.allSatisfy { if case .failed = $0.state { return true }; return false }, "stuck providers timeout independently")
expect(waitUntil { refreshing.last == [] && finished == 1 }, "all callback state reaches the main queue and final refreshing state clears")
expect(refreshing.last == [] && finished == 1 && callbacksOnMain, "all callback state reaches the main queue and final refreshing state clears")
synthetic.callback(.doubao, 0)?(BalanceProvider.doubao.placeholder())
pump(0.05)
expect(received.count == 4, "late result after timeout is ignored")
monitor.stop()
pump(0.01)
ResetRadarSelfTest.check(into: &failures)
if failures.isEmpty { print("Reliability tests passed (\(checks) checks + radar regression suite; synthetic inputs only)") }
else { print(failures.joined(separator: "\n")); exit(1) }
