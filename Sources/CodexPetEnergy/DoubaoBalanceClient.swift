import CommonCrypto
import CoreFoundation
import Foundation
import SQLite3
import Security

/// 豆包 membership quota lives behind the desktop client's login session. The
/// client stores its Chromium cookies encrypted (v10, AES with a key held by
/// the "DoubaoWork Browser Safe Storage" keychain item), so this reader asks
/// macOS once for permission, decrypts only the cookie values it needs, and
/// queries the same quota endpoint the in-app usage panel uses.
///
/// No credential is stored by this app; the decrypted cookie only lives in
/// memory for the lifetime of one refresh.
enum DoubaoQuotaParser {
    static func reading(from data: Data, now: Date = .now) -> BalanceReading {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return BalanceProvider.doubao.failed("返回数据无法解析")
        }
        if let code = object["code"] as? Int, code != 0 {
            let message = (object["msg"] as? String) ?? (object["message"] as? String) ?? "业务错误 \(code)"
            if code == 710012001 || message.contains("登录") {
                return BalanceProvider.doubao.failed("豆包登录已过期，请打开豆包客户端重新登录")
            }
            return BalanceProvider.doubao.failed(message)
        }
        let payload = (object["data"] as? [String: Any]) ?? object
        guard let windows = parseWindows(payload), !windows.isEmpty else {
            return BalanceProvider.doubao.failed("接口未返回额度窗口（可能版本已变化）")
        }
        // The rolling "当前时段" window is what limits usage right now; the
        // weekly window is the longer reserve. Match the in-app order.
        let rolling = windows.first { $0.id == "H5" } ?? windows.first { $0.id == "D7" } ?? windows[0]
        let weekly = windows.first { $0.id == "D7" }
        let planName = planName(from: payload)
        var detailParts: [String] = []
        if let planName { detailParts.append(planName) }
        if let weekly {
            if let reset = weekly.resetAt {
                detailParts.append("\(weekly.title) \(weekly.remainingPercent)% · \(shortReset(reset)) 重置")
            } else {
                detailParts.append("\(weekly.title) \(weekly.remainingPercent)%")
            }
        }
        for window in windows where window.id == "INC" {
            detailParts.append("\(window.title) \(window.remainingPercent)%")
        }
        return BalanceReading(
            id: BalanceProvider.doubao.id,
            title: BalanceProvider.doubao.title,
            systemImage: BalanceProvider.doubao.systemImage,
            valueText: "\(rolling.remainingPercent)",
            unitPrefix: nil,
            unitSuffix: "%",
            caption: "\(rolling.title)剩余\(rolling.resetAt.map { " · \(resetCountdown($0, now: now))重置" } ?? "")",
            detail: detailParts.joined(separator: " · "),
            percent: rolling.remainingPercent,
            windows: windows,
            state: .ok,
            sourceURL: BalanceProvider.doubao.sourceURL,
            updatedAt: now, numericValue: Double(rolling.remainingPercent), lastAttemptAt: now
        )
    }

    /// The quota summary groups windows into sections. Personal membership is
    /// in `window_limit_section`; the enterprise section is read too but is
    /// empty for personal accounts.
    private static func parseWindows(_ payload: [String: Any]) -> [BalanceWindowReading]? {
        var readings: [BalanceWindowReading] = []
        var seen = Set<String>()
        // Sections: personal membership, enterprise (usually empty), and the
        // activity-reward pool (shown only while it still has quota left).
        let sections: [(key: String, idPrefix: String?, title: String?)] = [
            ("window_limit_section", nil, nil),
            ("enterprise_window_limit_section", "ENT", "企业额度"),
            ("incentive_quota_section", "INC", "活动赠送"),
        ]
        for section in sections {
            guard let value = payload[section.key] as? [String: Any] else { continue }
            let groups = (value["window_limit_groups"] as? [[String: Any]])
                ?? (value["windowLimitGroups"] as? [[String: Any]])
                ?? []
            for group in groups {
                let limits = (group["window_limits"] as? [[String: Any]])
                    ?? (group["windowLimits"] as? [[String: Any]])
                    ?? []
                for limit in limits {
                    guard let windowType = windowType(from: limit), let remaining = remainingPercent(from: limit) else { continue }
                    // A spent activity pool is noise, not a constraint.
                    if section.key == "incentive_quota_section", remaining == 0 { continue }
                    let identifier = section.idPrefix.map { "\($0)-\(windowType.id)" } ?? windowType.id
                    guard !seen.contains(identifier) else { continue }
                    seen.insert(identifier)
                    readings.append(BalanceWindowReading(
                        id: identifier,
                        title: section.title ?? windowType.title,
                        remainingPercent: remaining,
                        resetAt: resetDate(from: limit),
                        isPrimary: identifier == "H5"
                    ))
                }
            }
        }
        guard !readings.isEmpty else { return nil }
        let order: [String: Int] = ["H5": 0, "D7": 1, "M1": 2, "SubscriptionTotal": 3, "INC-H5": 4, "INC-D7": 4, "INC-M1": 4]
        return readings.sorted { (order[$0.id] ?? 5) < (order[$1.id] ?? 5) }
    }

    private static func resetCountdown(_ date: Date, now: Date) -> String {
        let interval = date.timeIntervalSince(now)
        guard interval > 0 else { return "即将" }
        if interval < 3600 { return "\(max(1, Int(interval / 60))) 分钟后" }
        if interval < 86_400 { return "\(Int(interval / 3600)) 小时后" }
        return "\(Int(interval / 86_400)) 天后"
    }

    private static func shortReset(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: date)
    }

    private static func windowType(from limit: [String: Any]) -> (id: String, title: String)? {
        if let raw = limit["window_type"] {
            if let number = raw as? NSNumber {
                switch number.intValue {
                case 1: return ("H5", "当前时段")
                case 2: return ("D7", "近 7 天")
                case 3: return ("M1", "每月")
                case 4: return ("SubscriptionTotal", "套餐总额")
                default: return ("W\(number.intValue)", "额度")
                }
            }
            if let string = raw as? String {
                switch string.uppercased() {
                case "H5", "5H", "FIVEHOUR": return ("H5", "当前时段")
                case "D7", "7D", "WEEKLY": return ("D7", "近 7 天")
                case "M1", "MONTHLY": return ("M1", "每月")
                case "SUBSCRIPTIONTOTAL": return ("SubscriptionTotal", "套餐总额")
                default: return (string, string)
                }
            }
        }
        return nil
    }

    private static func remainingPercent(from limit: [String: Any]) -> Int? {
        if let used = number(limit["used_percent"]) ?? number(limit["usedPercent"]) {
            // The quota API always reports a 0–100 percentage (a 1 means 1%,
            // not a 0–1 fraction), so never rescale small values.
            guard (0...100).contains(used) else { return nil }
            return BalanceFormatting.percent(100 - used)
        }
        if let used = number(limit["used_amount"] ?? limit["usedAmount"]),
           let total = number(limit["total_amount"] ?? limit["totalAmount"]), total > 0, used >= 0, used <= total {
            return BalanceFormatting.percent((total - used) / total * 100)
        }
        return nil
    }

    private static func planName(from payload: [String: Any]) -> String? {
        guard let subscription = payload["current_subscription"] as? [String: Any],
              let display = subscription["display"] as? [String: Any],
              let name = display["short_name"] as? String, !name.isEmpty else { return nil }
        return name
    }

    private static func resetDate(from limit: [String: Any]) -> Date? {
        for key in ["end_time", "endTime", "end", "reset_time", "resetTime", "reset_at", "cycle_end_time"] {
            if let date = date(from: limit[key]) { return date }
        }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        let parsed: Double?
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { parsed = number.doubleValue }
        else if let string = value as? String { parsed = Double(string) }
        else { parsed = nil }
        guard let parsed, parsed.isFinite, abs(parsed) <= 1e15 else { return nil }
        return parsed
    }

    private static func date(from value: Any?) -> Date? {
        if let number = number(value) {
            if number > 1_000_000_000_000 { return Date(timeIntervalSince1970: number / 1000) }
            if number > 1_000_000_000 { return Date(timeIntervalSince1970: number) }
            return nil
        }
        guard let string = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: string) { return date }
        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "zh_CN")
        fallback.timeZone = TimeZone(identifier: "Asia/Shanghai")
        fallback.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return fallback.date(from: string)
    }
}

/// The membership badge ("标准套餐") is plain text in the client's Local State.
enum DoubaoMembership {
    // The quota response is the sole account-bound source of the badge. Local
    // multi-user stores do not provide a guaranteed Chromium profile mapping.
    static func displayName() -> String? { nil }
}

final class DoubaoBalanceClient {
    private let queue = DispatchQueue(label: "codex.pet.energy.balance.doubao")
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        session = URLSession(configuration: configuration)
    }

    func fetch(productLine: String?, fallbackCookie: String?, completion: @escaping (BalanceReading) -> Void) {
        queue.async {
            var captured = self.capture(productLine: productLine, fallbackCookie: fallbackCookie)
            captured.lastAttemptAt = .now
            let reading = captured
            DispatchQueue.main.async { completion(reading) }
        }
    }

    private func capture(productLine: String?, fallbackCookie: String?) -> BalanceReading {
        if let fallbackCookie, !fallbackCookie.isEmpty {
            var reading = postSummary(cookie: fallbackCookie, productLine: productLine)
            reading.sourceIdentity = "doubao:configured:" + SHA256Digest.hash(Data(fallbackCookie.utf8)).map { String(format: "%02x", $0) }.joined()
            reading.lastAttemptAt = .now
            return reading
        }
        do {
            let session = try DoubaoCookieReader.activeSession()
            var reading = postSummary(cookie: session.cookie, productLine: productLine)
            reading.sourceIdentity = "doubao:" + session.profile + ":" + SHA256Digest.hash(Data(session.cookie.utf8)).map { String(format: "%02x", $0) }.joined()
            reading.lastAttemptAt = .now
            return reading
        } catch let error as DoubaoCookieError {
            return BalanceProvider.doubao.failed(error.message)
        } catch {
            return BalanceProvider.doubao.failed("读取豆包登录态失败：\(error.localizedDescription)")
        }
    }

    private func postSummary(cookie: String, productLine: String?) -> BalanceReading {
        guard let url = URL(string: "https://www.doubao.com/alice/commerce/sale/subscription/quota/summary/") else {
            return BalanceProvider.doubao.failed("接口地址无效")
        }
        var body: [String: Any] = [:]
        if let productLine, !productLine.isEmpty {
            body["product_line"] = productLine
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("https://www.doubao.com/chat/", forHTTPHeaderField: "Referer")
        request.setValue("https://www.doubao.com", forHTTPHeaderField: "Origin")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let semaphore = DispatchSemaphore(value: 0)
        let result = DoubaoResponseBox()
        let task = session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                result.set(BalanceProvider.doubao.failed("请求失败：\(error.localizedDescription)"))
                return
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                result.set(BalanceProvider.doubao.failed("接口返回 HTTP \(http.statusCode)"))
                return
            }
            guard let data else {
                result.set(BalanceProvider.doubao.failed("接口无响应数据"))
                return
            }
            result.set(DoubaoQuotaParser.reading(from: data))
        }
        task.resume()
        guard semaphore.wait(timeout: .now() + 25) == .success else {
            task.cancel()
            return BalanceProvider.doubao.failed("豆包请求超时")
        }
        return result.get()
    }
}

struct DoubaoCookieError: Error {
    let message: String
}


/// Reads the desktop client's Chromium cookie store and decrypts the v10
/// values with the keychain key Chromium derived for that profile.
enum DoubaoCookieReader {
    static func activeSession() throws -> (profile: String, cookie: String) {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DoubaoWork", isDirectory: true)
        let profile = try activeProfile(in: root)
        return (profile.lastPathComponent, try cookies(for: profile, key: keychainKey()))
    }

    /// No fallback to a different account when last_used is stale or absent.
    /// Injectable directory lets offline tests use only synthetic Local State.
    static func activeProfile(in root: URL) throws -> URL {
        let manager = FileManager.default
        let state = (try? Data(contentsOf: root.appendingPathComponent("Local State")))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let name = (state?["profile"] as? [String: Any])?["last_used"] as? String
        let children = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let profiles = children.filter { child in
            (child.lastPathComponent == "Default" || child.lastPathComponent.hasPrefix("Profile "))
                && manager.fileExists(atPath: child.appendingPathComponent("Cookies").path)
        }
        if let name, !name.isEmpty {
            guard let active = profiles.first(where: { $0.lastPathComponent == name }) else {
                throw DoubaoCookieError(message: "当前豆包账号登录数据不可用，请打开客户端确认登录")
            }
            return active
        }
        guard profiles.count == 1, let only = profiles.first else {
            throw DoubaoCookieError(message: "无法确定当前豆包账号，请在豆包客户端选择账号后重试")
        }
        return only
    }

    private static func cookies(for profile: URL, key: Data) throws -> String {
        let source = profile.appendingPathComponent("Cookies")
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source.path) else {
            throw DoubaoCookieError(message: "找不到豆包客户端登录数据，请先打开并登录豆包")
        }
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("codex-energy-doubao-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }
        let copy = temporaryDirectory.appendingPathComponent("Cookies")
        do {
            try fileManager.copyItem(at: source, to: copy)
            for suffix in ["-wal", "-journal"] {
                let extra = URL(fileURLWithPath: source.path + suffix)
                if fileManager.fileExists(atPath: extra.path) {
                    try? fileManager.copyItem(at: extra, to: URL(fileURLWithPath: copy.path + suffix))
                }
            }
        } catch {
            throw DoubaoCookieError(message: "无法读取豆包登录数据：\(error.localizedDescription)")
        }

        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        guard sqlite3_open(copy.path, &database) == SQLITE_OK, let database else {
            throw DoubaoCookieError(message: "无法打开豆包登录数据")
        }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let query = "SELECT host_key, name, value, hex(encrypted_value) FROM cookies WHERE host_key LIKE '%doubao.com%' ORDER BY name"
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            throw DoubaoCookieError(message: "豆包登录数据格式异常")
        }
        var pairs: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let nameCString = sqlite3_column_text(statement, 1) else { continue }
            let name = String(cString: nameCString)
            let plaintext = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            let hex = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
            let value: String?
            if !plaintext.isEmpty {
                value = plaintext
            } else if let encrypted = Data(hexString: hex) {
                value = decrypt(encrypted, key: key)
            } else {
                value = nil
            }
            guard let value, !value.isEmpty else { continue }
            pairs.append("\(name)=\(value)")
        }
        guard !pairs.isEmpty else {
            throw DoubaoCookieError(message: "豆包登录态为空，请打开豆包客户端确认已登录")
        }
        return pairs.joined(separator: "; ")
    }

    private static let keyLock = NSLock()
    private static var cachedKey: Data?

    /// The keychain item is reused for the lifetime of the process: asking
    /// macOS once per launch instead of once per five-minute refresh.
    private static func keychainKey() throws -> Data {
        keyLock.lock()
        defer { keyLock.unlock() }
        if let cachedKey { return cachedKey }
        let service = "DoubaoWork Browser Safe Storage"
        let account = "DoubaoWork Browser"
        var length: UInt32 = 0
        var data: UnsafeMutableRawPointer?
        let status = SecKeychainFindGenericPassword(nil, UInt32(service.utf8.count), service,
                                                    UInt32(account.utf8.count), account, &length, &data, nil)
        guard status == errSecSuccess, let data else {
            if status == errSecItemNotFound {
                throw DoubaoCookieError(message: "找不到豆包登录密钥，请打开豆包客户端后重试")
            }
            if status == -25293 || status == errSecAuthFailed {
                throw DoubaoCookieError(message: "未授权读取豆包登录态：请在弹窗中选择允许；或在配置文件中填写 doubao.cookie")
            }
            throw DoubaoCookieError(message: "读取豆包登录密钥失败（\(status)）")
        }
        let password = Data(bytes: data, count: Int(length))
        SecKeychainItemFreeContent(nil, data)
        let key = pbkdf2(password: password)
        cachedKey = key
        return key
    }

    private static func pbkdf2(password: Data) -> Data {
        var key = Data(count: 16)
        let salt = Data("saltysalt".utf8)
        _ = key.withUnsafeMutableBytes { keyBytes in
            password.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress!.assumingMemoryBound(to: Int8.self), password.count,
                        saltBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                        keyBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), 16)
                }
            }
        }
        return key
    }

    private static func decrypt(_ encrypted: Data, key: Data) -> String? {
        guard encrypted.count > 3,
              String(data: encrypted.prefix(3), encoding: .ascii) == "v10" else { return nil }
        let ciphertext = encrypted.subdata(in: 3..<encrypted.count)
        let iv = Data(repeating: 0x20, count: 16)
        var output = Data(count: ciphertext.count + 16)
        var outputLength = 0
        let outputCapacity = output.count
        let status = output.withUnsafeMutableBytes { outputBytes in
            ciphertext.withUnsafeBytes { ciphertextBytes in
                iv.withUnsafeBytes { ivBytes in
                    key.withUnsafeBytes { keyBytes in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES128), CCOptions(kCCOptionPKCS7Padding),
                                keyBytes.baseAddress, 16, ivBytes.baseAddress,
                                ciphertextBytes.baseAddress, ciphertext.count,
                                outputBytes.baseAddress, outputCapacity, &outputLength)
                    }
                }
            }
        }
        guard status == CCCryptorStatus(kCCSuccess), outputLength > 0, outputLength <= output.count else { return nil }
        output.removeSubrange(outputLength..<output.count)
        // Chromium DB schema v24+: the plaintext is prefixed with a 32-byte
        // SHA-256 digest of the cookie domain. Fall back to an ASCII heuristic
        // when the domain form differs between Chromium builds.
        if output.count > 32 {
            let prefix = output.prefix(32)
            let hostDigest = Data(SHA256Digest.hash(Data(".doubao.com".utf8)))
            let printable = prefix.allSatisfy { $0 >= 0x20 && $0 < 0x7F }
            if Data(prefix) == hostDigest || !printable {
                output = output.subdata(in: 32..<output.count)
            }
        }
        return String(data: output, encoding: .utf8)
    }
}

private extension Data {
    init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hex.count % 2 == 0, !hex.isEmpty else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}

private enum SHA256Digest {
    static func hash(_ data: Data) -> [UInt8] {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        _ = data.withUnsafeBytes { bytes in
            CC_SHA256(bytes.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest
    }
}

private final class DoubaoResponseBox {
    private let lock = NSLock()
    private var value = BalanceProvider.doubao.failed("接口无响应")
    func set(_ reading: BalanceReading) { lock.lock(); defer { lock.unlock() }; value = reading }
    func get() -> BalanceReading { lock.lock(); defer { lock.unlock() }; return value }
}
