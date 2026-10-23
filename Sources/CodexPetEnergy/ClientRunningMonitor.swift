import AppKit

/// Watches whether the desktop clients behind the extra balance sources are
/// open. macOS broadcasts app launch/terminate notifications, so this needs no
/// polling loop, helper process or accessibility permission.
///
/// The account ↔ bundle mapping lives in `AccountVisibility` so the pure
/// visibility policy and this monitor can never drift apart.
final class ClientRunningMonitor {
    /// Called on the main queue whenever the set of open client accounts changes.
    var onChange: ((Set<String>) -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var current: Set<String> = []
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.publishIfChanged()
            })
        }
        publishIfChanged()
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers.removeAll()
        started = false
    }

    /// Recomputes from the live process list instead of trusting a single
    /// notification, so a missed event can never leave the bar stuck.
    func refresh() {
        publishIfChanged()
    }

    private func publishIfChanged() {
        let running = Self.runningAccounts()
        guard running != current else { return }
        current = running
        onChange?(running)
    }

    /// Reads the actual running-application list once per event; exact bundle
    /// identifier match keeps browser helpers and helpers of 豆包 out.
    static func runningAccounts() -> Set<String> {
        let applications = NSWorkspace.shared.runningApplications
        let identifiers = Set(applications.compactMap(\.bundleIdentifier))
        var accounts: Set<String> = []
        for (account, bundleIdentifier) in AccountVisibility.clientBundleIdentifiers
        where identifiers.contains(bundleIdentifier) {
            accounts.insert(account)
        }
        return accounts
    }
}
