import Foundation

func wait(until condition: () -> Bool, timeout: TimeInterval = 4) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
    return condition()
}

let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }
var failures: [String] = []

func check(_ condition: Bool, _ message: String) { if !condition { failures.append(message) } }

func executable(_ name: String, body: String) throws -> URL {
    let url = temporary.appendingPathComponent(name)
    try ("#!/bin/sh\n" + body).write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    return url
}

let silent = try executable("silent", body: "while IFS= read -r line; do :; done\n")
let handshakeClient = CodexRateLimitClient(executable: silent, timeoutInterval: 1)
var handshakeFailed = false
handshakeClient.onUnavailable = { handshakeFailed = true }
handshakeClient.start()
check(wait(until: { handshakeFailed }), "silent initialization must report failure")
handshakeClient.stop()

let retryServer = try executable("retry", body: #"""
count=0
while IFS= read -r line; do
    printf '%s\n' "$line" >> "$0.requests"
    case "$line" in
      *'"method":"initialize"'*) printf '%s\n' '{"id":1,"result":{}}' ;;
      *'rateLimits'*)
        count=$((count + 1))
        if [ "$count" -eq 1 ]; then
          printf '%s\n' '{"id":999,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":99}}}}'
        else
          printf '%s\n' '{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":99}}}}'
          printf '%s\n' '{"id":3,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":25,"windowDurationMins":10080,"resetsAt":123}}}}'
        fi ;;
    esac
done
"""#)
let retryClient = CodexRateLimitClient(executable: retryServer, timeoutInterval: 1)
var readFailed = false
var snapshots: [RateLimitReadResult] = []
retryClient.onUnavailable = { readFailed = true }
retryClient.onSnapshot = { snapshots.append($0) }
retryClient.start()
check(wait(until: { readFailed }), "a wrong request ID must not prevent timeout")
check(snapshots.isEmpty, "a wrong request ID must not publish a snapshot")
retryClient.refresh()
check(wait(until: { !snapshots.isEmpty }), "manual retry must recover after timeout")
check(snapshots.count == 1 && snapshots.first?.rateLimits.primary?.usedPercent == 25,
      "late response for a previous request must be ignored")
retryClient.stop()

if failures.isEmpty {
    print("RPC regression tests passed: initialization timeout, read timeout, stale response rejection, manual retry recovery")
} else {
    failures.forEach { print("RPC regression failed: \($0)") }
    print((try? String(contentsOf: retryServer.appendingPathExtension("requests"), encoding: .utf8)) ?? "no requests")
    exit(1)
}
