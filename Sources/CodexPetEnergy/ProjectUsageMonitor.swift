import Foundation

final class ProjectUsageMonitor {
    var onUpdate: ((ProjectUsageDaySummary) -> Void)?
    var onFailure: (() -> Void)?
    private var scanFailed = false

    private let queue = DispatchQueue(label: "codex.pet.energy.project-usage", qos: .utility)
    private let roots: [URL]
    private var timer: DispatchSourceTimer?
    private var cachedSessions: [String: ProjectUsageFileCache] = [:]
    private var cachedDayStart: Date?

    init(roots: [URL] = ProjectUsageMonitor.defaultRoots) {
        self.roots = roots.map { $0.resolvingSymlinksInPath() }
    }

    func start() {
        refresh(force: true)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 30, repeating: 30, leeway: .seconds(3))
        timer.setEventHandler { [weak self] in self?.refreshOnQueue() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func refresh(force: Bool = false) {
        queue.async { [weak self] in self?.refreshOnQueue(force: force) }
    }

    private func refreshOnQueue(force: Bool = false) {
        scanFailed = false
        let summary = readTodayUsingCache(now: Date(), force: force)
        let failed = scanFailed
        DispatchQueue.main.async { [weak self] in
            if failed { self?.onFailure?() } else { self?.onUpdate?(summary) }
        }
    }

    private func readTodayUsingCache(now: Date, force _: Bool) -> ProjectUsageDaySummary {
        let start = ProjectUsageLogic.startOfDay(containing: now)
        if cachedDayStart != start {
            cachedDayStart = start
            cachedSessions.removeAll()
        }

        var uniqueSessions: [String: ProjectUsageSession] = [:]
        for unresolvedRoot in roots {
            let root = unresolvedRoot.resolvingSymlinksInPath()
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles],
                errorHandler: { [weak self] _, _ in self?.scanFailed = true; return true }
            ) else { scanFailed = true; continue }

            for case let file as URL in enumerator {
                guard file.pathExtension == "jsonl",
                      let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]),
                      values.isRegularFile == true,
                      let modified = values.contentModificationDate,
                      modified >= start
                else { continue }

                guard FileManager.default.isReadableFile(atPath: file.path) else {
                    scanFailed = true
                    continue
                }
                let size = values.fileSize ?? 0
                let cacheKey = file.path
                let session: ProjectUsageSession?
                if let cached = cachedSessions[cacheKey],
                   cached.modified == modified,
                   cached.size == size {
                    session = cached.session
                } else {
                    let updated = Self.readSessionFile(
                        file,
                        modified: modified,
                        size: size,
                        cached: cachedSessions[cacheKey],
                        now: now
                    )
                    cachedSessions[cacheKey] = updated
                    session = updated.session
                }

                guard let session else { continue }
                if let existing = uniqueSessions[session.id] {
                    if session.totals.totalTokens > existing.totals.totalTokens
                        || session.lastActivity > existing.lastActivity {
                        uniqueSessions[session.id] = session
                    }
                } else {
                    uniqueSessions[session.id] = session
                }
            }
        }
        let sessions = Array(uniqueSessions.values)
        return ProjectUsageDaySummary(
            projects: ProjectUsageLogic.aggregate(sessions),
            sessionSwitchCount: ProjectUsageLogic.sessionSwitchCount(sessions)
        )
    }

    static var defaultRoots: [URL] {
        let codex = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        return [codex.appendingPathComponent("sessions"), codex.appendingPathComponent("archived_sessions")]
    }

    static func readToday(from roots: [URL], now: Date, fileManager: FileManager = .default) -> ProjectUsageDaySummary {
        var uniqueSessions: [String: ProjectUsageSession] = [:]
        let start = ProjectUsageLogic.startOfDay(containing: now)

        for unresolvedRoot in roots {
            let root = unresolvedRoot.resolvingSymlinksInPath()
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let file as URL in enumerator {
                guard file.pathExtension == "jsonl",
                      let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                      values.isRegularFile == true,
                      let modified = values.contentModificationDate,
                      modified >= start
                else { continue }

                let cache = readSessionFile(
                    file,
                    modified: modified,
                    size: values.fileSize ?? 0,
                    cached: nil,
                    now: now
                )
                guard let session = cache.session else { continue }

                if let existing = uniqueSessions[session.id] {
                    if session.totals.totalTokens > existing.totals.totalTokens
                        || session.lastActivity > existing.lastActivity {
                        uniqueSessions[session.id] = session
                    }
                } else {
                    uniqueSessions[session.id] = session
                }
            }
        }
        let sessions = Array(uniqueSessions.values)
        return ProjectUsageDaySummary(
            projects: ProjectUsageLogic.aggregate(sessions),
            sessionSwitchCount: ProjectUsageLogic.sessionSwitchCount(sessions)
        )
    }

    static func parseSession(_ text: String, fallbackID: String, now: Date) -> ProjectUsageSession? {
        let start = ProjectUsageLogic.startOfDay(containing: now)
        var accumulator = ProjectUsageSessionAccumulator(fallbackID: fallbackID)

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.contains("session_meta") || line.contains("token_count"),
                  let data = line.data(using: .utf8)
            else { continue }
            accumulator.consume(data, startOfDay: start)
        }

        return accumulator.makeSession()
    }

    private static func readSessionFile(
        _ file: URL,
        modified: Date,
        size: Int,
        cached: ProjectUsageFileCache?,
        now: Date
    ) -> ProjectUsageFileCache {
        let canContinue = cached.map {
            $0.size <= size && $0.bytesRead <= UInt64(size)
        } ?? false
        var result: ProjectUsageFileCache
        if canContinue, let cached {
            result = cached
        } else {
            result = ProjectUsageFileCache(
                fallbackID: file.path,
                modified: modified,
                size: size
            )
        }

        let start = ProjectUsageLogic.startOfDay(containing: now)
        if !canContinue {
            guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else {
                return result
            }
            result.pendingLine = result.accumulator.consumeCompleteJSONLines(
                in: data,
                startOfDay: start,
                includesSessionMetadata: true
            )
            result.bytesRead = UInt64(data.count)
            result.modified = modified
            result.size = size
            return result
        }

        guard let handle = try? FileHandle(forReadingFrom: file) else { return result }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: result.bytesRead)
            let appended = try handle.readToEnd() ?? Data()
            var buffer = result.pendingLine
            buffer.append(appended)
            result.pendingLine = result.accumulator.consumeCompleteJSONLines(
                in: buffer,
                startOfDay: start,
                includesSessionMetadata: result.bytesRead == 0
            )
            result.bytesRead = try handle.offset()
            result.modified = modified
            result.size = size
            return result
        } catch {
            return cached ?? result
        }
    }

}

struct ProjectUsageSession: Equatable {
    let id: String
    let directory: String
    let totals: ProjectUsageTotals
    let lastActivity: Date
}

struct ProjectUsageDaySummary: Equatable {
    let projects: [ProjectUsageReading]
    let sessionSwitchCount: Int

    var allProjectTotals: ProjectUsageTotals {
        projects.reduce(.zero) { $0.adding($1.totals) }
    }
}

enum ProjectUsageLogic {
    static let timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

    static func startOfDay(containing date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.startOfDay(for: date)
    }

    static func aggregate(_ sessions: [ProjectUsageSession], limit: Int = .max) -> [ProjectUsageReading] {
        var grouped: [String: ProjectUsageReading] = [:]
        for session in sessions {
            let name = URL(fileURLWithPath: session.directory).lastPathComponent
            if let existing = grouped[session.directory] {
                grouped[session.directory] = ProjectUsageReading(
                    directory: session.directory,
                    projectName: existing.projectName,
                    totals: existing.totals.adding(session.totals),
                    lastActivity: max(existing.lastActivity, session.lastActivity)
                )
            } else {
                grouped[session.directory] = ProjectUsageReading(
                    directory: session.directory,
                    projectName: name.isEmpty ? session.directory : name,
                    totals: session.totals,
                    lastActivity: session.lastActivity
                )
            }
        }
        return grouped.values
            .sorted {
                if $0.totals.totalTokens != $1.totals.totalTokens {
                    return $0.totals.totalTokens > $1.totals.totalTokens
                }
                return $0.lastActivity > $1.lastActivity
            }
            .prefix(limit)
            .map { $0 }
    }

    static func sessionSwitchCount(_ sessions: [ProjectUsageSession]) -> Int {
        let ordered = sessions.sorted { $0.lastActivity < $1.lastActivity }
        var previousDirectory: String?
        return ordered.reduce(into: 0) { count, session in
            if let previousDirectory, previousDirectory != session.directory { count += 1 }
            previousDirectory = session.directory
        }
    }
}

extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let standard = ISO8601DateFormatter()
}
