import Foundation

@MainActor enum NightWatchSelfTest {
    static func check(into failures: inout [String]) {
        func expect(_ condition: Bool, _ message: String) { if !condition { failures.append("night watch: " + message) } }

        let pluggedIn = BatteryStatus(hasBattery: true, isOnBattery: false, percentage: 5)
        var sleepCount = 0
        let controller = NightWatchController(sleepDisplays: { sleepCount += 1 }, battery: { pluggedIn })
        expect(!controller.isActive && controller.startedAt == nil, "starts inactive")
        controller.start()
        expect(controller.isActive && controller.startedAt != nil, "start acquires the wake lock")
        expect(sleepCount == 1, "start turns the display off once")
        controller.start()
        expect(sleepCount == 1, "repeated start stays idempotent")
        controller.stop()
        expect(!controller.isActive && controller.startedAt == nil, "stop releases the wake lock")
        controller.stop()
        expect(sleepCount == 1, "repeated stop stays idempotent")

        let store = SelfTest.makeStore(nightWatch: controller)
        store.activate(.nightWatch)
        expect(store.isNightWatchActive && store.nightWatchStartedAt != nil, "Mini action starts night watch")
        expect(sleepCount == 2, "store activation reaches the power controller")
        store.tick(now: Date().addingTimeInterval(61))
        expect(store.nightWatchElapsedText == "已开启 1 分钟", "elapsed text follows the app clock")
        store.activate(.nightWatch)
        expect(!store.isNightWatchActive && store.nightWatchElapsedText == nil, "Mini action stops night watch")
        expect(sleepCount == 2, "stopping does not sleep the display again")

        var battery = BatteryStatus(hasBattery: true, isOnBattery: false, percentage: 10)
        var autoSleepCount = 0
        let autoController = NightWatchController(sleepDisplays: { autoSleepCount += 1 }, battery: { battery })
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        autoController.start()
        autoController.checkBattery(now: start.addingTimeInterval(15))
        expect(autoController.isActive, "plugged-in low battery keeps running")
        battery = BatteryStatus(hasBattery: true, isOnBattery: true, percentage: 20)
        autoController.checkBattery(now: start.addingTimeInterval(30))
        expect(autoController.isActive, "battery above the threshold keeps running")
        battery = BatteryStatus(hasBattery: true, isOnBattery: true, percentage: 15)
        autoController.checkBattery(now: start.addingTimeInterval(45))
        expect(!autoController.isActive, "battery at the threshold releases the wake lock")
        expect(autoController.autoStopPercent == 15, "auto stop records the battery level")
        expect(autoController.autoStoppedAt == start.addingTimeInterval(45), "auto stop records the time")
        expect(autoSleepCount == 1, "auto stop does not sleep the display again")
        autoController.start()
        expect(autoController.autoStopPercent == nil && autoController.autoStoppedAt == nil,
               "restart clears the auto stop record")
        autoController.stop()

        let lowBattery = BatteryStatus(hasBattery: true, isOnBattery: true, percentage: 9)
        let lowController = NightWatchController(sleepDisplays: {}, battery: { lowBattery })
        let tickStore = SelfTest.makeStore(nightWatch: lowController)
        let lowStart = Date(timeIntervalSince1970: 1_800_000_000)
        tickStore.activate(.nightWatch)
        expect(tickStore.isNightWatchActive, "low battery does not block a manual start")
        tickStore.tick(now: lowStart.addingTimeInterval(15))
        expect(!tickStore.isNightWatchActive, "app clock applies the low battery guard")
        expect(tickStore.nightWatchNoticeText == "电量 9%，已自动关闭", "notice names the battery level")
        tickStore.tick(now: lowStart.addingTimeInterval(614))
        expect(tickStore.nightWatchNoticeText == "电量 9%，已自动关闭", "notice lasts within ten minutes")
        tickStore.tick(now: lowStart.addingTimeInterval(616))
        expect(tickStore.nightWatchNoticeText == nil, "notice expires after ten minutes")
        tickStore.activate(.nightWatch)
        expect(tickStore.isNightWatchActive && tickStore.nightWatchNoticeText == nil,
               "restart clears the notice")
        tickStore.activate(.nightWatch)
    }
}
