import Foundation
import IOKit.ps

/// 本机电池读数，只用于低电量保护，不写入任何存储或日志。
struct BatteryStatus: Equatable {
    var hasBattery: Bool
    var isOnBattery: Bool
    var percentage: Int?

    static let unavailable = BatteryStatus(hasBattery: false, isOnBattery: false, percentage: nil)

    /// 使用电池且电量不高于阈值时返回电量，插电或无电池时返回 nil。
    func lowBatteryPercent(threshold: Int) -> Int? {
        guard hasBattery, isOnBattery, let percentage, percentage <= threshold else { return nil }
        return percentage
    }
}

/// 夜间 AI 通宵模式（Mini 条显示「AI 通宵」）：只阻止系统因空闲而睡眠，
/// 不阻止显示器睡眠，语义等同 `caffeinate -i`。屏幕关闭后进程、网络和 AI
/// 后台任务继续运行；再次点击释放断言，恢复系统默认休眠。
/// 使用电池且电量不高于 15% 时自动退出，避免把电池耗尽。
@MainActor
final class NightWatchController {
    static let lowBatteryPercent = 15

    private(set) var isActive = false
    private(set) var startedAt: Date?
    /// 最近一次因低电量自动关闭的时间与电量；手动开/关会清除。
    private(set) var autoStoppedAt: Date?
    private(set) var autoStopPercent: Int?
    var onChange: (() -> Void)?

    private var activityToken: NSObjectProtocol?
    private var sleepRetryTasks: [Task<Void, Never>] = []
    private let sleepDisplays: () -> Void
    private let battery: () -> BatteryStatus

    init(sleepDisplays: @escaping () -> Void = NightWatchController.sleepDisplaysNow,
         battery: @escaping () -> BatteryStatus = NightWatchController.readBattery) {
        self.sleepDisplays = sleepDisplays
        self.battery = battery
    }

    func toggle() {
        if isActive { stop() } else { start() }
    }

    func start() {
        guard !isActive else { return }
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .userInitiated],
            reason: "AI 通宵：保持系统唤醒，让 AI 后台任务继续运行")
        isActive = true
        startedAt = .now
        autoStoppedAt = nil
        autoStopPercent = nil
        onChange?()
        scheduleDisplaySleep()
    }

    func stop() {
        stop(autoStoppedPercent: nil, now: .now)
    }

    /// 由应用时钟周期性调用：插电或不高于阈值时继续，低电量时自动退出。
    func checkBattery(now: Date) {
        guard isActive,
              let percent = battery().lowBatteryPercent(threshold: Self.lowBatteryPercent) else { return }
        stop(autoStoppedPercent: percent, now: now)
    }

    private func stop(autoStoppedPercent: Int?, now: Date) {
        guard isActive else { return }
        sleepRetryTasks.forEach { $0.cancel() }
        sleepRetryTasks = []
        if let activityToken { ProcessInfo.processInfo.endActivity(activityToken) }
        activityToken = nil
        isActive = false
        startedAt = nil
        self.autoStoppedAt = autoStoppedPercent == nil ? nil : now
        self.autoStopPercent = autoStoppedPercent
        onChange?()
    }

    /// 点击后的残余键鼠事件可能立刻唤醒显示器，因此再补两次关屏。
    private func scheduleDisplaySleep() {
        sleepDisplays()
        sleepRetryTasks.forEach { $0.cancel() }
        sleepRetryTasks = [1.0, 3.0].map { delay in
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled, let self, self.isActive else { return }
                self.sleepDisplays()
            }
        }
    }

    /// `pmset displaysleepnow` 不需要管理员权限；异步等待进程结束，避免阻塞主线程。
    nonisolated private static func sleepDisplaysNow() {
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["displaysleepnow"]
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    NSLog("AI 通宵：关闭显示器失败，pmset 退出码 %d", process.terminationStatus)
                }
            } catch {
                NSLog("AI 通宵：无法运行 pmset：%@", String(describing: error))
            }
        }
    }

    /// 通过 IOKit 读取内置电池；桌面 Mac 没有内置电池，返回不可用。
    nonisolated private static func readBattery() -> BatteryStatus {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return .unavailable
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?
                    .takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let onBattery = description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue
            let percentage: Int?
            if let current = description[kIOPSCurrentCapacityKey] as? Int,
               let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 {
                percentage = Int((Double(current) / Double(maximum) * 100).rounded())
            } else {
                percentage = nil
            }
            return BatteryStatus(hasBattery: true, isOnBattery: onBattery, percentage: percentage)
        }
        return .unavailable
    }
}
