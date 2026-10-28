import CommonCrypto
import CryptoKit
import Foundation

/// Trae CN（字节 Trae 国内版）把登录态加密存在自己的全局状态里：
/// `~/Library/Application Support/Trae CN/User/globalStorage/storage.json` 的
/// `iCubeAuthInfo://icube.cloudide` 是 base64 文本，解码后为
/// `6 字节头 + 32 字节随机密钥 + AES-128-CBC 密文`。AES 密钥与 IV 不来自
/// 钥匙串，而是由这 32 字节密钥经 SHA-512 与内置掩码派生，所以读取登录态
/// 不需要系统弹窗。解密只得到 token、账户与到期时间，用于向官方额度接口
/// 认证；token 只在内存中存在，不写盘、不发送给其他服务。
struct TraeVaultError: Error {
    let message: String
}

struct TraeCredentials {
    var token: String
    var userID: String?
    var expiresAt: Date?
}

enum TraeCredentialVault {
    static let persistedKey = "iCubeAuthInfo://icube.cloudide"

    /// 配置路径固定，不扫描其他位置，避免读到别的产品/账号残留。
    static func storageFile() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Trae CN/User/globalStorage/storage.json", isDirectory: false)
    }

    static func credentials() throws -> TraeCredentials {
        guard let data = try? Data(contentsOf: storageFile()),
              let store = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw TraeVaultError(message: "找不到 Trae CN 登录数据，请先打开并登录 Trae CN 客户端")
        }
        guard let encoded = store[persistedKey] as? String,
              let blob = Data(base64Encoded: encoded) else {
            throw TraeVaultError(message: "Trae CN 登录数据格式不受支持，请重新登录 Trae CN 客户端后重试")
        }
        guard let plain = decrypt(blob),
              let object = (try? JSONSerialization.jsonObject(with: plain)) as? [String: Any] else {
            throw TraeVaultError(message: "无法解密 Trae CN 登录数据，请重新登录客户端后重试")
        }
        guard let token = (object["token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            throw TraeVaultError(message: "Trae CN 登录数据无法解析，请重新登录客户端后重试")
        }
        let userID = (object["userId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return TraeCredentials(token: token, userID: userID?.isEmpty == false ? userID : nil,
                               expiresAt: epochDate(object["expiredAt"]))
    }

    /// 客户端把「AES」版本头写成 `tc\x05\x10\x00\x00`；其他版本（例如
    /// 系统安全存储包装）目前不出现，遇到时明确报格式不支持而不是猜。
    private static let aesHeader: [UInt8] = [0x74, 0x63, 0x05, 0x10, 0x00, 0x00]
    private static let keyLength = 32

    private static func decrypt(_ blob: Data) -> Data? {
        guard blob.count > aesHeader.count + keyLength + 64,
              Array(blob.prefix(aesHeader.count)) == aesHeader else { return nil }
        let key = blob.subdata(in: aesHeader.count..<(aesHeader.count + keyLength))
        let ciphertext = blob.subdata(in: (aesHeader.count + keyLength)..<blob.count)

        // SHA-512(key) 接固定掩码再哈希一次；前半段即 AES key(16) + IV(16)，
        // 与 Trae 的 byteCrypto 实现一致。
        var material = Data(SHA512.hash(data: key)) + mask
        let derived = Data(SHA512.hash(data: material))
        material.replaceSubrange(0..<64, with: derived)
        let aesKey = material.subdata(in: 0..<16)
        let iv = material.subdata(in: 16..<32)

        guard let plain = aesCBCDecrypt(ciphertext, key: aesKey, iv: iv), plain.count > 64 else { return nil }
        let proof = plain.subdata(in: 0..<64)
        let body = plain.subdata(in: 64..<plain.count)
        guard Data(SHA512.hash(data: body)) == proof else { return nil }
        return body
    }

    private static let mask: Data = {
        let left: [UInt8] = [
            82, 9, 106, 213, 48, 54, 165, 56, 191, 64, 163, 158, 129, 243, 215, 251,
            124, 227, 57, 130, 155, 47, 255, 135, 52, 142, 67, 68, 196, 222, 233, 203,
            84, 123, 148, 50, 166, 194, 35, 61, 238, 76, 149, 11, 66, 250, 195, 78,
            8, 46, 161, 102, 40, 217, 36, 178, 118, 91, 162, 73, 109, 139, 209, 37,
        ]
        let right: [UInt8] = [
            31, 221, 168, 51, 136, 7, 199, 49, 177, 18, 16, 89, 39, 128, 236, 95,
            96, 81, 127, 169, 25, 181, 74, 13, 45, 229, 122, 159, 147, 201, 156, 239,
            160, 224, 59, 77, 174, 42, 245, 176, 200, 235, 187, 60, 131, 83, 153, 97,
            23, 43, 4, 126, 186, 119, 214, 38, 225, 105, 20, 99, 85, 33, 12, 125,
        ]
        return Data(zip(left, right).map { $0 ^ $1 })
    }()

    private static func aesCBCDecrypt(_ ciphertext: Data, key: Data, iv: Data) -> Data? {
        var output = Data(count: ciphertext.count + kCCBlockSizeAES128)
        var outputLength = 0
        let capacity = output.count
        let status = output.withUnsafeMutableBytes { outputBytes in
            ciphertext.withUnsafeBytes { ciphertextBytes in
                iv.withUnsafeBytes { ivBytes in
                    key.withUnsafeBytes { keyBytes in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES128), CCOptions(kCCOptionPKCS7Padding),
                                keyBytes.baseAddress, key.count, ivBytes.baseAddress,
                                ciphertextBytes.baseAddress, ciphertext.count,
                                outputBytes.baseAddress, capacity, &outputLength)
                    }
                }
            }
        }
        guard status == CCCryptorStatus(kCCSuccess), outputLength > 0, outputLength <= output.count else { return nil }
        output.removeSubrange(outputLength..<output.count)
        return output
    }

    private static func epochDate(_ value: Any?) -> Date? {
        let number: Double?
        if let raw = value as? NSNumber, CFGetTypeID(raw) != CFBooleanGetTypeID() {
            number = raw.doubleValue
        } else if let text = value as? String {
            number = Double(text)
        } else {
            number = nil
        }
        guard let number, number > 1_000_000_000 else { return nil }
        return Date(timeIntervalSince1970: number > 1_000_000_000_000 ? number / 1_000 : number)
    }
}

/// `/trae/api/v2/pay/ide_user_ent_usage` 按权益包返回积分：
/// 每个包的 `quota.credits_limit` 是总额度，`usage.credits_amount` 是已用；
/// 顶层 `usage_summary` 是跨包的汇总（含已过期的包），有就以它为准。
enum TraeUsageParser {
    static func reading(usage: Data, userID: String? = nil, now: Date = .now) -> BalanceReading {
        guard let object = (try? JSONSerialization.jsonObject(with: usage)) as? [String: Any] else {
            return BalanceProvider.trae.failed("Trae CN 返回数据无法解析")
        }
        return reading(payload: object, userID: userID, now: now)
    }

    static func reading(payload: [String: Any], userID: String? = nil, now: Date = .now) -> BalanceReading {
        if let code = numberValue(payload["code"]), code != 0 {
            let message = (payload["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return BalanceProvider.trae.failed("Trae CN 返回错误：\(message?.isEmpty == false ? message! : "code \(Int(code))")")
        }

        let packs = (payload["user_entitlement_pack_list"] as? [[String: Any]]) ?? []
        var total: Double = 0
        var used: Double = 0
        var unlimited = false
        var labels: [String] = []
        var expiries: [Date] = []

        for pack in packs {
            guard let base = pack["entitlement_base_info"] as? [String: Any],
                  let quota = base["quota"] as? [String: Any],
                  let limit = numberValue(quota["credits_limit"]) else { continue }
            if limit < 0 { unlimited = true; continue }
            guard limit > 0 else { continue }
            total += limit
            let packUsed = numberValue((pack["usage"] as? [String: Any])?["credits_amount"]) ?? 0
            used += max(packUsed, 0)
            if let name = packLabel(pack), !labels.contains(name) {
                labels.append("\(name) \(credits(limit))")
            }
            if let expiry = epochDate(pack["expire_time"]), expiry > now {
                expiries.append(expiry)
            }
        }

        // 汇总字段更接近客户端自己显示的「本月已用」；缺字段时退回逐包相加。
        let summary = payload["usage_summary"] as? [String: Any]
        if let summaryTotal = numberValue(summary?["total_amount"]), summaryTotal > 0 {
            total = summaryTotal
            if let consumed = numberValue(summary?["consumed_amount"]), consumed >= 0 {
                used = consumed
            }
        }

        guard total > 0 || unlimited else {
            return BalanceProvider.trae.unconfigured("Trae CN 当前没有积分权益包；升级或领取奖励后可在客户端刷新读取")
        }

        var percent: Int?
        var remaining: Double?
        if !unlimited {
            let left = max(total - used, 0)
            remaining = left
            percent = BalanceFormatting.percent(left / total * 100)
        }

        var details: [String] = []
        if !labels.isEmpty {
            details.append(labels.joined(separator: " · "))
        }
        if !unlimited {
            details.append("已用 \(credits(used)) / \(credits(total))")
        }
        if let nearest = expiries.min() {
            details.append("至 " + dateText(nearest))
        }
        let exhausted = !unlimited && used >= total
        if exhausted {
            details.append("本周期额度已用尽")
        }

        let caption: String
        if unlimited {
            caption = "积分不限"
        } else if exhausted {
            caption = "额度已用尽"
        } else {
            caption = "套餐积分剩余"
        }

        return BalanceReading(
            id: BalanceProvider.trae.id,
            title: BalanceProvider.trae.title,
            systemImage: BalanceProvider.trae.systemImage,
            valueText: unlimited ? "不限" : credits(remaining ?? 0),
            unitPrefix: nil,
            unitSuffix: unlimited ? nil : " 积分",
            caption: caption,
            detail: details.isEmpty ? nil : details.joined(separator: " · "),
            percent: exhausted ? 0 : percent,
            usedText: unlimited ? nil : credits(used),
            windows: [],
            state: .ok,
            sourceURL: BalanceProvider.trae.sourceURL,
            updatedAt: now,
            numericValue: remaining,
            numericUsedValue: unlimited ? nil : used,
            currency: "credits",
            sourceIdentity: identity(userID: userID, payload: payload),
            lastAttemptAt: now
        )
    }

    private static func packLabel(_ pack: [String: Any]) -> String? {
        for key in ["group_name", "display_desc"] {
            if let value = (pack[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func identity(userID: String?, payload: [String: Any]) -> String? {
        var id = userID
        if id == nil {
            let packs = (payload["user_entitlement_pack_list"] as? [[String: Any]]) ?? []
            for pack in packs {
                let base = pack["entitlement_base_info"] as? [String: Any]
                if let value = (base?["user_id"] as? String) ?? (base?["user_id"] as? NSNumber)?.stringValue,
                   !value.isEmpty {
                    id = value
                    break
                }
            }
        }
        guard let id, !id.isEmpty else { return nil }
        let digest = SHA256.hash(data: Data(id.utf8))
        return "trae:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func credits(_ value: Double) -> String {
        BalanceFormatting.credits(String(value), fractionLength: 1) ?? "0"
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
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

    private static func epochDate(_ value: Any?) -> Date? {
        guard let number = numberValue(value), number > 1_000_000_000 else { return nil }
        return Date(timeIntervalSince1970: number > 1_000_000_000_000 ? number / 1_000 : number)
    }
}

final class TraeBalanceClient {
    private let queue = DispatchQueue(label: "codex.pet.energy.balance.trae")
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
        let credentials: TraeCredentials
        do {
            credentials = try TraeCredentialVault.credentials()
        } catch let error as TraeVaultError {
            return BalanceProvider.trae.unconfigured(error.message)
        } catch {
            return BalanceProvider.trae.failed("读取 Trae CN 登录态失败：\(error.localizedDescription)")
        }

        switch request(token: credentials.token) {
        case .success(let data):
            return TraeUsageParser.reading(usage: data, userID: credentials.userID)
        case .unauthorized:
            return BalanceProvider.trae.unconfigured("Trae CN 登录已过期，请在 Trae CN 客户端重新登录后重试")
        case .failure(let message):
            return BalanceProvider.trae.failed("读取 Trae CN 额度失败：\(message)")
        }
    }

    private enum Outcome {
        case success(Data)
        case unauthorized
        case failure(String)
    }

    private func request(token: String) -> Outcome {
        guard let url = URL(string: "https://api.trae.cn/trae/api/v2/pay/ide_user_ent_usage") else {
            return .failure("接口地址无效")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Cloud-IDE-JWT \(token)", forHTTPHeaderField: "Authorization")
        // req_source: 1 表示 IDE，与客户端自身查询用量时一致。
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["require_usage": true, "req_source": 1])

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
