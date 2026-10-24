import CryptoKit
import Foundation

/// 百度搭子（DuMate）把登录 Cookie 加密存放在自己的配置目录里：
/// `auth.json` 的 `cookies` 字段是 base64(iv + tag + ciphertext)，
/// 密钥是同一目录下 32 字节的 `.cookie-key`，算法为 AES-256-GCM（无 AAD）。
///
/// 解密后的 Cookie 只在内存中用于向百度智能云控制台的额度接口认证，
/// 不写盘、不发送给其他服务，与豆包读取自身登录态的方式一致。
struct DuMateVaultError: Error {
    let message: String
}

enum DuMateCookieVault {
    /// 配置目录固定，不扫描其他位置，避免读到别的账号残留。
    static func root() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/qianfan-desktop-app", isDirectory: true)
    }

    static func cookieHeader() throws -> String {
        let root = root()
        guard let authData = try? Data(contentsOf: root.appendingPathComponent("auth.json")),
              let object = try? JSONSerialization.jsonObject(with: authData) as? [String: Any],
              let encrypted = (object["cookies"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !encrypted.isEmpty else {
            throw DuMateVaultError(message: "找不到百度搭子登录数据，请先打开并登录客户端")
        }
        guard let key = try? Data(contentsOf: root.appendingPathComponent(".cookie-key")),
              key.count == 32 else {
            throw DuMateVaultError(message: "找不到百度搭子登录密钥")
        }
        guard let payload = Data(base64Encoded: encrypted), payload.count > 28 else {
            throw DuMateVaultError(message: "百度搭子登录数据格式异常")
        }
        let start = payload.startIndex
        let nonce = payload[start..<(start + 12)]
        let tag = payload[(start + 12)..<(start + 28)]
        let ciphertext = payload[(start + 28)...]
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce),
                                            ciphertext: ciphertext,
                                            tag: tag)
            let plain = try AES.GCM.open(box, using: SymmetricKey(data: key))
            return try header(from: plain)
        } catch {
            throw DuMateVaultError(message: "无法解密百度搭子登录数据，请重新登录客户端后重试")
        }
    }

    /// Chromium 风格的 cookie 列表 → `name=value; name=value`。
    /// 同名 cookie 只保留第一次出现的值，避免重复 header。
    private static func header(from data: Data) throws -> String {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw DuMateVaultError(message: "百度搭子登录数据无法解析")
        }
        var seen: Set<String> = []
        var pairs: [String] = []
        for item in list {
            guard let name = item["name"] as? String, !name.isEmpty,
                  let value = item["value"] as? String, !value.isEmpty,
                  !seen.contains(name) else { continue }
            seen.insert(name)
            pairs.append("\(name)=\(value)")
        }
        guard !pairs.isEmpty else {
            throw DuMateVaultError(message: "百度搭子登录数据为空，请重新登录客户端")
        }
        return pairs.joined(separator: "; ")
    }
}

enum DuMateBalanceParser {
    static func reading(from body: Data, now: Date = .now) -> BalanceReading {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return BalanceProvider.dumate.failed("百度搭子返回数据无法解析")
        }
        if let code = object["code"] as? Int, code != 0 {
            let message = (object["message"] as? String) ?? (object["msg"] as? String) ?? "业务错误 \(code)"
            return BalanceProvider.dumate.failed("百度搭子返回错误：\(message)")
        }
        guard let result = object["result"] as? [String: Any] else {
            return BalanceProvider.dumate.failed("百度搭子返回格式异常")
        }
        // totalPoints / usedPoints 是字符串，且可能是 "11060.00"。
        guard let total = number(result["totalPoints"]), total > 0,
              let used = number(result["usedPoints"]) else {
            return BalanceProvider.dumate.failed("百度搭子未返回积分额度（可能版本已变化）")
        }
        let remaining = max(total - used, 0)
        let percent = BalanceFormatting.percent(remaining / total * 100)

        var details: [String] = []
        if let plan = (result["subscription"] as? [[String: Any]])?.first,
           let planTotal = number(plan["totalPoints"]), planTotal > 0 {
            let planUsed = number(plan["usedPoints"]) ?? 0
            details.append("套餐 剩 \(credits(planTotal - planUsed)) / \(credits(planTotal))")
            if let expiry = number(plan["expireDate"]), expiry > 0 {
                details.append("至 " + expirationText(Date(timeIntervalSince1970: expiry)))
            }
        }
        details.append("已用 \(credits(used)) / \(credits(total))")
        if let incremental = result["incremental"] as? [[String: Any]], !incremental.isEmpty {
            details.append("赠送包 \(incremental.count) 个")
        }
        if let throttle = result["modelThrottleInfo"] as? [String: Any],
           (throttle["throttled"] as? Bool) == true {
            details.append("当前被限流")
        }

        return BalanceReading(
            id: BalanceProvider.dumate.id,
            title: BalanceProvider.dumate.title,
            systemImage: BalanceProvider.dumate.systemImage,
            valueText: credits(remaining),
            unitPrefix: nil,
            unitSuffix: " 积分",
            caption: "剩余积分",
            detail: details.joined(separator: " · "),
            percent: percent,
            usedText: credits(used),
            windows: [],
            state: .ok,
            sourceURL: BalanceProvider.dumate.sourceURL,
            updatedAt: now,
            numericValue: remaining,
            numericUsedValue: used,
            currency: "points",
            lastAttemptAt: now
        )
    }

    private static func number(_ value: Any?) -> Double? {
        let parsed: Double?
        if let string = value as? String { parsed = Double(string) }
        else if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { parsed = number.doubleValue }
        else { parsed = nil }
        guard let parsed, parsed.isFinite, parsed >= 0, parsed <= 1e15 else { return nil }
        return parsed
    }

    private static func credits(_ value: Double) -> String {
        BalanceFormatting.credits(String(value), fractionLength: 1) ?? "0"
    }

    private static func expirationText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }
}

final class DuMateBalanceClient {
    private let queue = DispatchQueue(label: "codex.pet.energy.balance.dumate")
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
        let cookie: String
        do {
            cookie = try DuMateCookieVault.cookieHeader()
        } catch let error as DuMateVaultError {
            return BalanceProvider.dumate.unconfigured(error.message)
        } catch {
            return BalanceProvider.dumate.failed("读取百度搭子登录态失败：\(error.localizedDescription)")
        }

        guard var components = URLComponents(string: "https://console.bce.baidu.com/api/dumate/points/quota_overview") else {
            return BalanceProvider.dumate.failed("百度搭子接口地址无效")
        }
        let zone = TimeZone.current.identifier.isEmpty ? "Asia/Shanghai" : TimeZone.current.identifier
        components.queryItems = [
            URLQueryItem(name: "timezone", value: zone),
            URLQueryItem(name: "clientType", value: "mac"),
            URLQueryItem(name: "ignoreLoginBonus", value: "true"),
        ]
        guard let url = components.url else {
            return BalanceProvider.dumate.failed("百度搭子接口地址无效")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("https://console.bce.baidu.com/dumate", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent")

        let semaphore = DispatchSemaphore(value: 0)
        var outcome: Result<Data, Error>?
        let task = session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                outcome = .failure(error)
                return
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                outcome = .failure(DuMateVaultError(message: "百度搭子接口返回 HTTP \(http.statusCode)"))
                return
            }
            outcome = .success(data ?? Data())
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 20)

        switch outcome {
        case .success(let data):
            var reading = DuMateBalanceParser.reading(from: data)
            // 与豆包一致：只用登录态的哈希做“同一账户”判据，今日用量换号后自动重算基线。
            reading.sourceIdentity = "dumate:" + SHA256.hash(data: Data(cookie.utf8))
                .map { String(format: "%02x", $0) }.joined()
            return reading
        case .failure(let error):
            return BalanceProvider.dumate.failed("读取百度搭子额度失败：\(error.localizedDescription)")
        case nil:
            task.cancel()
            return BalanceProvider.dumate.failed("读取百度搭子额度超时")
        }
    }
}
