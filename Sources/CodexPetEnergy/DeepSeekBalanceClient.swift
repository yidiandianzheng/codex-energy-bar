import Foundation
import CryptoKit

/// DeepSeek exposes an official balance endpoint for API keys:
/// `GET https://api.deepseek.com/user/balance`. The response is JSON with a
/// list of currency balances; CNY is the one the Chinese console shows.
enum DeepSeekBalanceParser {
    static func reading(from data: Data, now: Date = .now) -> BalanceReading {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return BalanceProvider.deepseek.failed("返回数据无法解析")
        }
        if let available = object["is_available"] as? Bool, available == false {
            return BalanceProvider.deepseek.failed("账户当前不可用")
        }
        guard let infos = object["balance_infos"] as? [[String: Any]], !infos.isEmpty else {
            return BalanceProvider.deepseek.failed("返回数据缺少余额字段")
        }
        let info = infos.first { ($0["currency"] as? String)?.uppercased() == "CNY" } ?? infos[0]
        guard let totalRaw = info["total_balance"] as? String,
              let rawValue = Double(totalRaw), rawValue.isFinite, abs(rawValue) <= 1e15,
              let total = BalanceFormatting.money(totalRaw),
              let currency = (info["currency"] as? String)?.uppercased(),
              currency.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil else {
            return BalanceProvider.deepseek.failed("余额数值或币种缺失/无效")
        }
        let prefix = currency == "CNY" ? "¥" : "\(currency) "
        func detailValue(_ key: String, label: String) -> String {
            guard let raw = info[key] as? String, let value = Double(raw), value.isFinite,
                  value >= 0, value <= 1e15, let formatted = BalanceFormatting.money(raw) else { return "\(label)待提供" }
            return "\(label) \(prefix)\(formatted)"
        }
        return BalanceReading(
            id: BalanceProvider.deepseek.id,
            title: BalanceProvider.deepseek.title,
            systemImage: BalanceProvider.deepseek.systemImage,
            valueText: total,
            unitPrefix: prefix,
            unitSuffix: nil,
            caption: "账户余额",
            detail: [detailValue("topped_up_balance", label: "充值"), detailValue("granted_balance", label: "赠送")].joined(separator: " · "),
            percent: nil,
            windows: [],
            state: .ok,
            sourceURL: BalanceProvider.deepseek.sourceURL,
            updatedAt: now, numericValue: rawValue, currency: currency, lastAttemptAt: now
        )
    }
}

final class DeepSeekBalanceClient {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        session = URLSession(configuration: configuration)
    }

    func fetch(apiKey: String, completion: @escaping (BalanceReading) -> Void) {
        guard let url = URL(string: "https://api.deepseek.com/user/balance") else {
            completion(BalanceProvider.deepseek.failed("接口地址无效"))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        session.dataTask(with: request) { data, response, error in
            let reading: BalanceReading
            if let error {
                reading = BalanceProvider.deepseek.failed("请求失败：\(error.localizedDescription)")
            } else if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                if http.statusCode == 401 {
                    reading = BalanceProvider.deepseek.failed("API Key 无效或已过期")
                } else {
                    reading = BalanceProvider.deepseek.failed("接口返回 HTTP \(http.statusCode)")
                }
            } else if let data {
                reading = DeepSeekBalanceParser.reading(from: data)
            } else {
                reading = BalanceProvider.deepseek.failed("接口无响应数据")
            }
            var identified = reading
            identified.sourceIdentity = "deepseek:" + SHA256.hash(data: Data(apiKey.utf8)).map { String(format: "%02x", $0) }.joined()
            identified.lastAttemptAt = .now
            DispatchQueue.main.async { completion(identified) }
        }.resume()
    }
}
