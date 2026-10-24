import AppKit
import CoreFoundation
import CryptoKit
import Darwin
import Foundation

/// 千问办公（QwenWorkCN）把 Credit 用量放在自己的本地 MCP 服务后面：客户端
/// 启动后监听 `/tmp/qwenworkcn-mcp.sock`，并把登录态、账户和额度查询能力注册
/// 成 `qw_query` 工具。本应用只连接这个本机 socket，查询 `qwenwork.usage`
/// （附带 `qwenwork.settings.profile` 用于确认套餐和账户身份）；不读取、不
/// 解密、也不保存千问办公的登录 token，网络请求由客户端自身发出。
///
/// 客户端未运行时 socket 不存在，对应账户按「未运行」处理；Mini 条由
/// `AccountVisibility` 自动隐藏这类账户，打开客户端后再自动出现。
enum QwenWorkUsageParser {
    static func reading(from payload: Data, profile: Data? = nil, now: Date = .now) -> BalanceReading {
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            return BalanceProvider.qwenwork.failed("千问办公返回数据无法解析")
        }
        let profileObject = profile.flatMap {
            (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any]
        }
        return reading(from: object, profile: profileObject, now: now)
    }

    static func reading(
        from payload: [String: Any],
        profile: [String: Any]? = nil,
        now: Date = .now
    ) -> BalanceReading {
        if let ok = booleanValue(payload["ok"]), !ok {
            return BalanceProvider.qwenwork.failed("千问办公返回错误：\(errorMessage(in: payload))")
        }
        let quotaData = (payload["data"] as? [String: Any]) ?? payload
        if let ok = booleanValue(quotaData["ok"]), !ok {
            return BalanceProvider.qwenwork.failed("千问办公返回错误：\(errorMessage(in: quotaData))")
        }
        if let available = booleanValue(quotaData["available"]), !available {
            let message = stringValue(quotaData["message"]) ?? "暂无可用的 Credits 数据"
            let lowercased = message.lowercased()
            if message.contains("登录") || lowercased.contains("log in")
                || lowercased.contains("login") || lowercased.contains("logged")
                || lowercased.contains("token") || lowercased.contains("unauthorized")
                || lowercased.contains("session") {
                return BalanceProvider.qwenwork.unconfigured("请先在千问办公客户端重新登录后重试")
            }
            return BalanceProvider.qwenwork.failed("千问办公暂无法读取：\(message)")
        }

        let plan = quota(quotaData["planCredits"] ?? quotaData["plan_credits"])
        let addOn = quota(quotaData["addOnCredits"] ?? quotaData["add_on_credits"])
        let shared = sharedPackage(quotaData["sharedResourcePackage"] ?? quotaData["shared_resource_package"])
        guard plan != nil || addOn != nil || shared != nil else {
            return BalanceProvider.qwenwork.failed("接口未返回 Credits 额度（可能版本已变化）")
        }

        var capacity: Double = 0
        var remaining: Double = 0
        var used: Double = 0
        if let plan {
            capacity += max(plan.total, 0)
            remaining += max(plan.remaining, 0)
            used += max(plan.used, 0)
        }
        if let addOn {
            capacity += max(addOn.total, 0)
            remaining += max(addOn.remaining, 0)
            used += max(addOn.used, 0)
        }
        if let shared, shared.available {
            // The shared pool reports cap = -1 when it is unbounded; mirror the
            // client's own aggregate rule (used + remaining as the denominator).
            capacity += shared.cap >= 0 ? max(shared.cap, 0) : shared.used + max(shared.remaining, 0)
            remaining += max(shared.remaining, 0)
            used += max(shared.used, 0)
        }

        let exceeded = booleanValue(quotaData["isQuotaExceeded"] ?? quotaData["is_quota_exceeded"]) ?? (remaining <= 0)
        var percent: Int?
        if let aggregate = numberValue(quotaData["aggregateRemainingPercent"] ?? quotaData["aggregate_remaining_percent"]) {
            percent = BalanceFormatting.percent(aggregate)
        } else if capacity > 0, remaining.isFinite, remaining <= 1e15 {
            percent = BalanceFormatting.percent(remaining / capacity * 100)
        }
        if exceeded { percent = 0 }

        let amountText = BalanceFormatting.credits(String(remaining), fractionLength: 1) ?? "0"
        let profileData = (profile?["data"] as? [String: Any]) ?? profile
        let tier = stringValue(profileData?["tier"])
        let team = booleanValue(quotaData["isTeamPlan"] ?? quotaData["is_team_plan"]) ?? false
        var details: [String] = []
        if let tier, !tier.isEmpty { details.append(tier) }
        if let plan, plan.total > 0 {
            details.append("套餐 剩 \(creditsText(plan.remaining)) / \(creditsText(plan.total))（已用 \(creditsText(plan.used))）")
        }
        if let addOn, addOn.total > 0 {
            details.append("附加 已用 \(creditsText(addOn.used)) / \(creditsText(addOn.total))")
        }
        if let shared, shared.available {
            details.append(shared.cap >= 0
                ? "共享 已用 \(creditsText(shared.used)) / \(creditsText(shared.cap))"
                : "共享 剩 \(creditsText(shared.remaining))")
        }
        if let expiration = expiresAt(quotaData) {
            details.append("至 " + expirationText(expiration))
        }
        if exceeded {
            details.append("本周期额度已用尽")
        }
        if team {
            details.append("团队套餐")
        }

        let caption: String
        if exceeded {
            caption = "额度已用尽"
        } else if percent != nil {
            caption = "套餐 Credits 剩余"
        } else {
            caption = "剩余 Credits"
        }

        return BalanceReading(
            id: BalanceProvider.qwenwork.id,
            title: BalanceProvider.qwenwork.title,
            systemImage: BalanceProvider.qwenwork.systemImage,
            valueText: amountText,
            unitPrefix: nil,
            unitSuffix: " Credits",
            caption: caption,
            detail: details.isEmpty ? nil : details.joined(separator: " · "),
            percent: percent,
            windows: [],
            state: .ok,
            sourceURL: BalanceProvider.qwenwork.sourceURL,
            updatedAt: now,
            numericValue: remaining,
            numericUsedValue: used,
            currency: "credits",
            sourceIdentity: identity(from: profileData),
            lastAttemptAt: now
        )
    }

    private struct Quota {
        var total: Double
        var used: Double
        var remaining: Double
    }

    private struct SharedPackage {
        var cap: Double
        var used: Double
        var remaining: Double
        var available: Bool
    }

    private static func quota(_ value: Any?) -> Quota? {
        guard let object = value as? [String: Any] else { return nil }
        let total = numberValue(object["total"])
        let used = numberValue(object["used"])
        let remaining = numberValue(object["remaining"])
        // An object whose numeric fields are all absent or out of range cannot
        // establish a balance; treating it as zero would fake "quota exhausted".
        guard total != nil || used != nil || remaining != nil else { return nil }
        let resolvedTotal = total ?? 0
        let resolvedUsed = used ?? 0
        return Quota(total: resolvedTotal, used: resolvedUsed,
                     remaining: remaining ?? max(resolvedTotal - resolvedUsed, 0))
    }

    private static func sharedPackage(_ value: Any?) -> SharedPackage? {
        guard let object = value as? [String: Any] else { return nil }
        let cap = numberValue(object["cap"] ?? object["total"])
        let used = numberValue(object["used"])
        let remaining = numberValue(object["remaining"])
        guard cap != nil || used != nil || remaining != nil else { return nil }
        let resolvedCap = cap ?? 0
        let resolvedUsed = used ?? 0
        let resolvedRemaining = remaining ?? max(resolvedCap - resolvedUsed, 0)
        let available = booleanValue(object["available"]) ?? (resolvedCap > 0 || resolvedRemaining > 0)
        return SharedPackage(cap: resolvedCap, used: resolvedUsed,
                             remaining: resolvedRemaining, available: available)
    }

    private static func errorMessage(in payload: [String: Any]) -> String {
        if let error = payload["error"] as? [String: Any] {
            return stringValue(error["message"]) ?? stringValue(error["code"]) ?? "查询失败"
        }
        return stringValue(payload["error"]) ?? stringValue(payload["message"]) ?? "查询失败"
    }

    private static func expiresAt(_ payload: [String: Any]) -> Date? {
        if let expiration = payload["planExpiration"] as? [String: Any],
           let date = dateValue(expiration["expiresAt"] ?? expiration["expires_at"]) {
            return date
        }
        return dateValue(payload["expiresAt"] ?? payload["expires_at"])
    }

    private static func creditsText(_ value: Double) -> String {
        BalanceFormatting.credits(String(value), fractionLength: 1) ?? "0"
    }

    private static func expirationText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    /// A domain-separated HMAC keeps the e-mail out of the ledger while still
    /// distinguishing two signed-in accounts on the same Mac.
    private static let identityKey = SymmetricKey(data: Data("compute-ring/question-work-identity-v1".utf8))

    private static func identity(from profile: [String: Any]?) -> String? {
        guard let email = stringValue(profile?["email"]), !email.isEmpty else { return nil }
        let digest = HMAC<SHA256>.authenticationCode(for: Data(email.utf8), using: identityKey)
        return "qwenwork:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String, !string.isEmpty { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func numberValue(_ value: Any?) -> Double? {
        let parsed: Double?
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            parsed = number.doubleValue
        } else if let string = value as? String {
            parsed = Double(string)
        } else {
            parsed = nil
        }
        guard let parsed, parsed.isFinite, abs(parsed) <= 1e15 else { return nil }
        return parsed
    }

    private static func booleanValue(_ value: Any?) -> Bool? {
        if let boolean = value as? Bool { return boolean }
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue
        }
        return nil
    }

    private static func dateValue(_ value: Any?) -> Date? {
        guard let number = numberValue(value), number > 1_000_000_000 else { return nil }
        return Date(timeIntervalSince1970: number > 1_000_000_000_000 ? number / 1_000 : number)
    }
}

struct QwenWorkChannelError: Error {
    let message: String
}

final class QwenWorkBalanceClient {
    private let queue = DispatchQueue(label: "codex.pet.energy.balance.qwenwork")

    func fetch(completion: @escaping (BalanceReading) -> Void) {
        queue.async {
            var captured = self.capture()
            captured.lastAttemptAt = .now
            let reading = captured
            DispatchQueue.main.async { completion(reading) }
        }
    }

    private func capture() -> BalanceReading {
        // The launch notification fires while 千问办公 is still starting; its
        // MCP socket appears about 3–9 s later (the app logs ~4 s to ready plus
        // adaptor startup). Poll within a bounded 12 s window so opening the
        // client updates the bar immediately instead of waiting five minutes.
        // Each attempt is capped at 4 s, keeping the worst case well below the
        // 30 s BalanceMonitor provider timeout.
        let clientIsRunning = Self.clientIsRunning()
        let deadline = Date().addingTimeInterval(clientIsRunning ? 12 : 0)
        var failure: BalanceReading?
        repeat {
            let started = Date()
            if let path = Self.socketPath() {
                do {
                    let connection = try QwenWorkMCPConnection(path: path, timeout: 4)
                    let usage = try connection.query(key: "qwenwork.usage")
                    // The profile tier/identity is optional: a newer or restricted
                    // app build can still answer the usage query.
                    let profile = try? connection.query(key: "qwenwork.settings.profile")
                    return QwenWorkUsageParser.reading(from: usage, profile: profile)
                } catch let error as QwenWorkChannelError {
                    failure = BalanceProvider.qwenwork.failed(error.message)
                    // Do not retry application-level errors or a connected but
                    // unresponsive server; only a not-yet-created socket or a
                    // refused connection indicates the client is still starting.
                    if !Self.isTransient(error.message) { return failure! }
                } catch {
                    failure = BalanceProvider.qwenwork.failed("读取千问办公额度失败：\(error.localizedDescription)")
                }
            } else {
                failure = BalanceProvider.qwenwork.failed("千问办公未运行（找不到本地 MCP 通道）")
            }
            guard clientIsRunning, Date() < deadline else { break }
            let elapsed = Date().timeIntervalSince(started)
            Thread.sleep(forTimeInterval: max(0.4, 1.0 - elapsed))
        } while true
        return failure ?? BalanceProvider.qwenwork.failed("千问办公未运行（找不到本地 MCP 通道）")
    }

    private static func isTransient(_ message: String) -> Bool {
        ["未运行", "无法连接", "找不到本地 MCP", "握手", "超时", "已断开", "不可用"].contains { message.contains($0) }
    }

    private static func clientIsRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == AccountVisibility.clientBundleIdentifiers["qwenwork"] }
    }

    /// The CN desktop build publishes its MCP server at a fixed user-level
    /// socket under /tmp. Only the socket of a running client exists, so finding
    /// it is also the "app is open" check.
    static func socketPath() -> String? {
        let path = "/tmp/qwenworkcn-mcp.sock"
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }
}

/// One short-lived MCP session: initialize, tools/call `qw_query`, close.
private final class QwenWorkMCPConnection {
    private let channel: QwenWorkChannel
    private var nextRequestID = 1

    init(path: String, timeout: TimeInterval) throws {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw QwenWorkChannelError(message: "无法创建千问办公本地连接")
        }
        let transport = try QwenWorkChannel(fileDescriptor: descriptor, timeout: timeout)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let pathBytes = Array(path.utf8)
        guard !pathBytes.contains(0), !pathBytes.isEmpty,
              pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw QwenWorkChannelError(message: "千问办公本地通道路径无效")
        }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 104) { destination in
                for (index, byte) in pathBytes.enumerated() {
                    destination[index] = CChar(bitPattern: byte)
                }
            }
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result != 0 {
            guard errno == EINPROGRESS else {
                throw QwenWorkChannelError(message: "千问办公未运行（无法连接本地 MCP 通道）")
            }
            try transport.waitFor(POLLOUT)
            var error: Int32 = 0
            var size = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &error, &size) == 0, error == 0 else {
                throw QwenWorkChannelError(message: "千问办公未运行（无法连接本地 MCP 通道）")
            }
        }
        channel = transport
        try handshake()
    }

    /// Runs one local `qw_query` and returns the MCP structuredContent.
    func query(key: String) throws -> [String: Any] {
        let requestIdentifier = nextRequestID
        nextRequestID += 1
        try channel.send([
            "jsonrpc": "2.0",
            "id": requestIdentifier,
            "method": "tools/call",
            "params": [
                "name": "qw_query",
                "arguments": ["key": key],
            ],
        ])
        guard let frame = try channel.response(matching: requestIdentifier) else {
            throw QwenWorkChannelError(message: "千问办公未返回额度数据")
        }
        if let error = frame["error"] as? [String: Any] {
            let message = (error["message"] as? String) ?? (error["code"] as? String) ?? "未知错误"
            throw QwenWorkChannelError(message: "千问办公返回错误：\(message)")
        }
        guard let result = frame["result"] as? [String: Any] else {
            throw QwenWorkChannelError(message: "千问办公返回格式异常")
        }
        if booleanValue(result["isError"]) == true {
            let message = contentText(result) ?? "查询失败"
            throw QwenWorkChannelError(message: "千问办公返回错误：\(message)")
        }
        if let structured = result["structuredContent"] as? [String: Any] {
            if let ok = booleanValue(structured["ok"]), !ok {
                let message: String
                if let error = structured["error"] as? [String: Any] {
                    message = (error["message"] as? String) ?? (error["code"] as? String) ?? "查询失败"
                } else {
                    message = (structured["message"] as? String) ?? "查询失败"
                }
                throw QwenWorkChannelError(message: "千问办公返回错误：\(message)")
            }
            return structured
        }
        if let text = contentText(result),
           let data = text.data(using: .utf8),
           let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            return object
        }
        throw QwenWorkChannelError(message: "千问办公返回内容为空")
    }

    private func handshake() throws {
        try channel.send([
            "jsonrpc": "2.0",
            "id": nextRequestID,
            "method": "initialize",
            "params": [
                "protocolVersion": "2024-11-05",
                "capabilities": [:] as [String: Any],
                "clientInfo": ["name": "compute-ring", "version": "1.4.0"],
            ],
        ])
        guard let response = try channel.response(matching: nextRequestID),
              response["result"] != nil else {
            throw QwenWorkChannelError(message: "千问办公本地通道握手失败")
        }
        nextRequestID += 1
        try channel.send(["jsonrpc": "2.0", "method": "notifications/initialized", "params": [:] as [String: Any]])
    }

    private func contentText(_ result: [String: Any]) -> String? {
        guard let content = result["content"] as? [[String: Any]] else { return nil }
        for item in content where (item["type"] as? String) == "text" {
            if let text = item["text"] as? String, !text.isEmpty { return text }
        }
        return nil
    }

    private func booleanValue(_ value: Any?) -> Bool? {
        if let boolean = value as? Bool { return boolean }
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue
        }
        return nil
    }
}

/// Bounded newline transport for the MCP socket. One monotonic deadline covers
/// connect, every write and every frame, so a frozen client cannot hang a
/// refresh.
private final class QwenWorkChannel {
    private let descriptor: Int32
    private let deadline: UInt64
    private var closed = false
    private var buffer = Data()
    private var frameCount = 0
    private var receivedBytes = 0
    private static let maximumFrameBytes = 1_048_576
    private static let maximumReceivedBytes = 4_194_304
    private static let maximumFrames = 256

    init(fileDescriptor: Int32, timeout: TimeInterval) throws {
        descriptor = fileDescriptor
        let safeTimeout = timeout.isFinite ? min(max(timeout, 0.001), 60) : 12
        deadline = DispatchTime.now().uptimeNanoseconds + UInt64(safeTimeout * 1_000_000_000)
        var noSignal: Int32 = 1
        guard setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size)) == 0,
              fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK) == 0 else {
            closed = true
            Darwin.close(descriptor)
            throw QwenWorkChannelError(message: "无法配置千问办公本地连接")
        }
    }

    deinit { close() }

    private func close() {
        guard !closed else { return }
        closed = true
        Darwin.close(descriptor)
    }

    func waitFor(_ events: Int32) throws {
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { throw QwenWorkChannelError(message: "千问办公本地通道超时") }
            var descriptorState = pollfd(fd: descriptor, events: Int16(events), revents: 0)
            let milliseconds = Int32(max(1, (deadline - now + 999_999) / 1_000_000))
            let result = poll(&descriptorState, 1, milliseconds)
            if result < 0 && errno == EINTR { continue }
            guard result > 0 else {
                throw QwenWorkChannelError(message: result == 0 ? "千问办公本地通道超时" : "千问办公本地通道不可用")
            }
            guard Int32(descriptorState.revents) & (POLLERR | POLLNVAL) == 0 else {
                throw QwenWorkChannelError(message: "千问办公本地通道已断开")
            }
            if Int32(descriptorState.revents) & events != 0 { return }
            throw QwenWorkChannelError(message: "千问办公本地通道已断开")
        }
    }

    func send(_ frame: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: frame)
        guard data.count <= Self.maximumFrameBytes else {
            throw QwenWorkChannelError(message: "千问办公请求帧过大")
        }
        data.append(0x0A)
        var offset = 0
        try data.withUnsafeBytes { bytes in
            while offset < bytes.count {
                try waitFor(POLLOUT)
                let written = Darwin.write(descriptor, bytes.baseAddress?.advanced(by: offset), bytes.count - offset)
                if written < 0 && [EINTR, EAGAIN, EWOULDBLOCK].contains(errno) { continue }
                guard written > 0 && written <= bytes.count - offset else {
                    throw QwenWorkChannelError(message: "千问办公本地通道写入失败")
                }
                offset += written
            }
        }
    }

    func response(matching identifier: Int) throws -> [String: Any]? {
        while let frame = try readFrame() {
            if let id = frame["id"] as? Int, id == identifier { return frame }
        }
        return nil
    }

    func readFrame() throws -> [String: Any]? {
        while true {
            guard DispatchTime.now().uptimeNanoseconds < deadline else {
                throw QwenWorkChannelError(message: "千问办公本地通道超时")
            }
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                frameCount += 1
                guard line.count <= Self.maximumFrameBytes, frameCount <= Self.maximumFrames else {
                    throw QwenWorkChannelError(message: "千问办公返回帧超限")
                }
                guard let frame = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else {
                    throw QwenWorkChannelError(message: "千问办公返回格式异常")
                }
                return frame
            }
            guard buffer.count <= Self.maximumFrameBytes else {
                throw QwenWorkChannelError(message: "千问办公返回帧过大")
            }
            try waitFor(POLLIN)
            var chunk = [UInt8](repeating: 0, count: 16_384)
            let count = Darwin.read(descriptor, &chunk, chunk.count)
            if count < 0 && [EINTR, EAGAIN, EWOULDBLOCK].contains(errno) { continue }
            guard count > 0 else {
                throw QwenWorkChannelError(message: "千问办公本地通道已断开")
            }
            receivedBytes += count
            guard receivedBytes <= Self.maximumReceivedBytes else {
                throw QwenWorkChannelError(message: "千问办公返回数据过大")
            }
            buffer.append(contentsOf: chunk[0..<count])
        }
    }
}
