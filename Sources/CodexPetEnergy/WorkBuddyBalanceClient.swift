import CryptoKit
import Foundation
import Darwin
import CoreFoundation

/// WorkBuddy keeps the subscription credit panel behind its own local IPC
/// channel (WBIPC). The client injects the current login token itself, so this
/// app never reads, stores or decrypts WorkBuddy credentials — it only asks the
/// running client for the same usage summary the in-app panel shows.
///
/// Protocol: newline-delimited JSON over a Unix socket under
/// `~/.workbuddy/wbipc/endpoint.json`, with a mutual HMAC-SHA256 handshake
/// (client and host each prove possession of the ticket in that file).
enum WorkBuddyBalanceParser {
    static func reading(from body: Data, now: Date = .now) -> BalanceReading {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return BalanceProvider.workbuddy.failed("返回数据无法解析")
        }
        if let code = object["code"] as? Int, code != 0 {
            let message = (object["msg"] as? String) ?? (object["message"] as? String) ?? "业务错误 \(code)"
            return BalanceProvider.workbuddy.failed(message)
        }
        guard let data = object["data"] as? [String: Any] else {
            return BalanceProvider.workbuddy.failed("返回数据缺少额度信息")
        }
        guard let totalRaw = stringValue(data["TotalCredits"]),
              let numeric = doubleValue(data["TotalCredits"]),
              let credits = BalanceFormatting.credits(totalRaw) else {
            return BalanceProvider.workbuddy.failed("额度数值缺失")
        }
        let plan = stringValue(data["SubscriptionPackageName"]) ?? "未识别套餐"
        let packages = data["Packages"] as? [[String: Any]] ?? []
        // A partial package list cannot establish total spend or capacity.
        let capacities = packages.compactMap { doubleValue($0["CycleTotalCapacity"]) }
        let usages = packages.compactMap { doubleValue($0["CycleUsedCapacity"]) }
        let complete = !packages.isEmpty && capacities.count == packages.count && usages.count == packages.count
        let capacity = complete ? capacities.reduce(0, +) : 0
        let aggregateUsed = complete ? usages.reduce(0, +) : nil
        let used = aggregateUsed.flatMap { $0.isFinite && $0 <= 1e15 ? $0 : nil }
        var detail = plan
        var usedCredits: String? = nil
        if let used, capacity > 0, capacity <= 1e15, used <= 1e15 {
            let spentText = BalanceFormatting.credits(String(used))!
            let capacityText = BalanceFormatting.credits(String(capacity))!
            usedCredits = spentText
            detail += " · 已用 \(spentText) / \(capacityText)"
        }
        let percent = used.flatMap { capacity > 0 && capacity <= 1e15 ? BalanceFormatting.percent((capacity - $0) / capacity * 100) : nil }
        return BalanceReading(
            id: BalanceProvider.workbuddy.id,
            title: BalanceProvider.workbuddy.title,
            systemImage: BalanceProvider.workbuddy.systemImage,
            valueText: credits,
            unitPrefix: nil,
            unitSuffix: " 积分",
            caption: "剩余积分",
            detail: detail,
            percent: percent,
            usedText: usedCredits,
            windows: [],
            state: .ok,
            sourceURL: BalanceProvider.workbuddy.sourceURL,
            updatedAt: now, numericValue: numeric, numericUsedValue: used, lastAttemptAt: now
        )
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String, !string.isEmpty { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        let parsed: Double?
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { parsed = number.doubleValue }
        else if let string = value as? String { parsed = Double(string) }
        else { parsed = nil }
        guard let parsed, parsed.isFinite, parsed >= 0, parsed <= 1e15 else { return nil }
        return parsed
    }
}

final class WorkBuddyBalanceClient {
    private let queue = DispatchQueue(label: "codex.pet.energy.balance.workbuddy")

    func fetch(completion: @escaping (BalanceReading) -> Void) {
        queue.async {
            var captured = self.capture()
            captured.lastAttemptAt = .now
            let reading = captured
            DispatchQueue.main.async { completion(reading) }
        }
    }

    private func capture() -> BalanceReading {
        guard let discovery = Self.discovery() else {
            return BalanceProvider.workbuddy.failed("WorkBuddy 未运行（找不到本地通道）")
        }
        do {
            let body = try WbipcConnection(endpoint: discovery.endpoint, ticket: discovery.ticket).fetchResourceSummary()
            return WorkBuddyBalanceParser.reading(from: body)
        } catch let error as WbipcError {
            return BalanceProvider.workbuddy.failed(error.displayMessage)
        } catch {
            return BalanceProvider.workbuddy.failed("读取失败：\(error.localizedDescription)")
        }
    }

    private static func discovery() -> (endpoint: String, ticket: String)? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configDirectory = ProcessInfo.processInfo.environment["WORKBUDDY_CONFIG_DIR"]
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
            ?? home.appendingPathComponent(".workbuddy", isDirectory: true)
        let url = configDirectory.appendingPathComponent("wbipc/endpoint.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let endpoint = (object["endpoint"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let ticket = (object["ticket"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !endpoint.isEmpty, !ticket.isEmpty else { return nil }
        return (endpoint, ticket)
    }
}

struct WbipcError: Error {
    let displayMessage: String
}

/// One short-lived WBIPC connection: handshake, one JSON-RPC call, close.
private final class WbipcConnection {
    private let endpoint: String
    private let ticket: String
    private let channel: WbipcChannel
    private var nextRequestID = 1
    private let protocolVersion = 1

    init(endpoint: String, ticket: String, timeout: TimeInterval = 12) throws {
        self.endpoint = endpoint
        self.ticket = ticket
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw WbipcError(displayMessage: "无法创建本地连接") }
        let transport = try WbipcChannel(fileDescriptor: descriptor, timeout: timeout)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let pathBytes = Array(endpoint.utf8)
        guard !pathBytes.contains(0), !pathBytes.isEmpty, pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw WbipcError(displayMessage: "WorkBuddy 通道路径无效")
        }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 104) { destination in
                for (index, byte) in pathBytes.enumerated() { destination[index] = CChar(bitPattern: byte) }
            }
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result != 0 {
            guard errno == EINPROGRESS else { throw WbipcError(displayMessage: "无法连接 WorkBuddy（客户端需保持运行）") }
            try transport.waitFor(POLLOUT)
            var error: Int32 = 0
            var size = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &error, &size) == 0, error == 0 else {
                throw WbipcError(displayMessage: "无法连接 WorkBuddy（客户端需保持运行）")
            }
        }
        channel = transport
    }

    /// Returns the raw JSON body of `/billing/meter/get-user-resource-summary`.
    func fetchResourceSummary() throws -> Data {
        try handshake()

        guard let pipeResponse = try request("broker/GetPipe", ["pipe": "wb.request"]),
              let pipeResult = pipeResponse["result"] as? [String: Any],
              let channel = pipeResult["channel"] as? String else {
            throw WbipcError(displayMessage: "WorkBuddy 通道未提供请求能力")
        }
        let params: [String: Any] = [
            "method": "POST",
            "path": "/billing/meter/get-user-resource-summary",
            "headers": ["content-type": "application/json", "accept": "application/json"],
            "body_b64": Data("{}".utf8).base64EncodedString(),
        ]
        guard let response = try request("\(channel)/http.fetch", params, mode: "call") else {
            throw WbipcError(displayMessage: "WorkBuddy 未返回额度数据")
        }
        if let error = response["error"] as? [String: Any] {
            let code = (error["code"] as? String) ?? ""
            if code == "E_CONSENT_REQUIRED" {
                throw WbipcError(displayMessage: "请在 WorkBuddy 中授权本应用读取额度")
            }
            let message = (error["message"] as? String) ?? code
            throw WbipcError(displayMessage: "WorkBuddy 返回错误：\(message)")
        }
        guard let result = response["result"] as? [String: Any] else {
            throw WbipcError(displayMessage: "WorkBuddy 返回格式异常")
        }
        if let status = result["status"] as? Int, !(200...299).contains(status) {
            throw WbipcError(displayMessage: "WorkBuddy 接口返回 HTTP \(status)")
        }
        guard let bodyBase64 = result["body_b64"] as? String,
              let body = Data(base64Encoded: bodyBase64) else {
            throw WbipcError(displayMessage: "WorkBuddy 返回内容为空")
        }
        return body
    }

    private func handshake() throws {
        let clientNonce = Self.randomNonce()
        try channel.send([
            "type": "session_hello",
            "protocol_min": protocolVersion,
            "protocol_max": protocolVersion,
            "client_nonce": clientNonce,
            "ticket_id": Self.ticketID(ticket),
            "client": ["kind": "skill", "id": "codex-energy-bar", "version": "1.4.0"],
        ])
        guard let frame = try channel.readFrame() else {
            throw WbipcError(displayMessage: "WorkBuddy 通道握手无响应")
        }
        guard (frame["type"] as? String) == "session_challenge",
              let serverNonce = frame["server_nonce"] as? String,
              let serverProof = frame["server_proof"] as? String else {
            throw WbipcError(displayMessage: "WorkBuddy 通道握手被拒绝")
        }
        let expected = Self.proof(ticket: ticket, role: "server", protocolVersion: protocolVersion,
                                  endpoint: endpoint, clientNonce: clientNonce, serverNonce: serverNonce)
        guard expected == serverProof else {
            throw WbipcError(displayMessage: "WorkBuddy 通道校验失败（客户端可能已更新）")
        }
        try channel.send([
            "type": "session_prove",
            "client_proof": Self.proof(ticket: ticket, role: "client", protocolVersion: protocolVersion,
                                       endpoint: endpoint, clientNonce: clientNonce, serverNonce: serverNonce),
        ])
        guard let ack = try channel.readFrame(), (ack["type"] as? String) == "session_hello_ack" else {
            throw WbipcError(displayMessage: "WorkBuddy 通道握手未完成")
        }
    }

    private func request(_ method: String, _ params: [String: Any], mode: String? = nil) throws -> [String: Any]? {
        let identifier = nextRequestID
        nextRequestID += 1
        var frame: [String: Any] = ["jsonrpc": "2.0", "id": identifier, "method": method, "params": params]
        if let mode { frame["mode"] = mode }
        try channel.send(frame)
        return try channel.response(matching: identifier)
    }

    private static func randomNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func ticketID(_ ticket: String) -> String {
        let digest = SHA256.hash(data: Data(ticket.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    private static func proof(ticket: String, role: String, protocolVersion: Int, endpoint: String,
                              clientNonce: String, serverNonce: String) -> String {
        let domain = role == "server" ? "wbipc-s" : "wbipc-c"
        var message = Data()
        for part in [domain, "\(protocolVersion)", endpoint, clientNonce, serverNonce] {
            let bytes = Data(part.utf8)
            var length = UInt32(bytes.count).bigEndian
            withUnsafeBytes(of: &length) { message.append(contentsOf: $0) }
            message.append(bytes)
        }
        let key = SymmetricKey(data: Data(ticket.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: key)
        return base64URL(Data(mac))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Bounded newline transport shared with synthetic socket-pair tests. One
/// monotonic deadline covers every write, frame and unrelated response.
final class WbipcChannel {
    typealias Writer = (Int32, UnsafeRawPointer?, Int) -> Int
    private let descriptor: Int32
    private let deadline: UInt64
    private let writer: Writer
    private var buffer = Data()
    private var frameCount = 0
    private var receivedBytes = 0
    static let maximumFrameBytes = 1_048_576
    static let maximumReceivedBytes = 4_194_304
    static let maximumFrames = 256

    init(fileDescriptor: Int32, timeout: TimeInterval = 12, writer: Writer? = nil) throws {
        descriptor = fileDescriptor
        self.writer = writer ?? { Darwin.write($0, $1, $2) }
        let safeTimeout = timeout.isFinite ? min(max(timeout, 0.001), 60) : 12
        deadline = DispatchTime.now().uptimeNanoseconds + UInt64(safeTimeout * 1_000_000_000)
        var noSignal: Int32 = 1
        guard setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size)) == 0,
              fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK) == 0 else {
            close(descriptor)
            throw WbipcError(displayMessage: "无法配置 WorkBuddy 本地连接")
        }
    }

    deinit { close(descriptor) }

    func waitFor(_ events: Int32) throws {
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { throw WbipcError(displayMessage: "WorkBuddy 通道超时") }
            var descriptorState = pollfd(fd: descriptor, events: Int16(events), revents: 0)
            let milliseconds = Int32(max(1, (deadline - now + 999_999) / 1_000_000))
            let result = poll(&descriptorState, 1, milliseconds)
            if result < 0 && errno == EINTR { continue }
            guard result > 0 else { throw WbipcError(displayMessage: result == 0 ? "WorkBuddy 通道超时" : "WorkBuddy 通道不可用") }
            guard Int32(descriptorState.revents) & (POLLERR | POLLNVAL) == 0 else { throw WbipcError(displayMessage: "WorkBuddy 通道已断开") }
            if Int32(descriptorState.revents) & events != 0 { return }
            throw WbipcError(displayMessage: "WorkBuddy 通道已断开")
        }
    }

    func send(_ frame: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: frame)
        guard data.count <= Self.maximumFrameBytes else { throw WbipcError(displayMessage: "WorkBuddy 请求帧过大") }
        data.append(0x0A)
        var offset = 0
        try data.withUnsafeBytes { bytes in
            while offset < bytes.count {
                try waitFor(POLLOUT)
                let written = writer(descriptor, bytes.baseAddress?.advanced(by: offset), bytes.count - offset)
                if written < 0 && [EINTR, EAGAIN, EWOULDBLOCK].contains(errno) { continue }
                guard written > 0 && written <= bytes.count - offset else { throw WbipcError(displayMessage: "WorkBuddy 通道写入失败") }
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
            guard DispatchTime.now().uptimeNanoseconds < deadline else { throw WbipcError(displayMessage: "WorkBuddy 通道超时") }
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                frameCount += 1
                guard line.count <= Self.maximumFrameBytes, frameCount <= Self.maximumFrames else {
                    throw WbipcError(displayMessage: "WorkBuddy 返回帧超限")
                }
                guard let frame = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    throw WbipcError(displayMessage: "WorkBuddy 返回格式异常")
                }
                return frame
            }
            guard buffer.count <= Self.maximumFrameBytes else { throw WbipcError(displayMessage: "WorkBuddy 返回帧过大") }
            try waitFor(POLLIN)
            var chunk = [UInt8](repeating: 0, count: 16_384)
            let count = Darwin.read(descriptor, &chunk, chunk.count)
            if count < 0 && [EINTR, EAGAIN, EWOULDBLOCK].contains(errno) { continue }
            guard count > 0 else { throw WbipcError(displayMessage: "WorkBuddy 通道已断开") }
            receivedBytes += count
            guard receivedBytes <= Self.maximumReceivedBytes else { throw WbipcError(displayMessage: "WorkBuddy 返回数据过大") }
            buffer.append(contentsOf: chunk[0..<count])
        }
    }
}
