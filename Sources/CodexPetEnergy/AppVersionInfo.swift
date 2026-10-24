import Foundation

/// 应用版本信息：版本号、构建号与构建日期。
///
/// 版本号（`CFBundleShortVersionString`）和构建号（`CFBundleVersion`）来自 App 包；
/// 构建日期由 `scripts/build-app.sh` 在打包时写入 `CFBundleBuildDate`（上海时区 yyyy-MM-dd）。
/// 直接 `swift run` 或旧构建没有该键时，回退到可执行文件的修改时间；
/// 两者都读不到时按“开发版”展示，不虚构版本号。
struct AppVersionInfo: Sendable {
    /// 版本与日期统一按上海时区展示，与应用内的额度、Token 统计口径一致。
    static let timeZone = TimeZone(identifier: "Asia/Shanghai")!
    static let chineseLocale = Locale(identifier: "zh_CN")
    /// 信息缺失时的内部占位，展示层会转换成“开发版”等可读文字。
    static let unknown = "—"

    let shortVersion: String
    let buildNumber: String
    let buildDate: Date?

    static let current = AppVersionInfo(bundle: .main)

    init(shortVersion: String, buildNumber: String, buildDate: Date?) {
        self.shortVersion = shortVersion
        self.buildNumber = buildNumber
        self.buildDate = buildDate
    }

    init(bundle: Bundle) {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let buildDateText = bundle.object(forInfoDictionaryKey: "CFBundleBuildDate") as? String
        self.init(
            shortVersion: Self.cleaned(version) ?? Self.unknown,
            buildNumber: Self.cleaned(build) ?? Self.unknown,
            buildDate: buildDateText.flatMap(Self.buildDate(fromText:)) ?? Self.executableModificationDate(bundle)
        )
    }

    /// 当前进程确实从带版本信息的 App 包运行（`swift run` 等开发运行没有版本号）。
    var isPackaged: Bool { shortVersion != Self.unknown }

    /// 标题栏、关于对话框共用的版本号文字，例如 `v1.4.0`。
    var versionText: String { isPackaged ? "v\(shortVersion)" : "开发版" }

    /// 构建号文字，例如 `第 75 版`；没有构建号时为 nil。
    var buildText: String? {
        guard isPackaged, buildNumber != Self.unknown else { return nil }
        return "第 \(buildNumber) 版"
    }

    /// 构建日期文字（yyyy-MM-dd）；未知时为 nil。
    var buildDateText: String? {
        buildDate.map { Self.text("yyyy-MM-dd", from: $0) }
    }

    /// 标题栏摘要，例如 `v1.4.0 · 第 75 版 · 构建 2026-10-23`。
    var summaryText: String {
        var parts = [versionText]
        if let buildText { parts.append(buildText) }
        if let buildDateText { parts.append("构建 \(buildDateText)") }
        return parts.joined(separator: " · ")
    }

    /// 关于对话框里的完整说明；未知字段明确写“未知”，不省略成空白。
    var aboutText: String {
        var lines = [isPackaged ? "版本 \(versionText)（\(buildText ?? "构建号未知")）" : "开发版（未从 App 包运行）"]
        lines.append("构建日期：\(buildDateText ?? "未知")")
        return lines.joined(separator: "\n")
    }

    /// 标题栏悬停提示：说明各段含义，并指向更新日志。
    var helpText: String {
        var lines = [isPackaged ? "\(versionText) · \(buildText ?? "构建号未知")" : "开发版（未从 App 包运行）"]
        lines.append("构建日期：\(buildDateText ?? "未知")")
        lines.append("更新日志见仓库 CHANGELOG.md")
        return lines.joined(separator: "\n")
    }

    /// 解析构建脚本写入的日期；也接受 ISO 8601 时间戳，便于其它构建环境复用。
    static func buildDate(fromText text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let calendarFormatter = DateFormatter()
        calendarFormatter.locale = Locale(identifier: "en_US_POSIX")
        calendarFormatter.calendar = Calendar(identifier: .gregorian)
        calendarFormatter.timeZone = timeZone
        calendarFormatter.dateFormat = "yyyy-MM-dd"
        if let date = calendarFormatter.date(from: trimmed) { return date }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.timeZone = timeZone
        return isoFormatter.date(from: trimmed)
    }

    private static func text(_ format: String, from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = chineseLocale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    /// 未打包运行时，可执行文件的修改时间就是这次构建的时间。
    private static func executableModificationDate(_ bundle: Bundle) -> Date? {
        guard let executable = bundle.executableURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: executable.path),
              let date = attributes[.modificationDate] as? Date
        else { return nil }
        return date
    }
}
