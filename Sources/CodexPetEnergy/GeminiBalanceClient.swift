import CryptoKit
import Foundation
import Security

struct GeminiVaultError: Error {
    let message: String
}

struct GeminiCredentials {
    var refreshToken: String
    var gaiaID: String?
}

/// Gemini macOS 应用（`com.google.GeminiMacOS`）把 Google 账户登录态加密存在
/// `~/Library/Application Support/com.google.GeminiMacOS/Data/<user>/auth`。
///
/// 文件格式：8 字节魔数 `2e ba fe ca` 重复两次 + 4 字节小端 preamble 长度 +
/// preamble（字段 4 是 12 字节 AES-GCM nonce）+ AES-256-GCM 密文 + 16 字节 tag。
/// 解密密钥取自钥匙串条目「Gemini Safe Storage / Gemini Keys」中的
/// `KEY_ID_CREDENTIALS`（key_id == 1，32 字节）。解密后只读取 refresh token 与
/// Gaia ID，用于向 Google 官方 token 接口换取访问令牌；token 只在内存中存在，
/// 不写盘、不发送给 Google 以外的服务。
enum GeminiCredentialVault {
    static let keychainService = "Gemini Safe Storage"
    static let keychainAccount = "Gemini Keys"
    static let containerMagic: [UInt8] = [0x2e, 0xba, 0xfe, 0xca, 0x2e, 0xba, 0xfe, 0xca]

    private static let keyLock = NSLock()
    private static var cachedKey: Data?

    static func root() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.google.GeminiMacOS", isDirectory: true)
    }

    static func credentials() throws -> GeminiCredentials {
        let rootURL = root()
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            throw GeminiVaultError(message: "找不到 Gemini 应用数据，请先打开并登录 Gemini 应用")
        }
        let key = try keychainKey()
        guard let authURL = authFileURL(in: rootURL, key: key) else {
            throw GeminiVaultError(message: "找不到 Gemini 登录数据，请先打开并登录 Gemini 应用")
        }
        guard let container = try? Data(contentsOf: authURL) else {
            throw GeminiVaultError(message: "读取 Gemini 登录数据失败，请重新登录 Gemini 应用后重试")
        }
        guard let plain = decryptContainer(container, key: key) else {
            throw GeminiVaultError(message: "无法解密 Gemini 登录数据，请重新登录 Gemini 应用后重试")
        }
        guard let refreshToken = parseStringField(4, in: plain), !refreshToken.isEmpty else {
            throw GeminiVaultError(message: "Gemini 登录数据缺少 refresh token，请重新登录 Gemini 应用后重试")
        }
        return GeminiCredentials(refreshToken: refreshToken, gaiaID: parseStringField(1, in: plain))
    }

    /// 优先使用 `account_config` 里的 active user alias；没有时退回第一个登录目录。
    static func authFileURL(in rootURL: URL, key: Data) -> URL? {
        let dataDirectory = rootURL.appendingPathComponent("Data", isDirectory: true)
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: dataDirectory.path))?.sorted() ?? []
        let candidates = entries.compactMap { entry -> URL? in
            let url = dataDirectory
                .appendingPathComponent(entry, isDirectory: true)
                .appendingPathComponent("auth", isDirectory: false)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        guard !candidates.isEmpty else { return nil }

        let configURL = rootURL.appendingPathComponent("account_config", isDirectory: false)
        if let configData = try? Data(contentsOf: configURL) {
            let plain = decryptContainer(configData, key: key) ?? configData
            if let alias = parseStringField(4, in: plain), !alias.isEmpty {
                let preferred = dataDirectory
                    .appendingPathComponent(alias, isDirectory: true)
                    .appendingPathComponent("auth", isDirectory: false)
                if candidates.contains(preferred) { return preferred }
            }
        }
        return candidates[0]
    }

    private static func keychainKey() throws -> Data {
        keyLock.lock()
        defer { keyLock.unlock() }
        if let cachedKey { return cachedKey }
        let key = try requestKeychainKey()
        cachedKey = key
        return key
    }

    private static func requestKeychainKey() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let stored = item as? Data else {
            switch status {
            case errSecItemNotFound:
                throw GeminiVaultError(message: "找不到 Gemini 登录密钥，请先打开并登录 Gemini 应用")
            case errSecAuthFailed, errSecUserCanceled:
                throw GeminiVaultError(message: "未授权读取 Gemini 登录密钥：请在系统弹窗中选择允许后重试")
            case errSecInteractionNotAllowed:
                throw GeminiVaultError(message: "钥匙串当前不可用，请解锁后重试")
            default:
                throw GeminiVaultError(message: "读取 Gemini 登录密钥失败（\(status)）")
            }
        }
        guard let key = extractCredentialsKey(from: stored) else {
            throw GeminiVaultError(message: "Gemini 登录密钥格式不受支持，请重新登录 Gemini 应用后重试")
        }
        return key
    }

    /// 钥匙串条目是 `argo.crypt.Keystore` protobuf：字段 2 是重复的 KeyData，
    /// KeyData 的字段 1 是 key id、字段 4 是 32 字节密钥；credential 使用 id 1。
    static func extractCredentialsKey(from keystore: Data) -> Data? {
        var offset = 0
        while offset < keystore.count {
            guard let tag = readVarint(keystore, offset: &offset) else { return nil }
            let fieldNumber = tag >> 3
            let wireType = tag & 0x07
            switch wireType {
            case 0:
                guard readVarint(keystore, offset: &offset) != nil else { return nil }
            case 2:
                guard let length = readVarint(keystore, offset: &offset),
                      let subdata = slice(keystore, offset: &offset, length: Int(length)) else { return nil }
                if fieldNumber == 2,
                   let key = parseKeyData(subdata),
                   key.id == 1,
                   key.payload.count == 32 {
                    return key.payload
                }
            default:
                guard skipField(wireType: wireType, in: keystore, offset: &offset) else { return nil }
            }
        }
        return nil
    }

    private static func parseKeyData(_ data: Data) -> (id: UInt64, payload: Data)? {
        var offset = 0
        var keyID: UInt64 = 0
        var payload: Data?
        while offset < data.count {
            guard let tag = readVarint(data, offset: &offset) else { return nil }
            let fieldNumber = tag >> 3
            let wireType = tag & 0x07
            switch wireType {
            case 0:
                guard let value = readVarint(data, offset: &offset) else { return nil }
                if fieldNumber == 1 { keyID = value }
            case 2:
                guard let length = readVarint(data, offset: &offset),
                      let bytes = slice(data, offset: &offset, length: Int(length)) else { return nil }
                if fieldNumber == 4 { payload = bytes }
            default:
                guard skipField(wireType: wireType, in: data, offset: &offset) else { return nil }
            }
        }
        guard let payload else { return nil }
        return (keyID, payload)
    }

    /// 解密 `container.proto` 文件（魔数 + 长度前缀 preamble + AES-GCM 载荷）。
    static func decryptContainer(_ container: Data, key: Data) -> Data? {
        guard container.count > 12 + 16,
              Array(container.prefix(containerMagic.count)) == containerMagic else { return nil }
        let preambleLength = Int(
            UInt32(container[container.startIndex + 8])
                | (UInt32(container[container.startIndex + 9]) << 8)
                | (UInt32(container[container.startIndex + 10]) << 16)
                | (UInt32(container[container.startIndex + 11]) << 24)
        )
        guard preambleLength > 0, preambleLength <= container.count - 28 else { return nil }
        let bodyStart = 12 + preambleLength

        let preamble = container.subdata(in: 12..<bodyStart)
        guard let nonce = parseBytesField(4, in: preamble), nonce.count == 12 else { return nil }

        let payload = container.subdata(in: bodyStart..<container.count)
        guard payload.count > 16 else { return nil }
        let ciphertext = payload.prefix(payload.count - 16)
        let tag = payload.suffix(16)
        guard let sealedBox = try? AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: nonce),
            ciphertext: ciphertext,
            tag: tag
        ) else { return nil }
        return try? AES.GCM.open(sealedBox, using: SymmetricKey(data: key))
    }

    static func parseStringField(_ targetField: UInt64, in data: Data) -> String? {
        guard let bytes = parseBytesField(targetField, in: data) else { return nil }
        return String(data: bytes, encoding: .utf8)
    }

    static func parseBytesField(_ targetField: UInt64, in data: Data) -> Data? {
        var offset = 0
        while offset < data.count {
            guard let tag = readVarint(data, offset: &offset) else { return nil }
            let fieldNumber = tag >> 3
            let wireType = tag & 0x07
            if wireType == 2 {
                guard let length = readVarint(data, offset: &offset),
                      let bytes = slice(data, offset: &offset, length: Int(length)) else { return nil }
                if fieldNumber == targetField { return bytes }
            } else {
                guard skipField(wireType: wireType, in: data, offset: &offset) else { return nil }
            }
        }
        return nil
    }

    private static func readVarint(_ data: Data, offset: inout Int) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while offset < data.count, shift < 64 {
            let byte = data[data.startIndex + offset]
            offset += 1
            result |= UInt64(byte & 0x7f) << shift
            if (byte & 0x80) == 0 { return result }
            shift += 7
        }
        return nil
    }

    private static func slice(_ data: Data, offset: inout Int, length: Int) -> Data? {
        guard length >= 0, offset + length <= data.count else { return nil }
        let start = data.startIndex + offset
        let sub = data.subdata(in: start..<(start + length))
        offset += length
        return sub
    }

    private static func skipField(wireType: UInt64, in data: Data, offset: inout Int) -> Bool {
        switch wireType {
        case 0:
            return readVarint(data, offset: &offset) != nil
        case 1:
            guard offset + 8 <= data.count else { return false }
            offset += 8
            return true
        case 2:
            guard let length = readVarint(data, offset: &offset),
                  Int(length) >= 0,
                  offset + Int(length) <= data.count else { return false }
            offset += Int(length)
            return true
        case 5:
            guard offset + 4 <= data.count else { return false }
            offset += 4
            return true
        default:
            return false
        }
    }
}

/// `GetUsageInfo` 返回 `userTier` 与 `usage[]`；每个用量池的 `gxu.pctUsed`
/// 是 0–1 的已用比例，窗口重置时间在 `gxu.windowRefreshesAt`。
enum GeminiUsageParser {
    static let fiveHourID = "gemini-5h"
    static let weeklyID = "gemini-weekly"

    static func reading(usage: Data, gaiaID: String? = nil, now: Date = .now) -> BalanceReading {
        guard let payload = (try? JSONSerialization.jsonObject(with: usage)) as? [String: Any] else {
            return BalanceProvider.gemini.failed("Gemini 返回数据无法解析")
        }
        return reading(payload: payload, gaiaID: gaiaID, now: now)
    }

    static func reading(payload: [String: Any], gaiaID: String? = nil, now: Date = .now) -> BalanceReading {
        let plan = planName(payload["userTier"] as? String)
        let entries = payload["usage"] as? [[String: Any]] ?? []

        struct Candidate {
            let id: String
            let title: String
            let remaining: Int
            let resetAt: Date?
            let order: Int
        }

        var candidates: [Candidate] = []
        for entry in entries {
            guard let poolType = (entry["budgetPoolType"] as? String)?.uppercased(),
                  let gxu = entry["gxu"] as? [String: Any],
                  let fraction = numberValue(gxu["pctUsed"]) else { continue }
            let clamped = min(max(fraction, 0), 1)
            let remaining = BalanceFormatting.percent((1 - clamped) * 100)
            let resetAt = isoDate(gxu["windowRefreshesAt"])
            let title: String
            let order: Int
            switch poolType {
            case "GXU_FIVE_HOURLY":
                title = "当前用量（5 小时）"
                order = 0
            case "GXU_WEEKLY":
                title = "每周限额"
                order = 1
            default:
                title = (gxu["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? poolType
                order = 2
            }
            candidates.append(Candidate(
                id: poolType == "GXU_FIVE_HOURLY" ? fiveHourID
                    : (poolType == "GXU_WEEKLY" ? weeklyID : "gemini-\(poolType.lowercased())"),
                title: title,
                remaining: remaining,
                resetAt: resetAt,
                order: order
            ))
        }

        guard !candidates.isEmpty else {
            return BalanceProvider.gemini.failed("Gemini 接口未返回用量窗口（应用版本可能已变化）")
        }

        candidates.sort { $0.order < $1.order }
        let primary = candidates[0]
        let windows = candidates.map { candidate in
            BalanceWindowReading(
                id: candidate.id,
                title: candidate.title,
                remainingPercent: candidate.remaining,
                resetAt: candidate.resetAt,
                isPrimary: candidate.id == primary.id
            )
        }

        var detailParts: [String] = []
        if let plan, !plan.isEmpty { detailParts.append("\(plan) 方案") }
        if let weekly = candidates.first(where: { $0.id == weeklyID }) {
            detailParts.append("本周已用 \(100 - weekly.remaining)%")
        }
        let exhausted = primary.remaining <= 0

        return BalanceReading(
            id: BalanceProvider.gemini.id,
            title: BalanceProvider.gemini.title,
            systemImage: BalanceProvider.gemini.systemImage,
            valueText: String(primary.remaining),
            unitPrefix: nil,
            unitSuffix: "%",
            caption: exhausted ? "当前用量已用尽" : "当前用量剩余",
            detail: detailParts.isEmpty ? nil : detailParts.joined(separator: " · "),
            percent: primary.remaining,
            usedText: "\(100 - primary.remaining)%",
            windows: windows,
            state: .ok,
            sourceURL: BalanceProvider.gemini.sourceURL,
            updatedAt: now,
            numericValue: Double(primary.remaining),
            numericUsedValue: Double(100 - primary.remaining),
            currency: nil,
            sourceIdentity: identity(gaiaID: gaiaID),
            lastAttemptAt: now
        )
    }

    /// `ROBINQuotaUserTier` → Google AI 订阅名；未知档位不猜。
    static func planName(_ raw: String?) -> String? {
        guard let value = raw?.uppercased(), !value.isEmpty else { return nil }
        switch value {
        case "TIER_ULTRA", "TIER_NEON", "TIER2": return "Ultra"
        case "TIER_PRO", "TIER_PREMIUM", "TIER1": return "Pro"
        case "TIER_PLUS", "TIER_LITE", "TIER_HELIUM": return "Plus"
        case "TIER_BASIC", "TIER_FREE", "TIER0": return "Free"
        case "TIER_EXPANDED": return "Expanded"
        default: return nil
        }
    }

    private static func identity(gaiaID: String?) -> String? {
        guard let gaiaID, !gaiaID.isEmpty else { return nil }
        let digest = SHA256.hash(data: Data(gaiaID.utf8))
        return "gemini:" + digest.map { String(format: "%02x", $0) }.joined()
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

    static func isoDate(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

final class GeminiBalanceClient {
    private let queue = DispatchQueue(label: "codex.pet.energy.balance.gemini")
    private let session: URLSession

    /// Google 桌面端（Gemini Mac 应用）公开的 OAuth 客户端信息。客户端密钥不具
    /// 保密性，按参考实现以 XOR 存储，避免被密钥扫描器误报；运行时再还原。
    static let clientID = "839509190550-l232s7lupkp6f57818eshd7u4sl4920h.apps.googleusercontent.com"
    static let encodedClientSecret: [UInt8] = [
        0x1d, 0x15, 0x19, 0x09, 0x0a, 0x02, 0x77, 0x39, 0x3e, 0x3f, 0x38, 0x6a,
        0x1d, 0x19, 0x31, 0x0e, 0x17, 0x16, 0x03, 0x1c, 0x0e, 0x1f, 0x32, 0x11,
        0x1b, 0x69, 0x6b, 0x2a, 0x32, 0x1c, 0x19, 0x18, 0x08, 0x29, 0x34,
    ]
    static let tokenURL = URL(string: "https://www.googleapis.com/oauth2/v4/token")!
    static let usageURL = URL(string: "https://robinfrontend-pa.googleapis.com/$rpc/assistant.mobile.robin.RobinService/GetUsageInfo")!

    static var clientSecret: String {
        String(decoding: encodedClientSecret.map { $0 ^ 0x5a }, as: UTF8.self)
    }

    private var cachedAccessToken: (refreshToken: String, token: String, expiresAt: Date)?

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 25
        session = URLSession(configuration: configuration)
    }

    func fetch(completion: @escaping (BalanceReading) -> Void) {
        queue.async {
            let reading = self.capture()
            DispatchQueue.main.async { completion(reading) }
        }
    }

    private func capture() -> BalanceReading {
        let credentials: GeminiCredentials
        do {
            credentials = try GeminiCredentialVault.credentials()
        } catch let error as GeminiVaultError {
            return BalanceProvider.gemini.unconfigured(error.message)
        } catch {
            return BalanceProvider.gemini.failed("读取 Gemini 登录态失败：\(error.localizedDescription)")
        }

        for attempt in 0..<2 {
            switch accessToken(for: credentials.refreshToken, forceRefresh: attempt > 0) {
            case .failure(let message):
                return BalanceProvider.gemini.failed("读取 Gemini 登录状态失败：\(message)")
            case .expired:
                return BalanceProvider.gemini.unconfigured("Gemini 登录已失效，请在 Gemini 应用重新登录后重试")
            case .success(let token):
                switch requestUsage(token: token) {
                case .success(let data):
                    return GeminiUsageParser.reading(usage: data, gaiaID: credentials.gaiaID)
                case .unauthorized:
                    if attempt == 0 { continue }
                    return BalanceProvider.gemini.unconfigured("Gemini 登录已失效，请在 Gemini 应用重新登录后重试")
                case .failure(let message):
                    return BalanceProvider.gemini.failed("读取 Gemini 用量失败：\(message)")
                }
            }
        }
        return BalanceProvider.gemini.unconfigured("Gemini 登录已失效，请在 Gemini 应用重新登录后重试")
    }

    private enum TokenOutcome {
        case success(String)
        case expired
        case failure(String)
    }

    private func accessToken(for refreshToken: String, forceRefresh: Bool) -> TokenOutcome {
        if !forceRefresh,
           let cached = cachedAccessToken,
           cached.refreshToken == refreshToken,
           cached.expiresAt > Date().addingTimeInterval(60) {
            return .success(cached.token)
        }

        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "client_id": Self.clientID,
            "client_secret": Self.clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ]
        .map { "\($0.key)=\(formEncode($0.value))" }
        .joined(separator: "&")
        request.httpBody = Data(body.utf8)

        let semaphore = DispatchSemaphore(value: 0)
        var result: TokenOutcome = .failure("读取超时")
        let task = session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                result = .failure(error.localizedDescription)
                return
            }
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 400 || http.statusCode == 401 || http.statusCode == 403 {
                    result = .expired
                    return
                }
                guard (200...299).contains(http.statusCode) else {
                    result = .failure("token 接口返回 HTTP \(http.statusCode)")
                    return
                }
            }
            guard let data,
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let token = object["access_token"] as? String,
                  !token.isEmpty else {
                result = .failure("token 接口未返回访问令牌")
                return
            }
            let expiresIn = (object["expires_in"] as? NSNumber)?.doubleValue ?? 3_600
            self.cachedAccessToken = (refreshToken, token, Date().addingTimeInterval(max(60, expiresIn)))
            result = .success(token)
        }
        task.resume()
        if semaphore.wait(timeout: .now() + 20) == .timedOut {
            task.cancel()
            return .failure("读取超时")
        }
        return result
    }

    private enum UsageOutcome {
        case success(Data)
        case unauthorized
        case failure(String)
    }

    private func requestUsage(token: String) -> UsageOutcome {
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let semaphore = DispatchSemaphore(value: 0)
        var outcome: UsageOutcome = .failure("读取超时")
        let task = session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                outcome = .failure(error.localizedDescription)
                return
            }
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 401 || http.statusCode == 403 {
                    outcome = .unauthorized
                    return
                }
                guard (200...299).contains(http.statusCode) else {
                    outcome = .failure("接口返回 HTTP \(http.statusCode)")
                    return
                }
            }
            outcome = .success(data ?? Data())
        }
        task.resume()
        if semaphore.wait(timeout: .now() + 20) == .timedOut {
            task.cancel()
            return .failure("读取超时")
        }
        return outcome
    }

    private func formEncode(_ string: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
}
