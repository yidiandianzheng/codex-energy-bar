import Foundation

/// Local, per-user configuration for the extra balance sources.
///
/// Secrets live only in `~/.config/codex-energy-bar/sources.json` (0600) and are
/// never written to the repository or uploaded anywhere. The file is optional:
/// DeepSeek can be discovered from keys the machine already stores, WorkBuddy
/// and 千问办公 use their own local channels, and 豆包 reads its own client login
/// state.
struct BalanceConfig: Equatable {
    var deepSeekAPIKey: String?
    var doubaoCookie: String?
    var doubaoProductLine: String?
    var workBuddyEnabled: Bool
    var qwenWorkEnabled: Bool

    static let empty = BalanceConfig(deepSeekAPIKey: nil, doubaoCookie: nil, doubaoProductLine: nil,
                                     workBuddyEnabled: true, qwenWorkEnabled: true)

    static var directoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/codex-energy-bar", isDirectory: true)
    }

    static var fileURL: URL {
        directoryURL.appendingPathComponent("sources.json")
    }

    static func load() -> BalanceConfig {
        var config = BalanceConfig.empty
        if let data = try? Data(contentsOf: fileURL),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let deepseek = object["deepseek"] as? [String: Any],
               let key = (deepseek["apiKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !key.isEmpty {
                config.deepSeekAPIKey = key
            }
            if let doubao = object["doubao"] as? [String: Any] {
                if let cookie = (doubao["cookie"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !cookie.isEmpty {
                    config.doubaoCookie = cookie
                }
                if let line = (doubao["productLine"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty {
                    config.doubaoProductLine = line
                }
            }
            if let workbuddy = object["workbuddy"] as? [String: Any],
               let enabled = workbuddy["enabled"] as? Bool {
                config.workBuddyEnabled = enabled
            }
            if let qwenwork = object["qwenwork"] as? [String: Any],
               let enabled = qwenwork["enabled"] as? Bool {
                config.qwenWorkEnabled = enabled
            }
        }
        if config.deepSeekAPIKey == nil {
            config.deepSeekAPIKey = discoverDeepSeekKey()
        }
        return config
    }

    /// DeepSeek key discovery, in priority order:
    /// 1. `sources.json` (handled by the caller),
    /// 2. `DEEPSEEK_API_KEY` environment variable,
    /// 3. a DeepSeek model entry that WorkBuddy already stores locally.
    static func discoverDeepSeekKey() -> String? {
        if let env = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"],
           !env.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return env.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let modelsURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".workbuddy/models.json")
        guard let data = try? Data(contentsOf: modelsURL),
              let models = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        for model in models {
            let vendor = (model["vendor"] as? String)?.lowercased() ?? ""
            let url = (model["url"] as? String)?.lowercased() ?? ""
            guard vendor == "deepseek" || url.contains("api.deepseek.com") else { continue }
            if let key = (model["apiKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
                return key
            }
        }
        return nil
    }

    /// Creates an empty template with 0600 permissions when the user asks for
    /// the config file (menu item). Existing files are left untouched.
    @discardableResult
    static func prepareTemplateFile() -> URL? {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if !fileManager.fileExists(atPath: fileURL.path) {
                let template = """
                {
                  "_comment": "算力环额外账户配置。只保存在本机，权限 0600。",
                  "deepseek": { "apiKey": "" },
                  "doubao": { "cookie": "", "productLine": "" },
                  "workbuddy": { "enabled": true },
                  "qwenwork": { "enabled": true }
                }
                """
                try template.write(to: fileURL, atomically: true, encoding: .utf8)
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            }
            return fileURL
        } catch {
            return nil
        }
    }
}
