import CommonCrypto
import CoreFoundation
import CryptoKit
import Foundation
import Security

/// Qoder CN（阿里 Qoder 国内版）把登录凭证加密存放在自己的配置目录里：
/// `~/Library/Application Support/com.qodercn.app.stable/auth.v1.dat` 的前 3 字节
/// 是 ASCII `v10`（Electron/Chromium safe-storage 标志），其余为 AES-128-CBC
/// 密文；密钥由钥匙串条目「Qoder CN App Safe Storage」的密码经
/// PBKDF2-HMAC-SHA1（salt `saltysalt`、1003 轮、16 字节）派生，IV 为 16 个空格。
///
/// 解密只得到 token、到期时间与账户信息，用于向 Qoder 官方额度接口认证；
/// token 只在内存中存在，不写盘、不发送给其他服务，与豆包、百度搭子读取自身
/// 登录态的方式一致。
struct QoderVaultError: Error {
    let message: String
}

struct QoderCredentials {
    var token: String
    var expiresAt: Date?
}

enum QoderCredentialVault {
    /// 配置目录固定，不扫描其他位置，避免读到别的账号残留。
    static func root() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.qodercn.app.stable", isDirectory: true)
    }

    static func credentials() throws -> QoderCredentials {
        let file = root().appendingPathComponent("auth.v1.dat")
        guard let encrypted = try? Data(contentsOf: file), encrypted.count > 3 else {
            throw QoderVaultError(message: "找不到 Qoder CN 登录数据，请先打开并登录 Qoder CN 客户端")
        }
        guard String(data: encrypted.prefix(3), encoding: .ascii) == "v10" else {
            throw QoderVaultError(message: "Qoder CN 登录数据格式不受支持，请重新登录 Qoder CN 客户端后重试")
        }
        let key = try keychainKey()
        guard let plain = decrypt(encrypted, key: key),
              let object = (try? JSONSerialization.jsonObject(with: plain)) as? [String: Any] else {
            throw QoderVaultError(message: "无法解密 Qoder CN 登录数据，请重新登录客户端后重试")
        }
        guard let token = (object["token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            throw QoderVaultError(message: "Qoder CN 登录数据无法解析，请重新登录客户端后重试")
        }
        return QoderCredentials(token: token, expiresAt: isoDate(object["expiresAt"]))
    }

    private static let keyLock = NSLock()
    private static var cachedKey: Data?

    /// The keychain item is reused for the lifetime of the process: asking macOS
    /// once per launch instead of once per five-minute refresh.
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
            kSecAttrService as String: "Qoder CN App Safe Storage",
            kSecAttrAccount as String: "Qoder CN App Key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let stored = item as? Data else {
            switch status {
            case errSecItemNotFound:
                throw QoderVaultError(message: "找不到 Qoder CN 登录密钥，请打开 Qoder CN 客户端后重试")
            case errSecAuthFailed, errSecUserCanceled:
                throw QoderVaultError(message: "未授权读取 Qoder CN 登录态：请在系统弹窗中选择允许后重试")
            default:
                throw QoderVaultError(message: "读取 Qoder CN 登录密钥失败（\(status)）")
            }
        }
        // Electron 把随机密钥存成可打印 ASCII 字符串（24 字节），PBKDF2 的密码
        // 就是这串字节本身；尾部若带 NUL 填充先去掉。
        var password = stored
        while password.last == 0x00 { password.removeLast() }
        guard !password.isEmpty else {
            throw QoderVaultError(message: "Qoder CN 登录密钥为空，请重新登录客户端后重试")
        }
        return pbkdf2(password: password)
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

    private static func decrypt(_ encrypted: Data, key: Data) -> Data? {
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
        return output
    }

    private static func isoDate(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }
}

/// Qoder 的 `quota/usage` 返回套餐与附加包两段额度；剩余百分比由本应用按
/// remaining / total 自行计算，不采用接口里量级含糊的 `percentage` 字段。
enum QoderUsageParser {
    static func reading(usage: Data, plan: Data? = nil, now: Date = .now) -> BalanceReading {
        guard let usageObject = try? JSONSerialization.jsonObject(with: usage) as? [String: Any] else {
            return BalanceProvider.qoder.failed("Qoder CN 返回数据无法解析")
        }
        let planObject = plan.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        return reading(usage: usageObject, plan: planObject, now: now)
    }

    static func reading(usage: [String: Any], plan: [String: Any]? = nil, now: Date = .now) -> BalanceReading {
        let quota = portion(usage["userQuota"])
        let addOn = portion(usage["addOnQuota"])
        guard quota != nil || addOn != nil else {
            return BalanceProvider.qoder.failed("Qoder CN 接口未返回积分额度（可能版本已变化）")
        }

        var capacity: Double = 0
        var remaining: Double = 0
        var used: Double = 0
        if let quota {
            capacity += max(quota.total, 0)
            remaining += max(quota.remaining, 0)
            used += max(quota.used, 0)
        }
        if let addOn {
            capacity += max(addOn.total, 0)
            remaining += max(addOn.remaining, 0)
            used += max(addOn.used, 0)
        }

        let exceeded = booleanValue(usage["isQuotaExceeded"]) ?? (remaining <= 0)
        var percent: Int?
        if capacity > 0, remaining.isFinite, remaining <= 1e15 {
            percent = BalanceFormatting.percent(remaining / capacity * 100)
        }
        if exceeded { percent = 0 }

        var details: [String] = []
        if let tier = stringValue(plan?["plan_tier_name"]), !tier.isEmpty {
            details.append(tier)
        }
        if let quota, quota.total > 0 {
            details.append("套餐 剩 \(credits(quota.remaining)) / \(credits(quota.total))（已用 \(credits(quota.used))）")
        }
        if let addOn, addOn.total > 0 {
            details.append("附加 已用 \(credits(addOn.used)) / \(credits(addOn.total))")
        }
        if let expiration = epochDate(usage["expiresAt"] ?? plan?["end_date"]) {
            details.append("至 " + expirationText(expiration))
        }
        if exceeded {
            details.append("本周期额度已用尽")
        }

        let caption: String
        if exceeded {
            caption = "额度已用尽"
        } else if percent != nil {
            caption = "套餐积分剩余"
        } else {
            caption = "剩余积分"
        }

        return BalanceReading(
            id: BalanceProvider.qoder.id,
            title: BalanceProvider.qoder.title,
            systemImage: BalanceProvider.qoder.systemImage,
            valueText: credits(remaining),
            unitPrefix: nil,
            unitSuffix: " 积分",
            caption: caption,
            detail: details.isEmpty ? nil : details.joined(separator: " · "),
            percent: percent,
            usedText: credits(used),
            windows: [],
            state: .ok,
            sourceURL: BalanceProvider.qoder.sourceURL,
            updatedAt: now,
            numericValue: remaining,
            numericUsedValue: used,
            currency: "credits",
            sourceIdentity: identity(from: usage),
            lastAttemptAt: now
        )
    }

    private struct Portion {
        var total: Double
        var used: Double
        var remaining: Double
    }

    private static func portion(_ value: Any?) -> Portion? {
        guard let object = value as? [String: Any] else { return nil }
        let total = numberValue(object["total"])
        let used = numberValue(object["used"])
        let remaining = numberValue(object["remaining"])
        // 三个数字全缺时不能当作「额度为 0」，那会伪造成「额度耗尽」。
        guard total != nil || used != nil || remaining != nil else { return nil }
        let resolvedTotal = total ?? 0
        let resolvedUsed = used ?? 0
        return Portion(total: resolvedTotal, used: resolvedUsed,
                       remaining: remaining ?? max(resolvedTotal - resolvedUsed, 0))
    }

    private static func credits(_ value: Double) -> String {
        BalanceFormatting.credits(String(value), fractionLength: 1) ?? "0"
    }

    private static func identity(from usage: [String: Any]) -> String? {
        guard let userID = stringValue(usage["userId"]), !userID.isEmpty else { return nil }
        let digest = SHA256.hash(data: Data(userID.utf8))
        return "qoder:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func expirationText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
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

    private static func epochDate(_ value: Any?) -> Date? {
        guard let number = numberValue(value), number > 1_000_000_000 else { return nil }
        return Date(timeIntervalSince1970: number > 1_000_000_000_000 ? number / 1_000 : number)
    }
}

final class QoderBalanceClient {
    private let queue = DispatchQueue(label: "codex.pet.energy.balance.qoder")
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        session = URLSession(configuration: configuration)
    }

    func fetch(completion: @escaping (BalanceReading) -> Void) {
        queue.async {
            let reading = self.capture()
            DispatchQueue.main.async { completion(reading) }
        }
    }

    private func capture() -> BalanceReading {
        let credentials: QoderCredentials
        do {
            credentials = try QoderCredentialVault.credentials()
        } catch let error as QoderVaultError {
            return BalanceProvider.qoder.unconfigured(error.message)
        } catch {
            return BalanceProvider.qoder.failed("读取 Qoder CN 登录态失败：\(error.localizedDescription)")
        }

        switch request(path: "/api/v2/quota/usage", token: credentials.token) {
        case .success(let data):
            // 套餐名与到期时间是可选的：拿不到不影响额度本身。
            let plan = request(path: "/api/v2/user/plan", token: credentials.token).data
            return QoderUsageParser.reading(usage: data, plan: plan)
        case .unauthorized:
            return BalanceProvider.qoder.unconfigured("Qoder CN 登录已过期，请在 Qoder CN 客户端重新登录后重试")
        case .failure(let message):
            return BalanceProvider.qoder.failed("读取 Qoder CN 额度失败：\(message)")
        }
    }

    private enum Outcome {
        case success(Data)
        case unauthorized
        case failure(String)

        var data: Data? { if case .success(let data) = self { return data }; return nil }
    }

    private func request(path: String, token: String) -> Outcome {
        guard let url = URL(string: "https://openapi.qoder.com.cn" + path) else {
            return .failure("接口地址无效")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let semaphore = DispatchSemaphore(value: 0)
        var outcome: Outcome = .failure("读取超时")
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
}