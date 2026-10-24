import Foundation

/// Decides which account cells belong on the compact Mini bar.
///
/// The Mini bar is a glance surface, not the account manager: an account whose
/// desktop client is not open only adds a "—" placeholder there. The balance
/// page keeps the full list, so a hidden account never becomes unreachable.
///
/// Codex is the app's primary account and DeepSeek is a server-side balance, so
/// neither depends on another app being open. 豆包、WorkBuddy、百度搭子 和千问办公
/// can only be read while their own client is running, which is exactly the
/// state this policy follows.
enum AccountVisibility {
    /// Account id → bundle identifier of the client app whose local state is
    /// read. Kept pure here (no AppKit) so the policy is unit-testable.
    static let clientBundleIdentifiers: [String: String] = [
        "doubao": "com.work.pc.doubao",
        "workbuddy": "com.tencent.workbuddy.mac",
        "workbuddyintl": "com.workbuddy.workbuddy-ai",
        "dumate": "com.baidu.qianfan.desktop",
        "qwenwork": "cn.qwenwork.desktop.mac",
    ]

    static let autoHideDefaultsKey = "energy-auto-hide-inactive-accounts"

    /// Accounts that are hidden from the compact bar right now.
    ///
    /// - Unconfigured accounts (no DeepSeek key, a client disabled in
    ///   `sources.json`) are noise on the glance surface and hide first.
    /// - Client-bound accounts hide while their client app is closed.
    /// - Codex is never hidden.
    static func hiddenIDs(
        readings: [BalanceReading],
        runningClients: Set<String>,
        autoHide: Bool
    ) -> Set<String> {
        guard autoHide else { return [] }
        var hidden: Set<String> = []
        for reading in readings where reading.id != BalanceReading.codexID {
            if case .unconfigured = reading.state {
                hidden.insert(reading.id)
                continue
            }
            if clientBundleIdentifiers[reading.id] != nil,
               !runningClients.contains(reading.id) {
                hidden.insert(reading.id)
            }
        }
        return hidden
    }

    static func visibleReadings(
        _ readings: [BalanceReading],
        runningClients: Set<String>,
        autoHide: Bool
    ) -> [BalanceReading] {
        let hidden = hiddenIDs(readings: readings, runningClients: runningClients, autoHide: autoHide)
        return readings.filter { !hidden.contains($0.id) }
    }
}

/// Local, non-secret preference for the compact bar. Defaults to on: the whole
/// point of the Mini bar is showing the accounts that are actually in use.
enum AccountVisibilityPreference {
    static func load(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: AccountVisibility.autoHideDefaultsKey) as? Bool ?? true
    }

    static func save(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: AccountVisibility.autoHideDefaultsKey)
    }
}
