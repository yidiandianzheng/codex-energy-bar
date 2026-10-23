import Foundation

final class ProjectUsageMonitor {
    var onUpdate: ((ProjectUsageDaySummary) -> Void)?
    var onFailure: (() -> Void)?
    private var scanFailed = false

    private let queue = DispatchQueue(label: "codex.pet.energy.project-usage", qos: .utility)
    private let roots: [URL]
    private let fileManager: FileManager
    private let fileReadObserver: ((URL, UInt64, Int) -> Void)?
    private var timer: DispatchSourceTimer?
    private var cachedSessions: [String: ProjectUsageFileCache] = [:]
    private var cachedDayStart: Date?

    init(roots: [URL] = ProjectUsageMonitor.defaultRoots, fileManager: FileManager = .default,
         fileReadObserver: ((URL, UInt64, Int) -> Void)? = nil) {
        self.roots = roots.map { $0.resolvingSymlinksInPath() }
        self.fileManager = fileManager
        self.fileReadObserver = fileReadObserver
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
        let summary = readTodayUsingCache(now: Date(), force: force)
        let failed = scanFailed
        DispatchQueue.main.async { [weak self] in
            if failed { self?.onFailure?() } else { self?.onUpdate?(summary) }
        }
    }

    // Queue-confined in production; synchronous access permits isolated fixture
    // tests without starting a timer, main run loop, or reading the default roots.
    func readTodayUsingCache(now: Date, force: Bool = false) -> ProjectUsageDaySummary {
        scanFailed = false
        let start = ProjectUsageLogic.startOfDay(containing: now)
        if force || cachedDayStart != start {
            cachedDayStart = start
            cachedSessions.removeAll()
        }
        var visited: Set<String> = []
        var uniqueSessions: [String: ProjectUsageSession] = [:]
        for unresolvedRoot in roots {
            let root = unresolvedRoot.resolvingSymlinksInPath()
            guard fileManager.fileExists(atPath: root.path) else { continue }
            guard let enumerator = fileManager.enumerator(
                at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles],
                errorHandler: { [weak self] _, _ in self?.scanFailed = true; return true }
            ) else { scanFailed = true; continue }

            for case let file as URL in enumerator {
                guard file.pathExtension == "jsonl" else { continue }
                guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey]) else {
                    scanFailed = true
                    continue
                }
                guard values.isRegularFile == true else { continue }
                guard let snapshot = ProjectUsageFileSnapshot.read(file) else {
                    scanFailed = true
                    continue
                }
                // Old sessions can contain today's appended events. Their mtime
                // advances on append; unchanged historical files need no parsing.
                guard snapshot.modified >= start else { continue }
                let key = file.path
                guard visited.insert(key).inserted else { continue }
                let cached = cachedSessions[key]
                let updated: ProjectUsageFileCache
                if let cached, cached.succeeded, cached.snapshot == snapshot {
                    updated = cached
                } else {
                    updated = Self.readSessionFile(file, snapshot: snapshot, cached: cached,
                                                   now: now, observer: fileReadObserver)
                    cachedSessions[key] = updated
                }
                if !updated.succeeded { scanFailed = true }
                guard let session = updated.session else { continue }
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
        cachedSessions = cachedSessions.filter { visited.contains($0.key) }
        let sessions = Array(uniqueSessions.values)
        return ProjectUsageDaySummary(projects: ProjectUsageLogic.aggregate(sessions),
                                      sessionSwitchCount: ProjectUsageLogic.sessionSwitchCount(sessions))
    }

    static var defaultRoots: [URL] {
        let codex = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        return [codex.appendingPathComponent("sessions"), codex.appendingPathComponent("archived_sessions")]
    }

    static func readToday(from roots: [URL], now: Date, fileManager: FileManager = .default) -> ProjectUsageDaySummary {
        let monitor = ProjectUsageMonitor(roots: roots, fileManager: fileManager)
        return monitor.readTodayUsingCache(now: now, force: true)
    }

    static func parseSession(_ text: String, fallbackID: String, now: Date) -> ProjectUsageSession? {
        let start = ProjectUsageLogic.startOfDay(containing: now)
        var accumulator = ProjectUsageSessionAccumulator(fallbackID: fallbackID)
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8) else { continue }
            accumulator.consume(data, startOfDay: start)
        }
        return accumulator.makeSession()
    }

    private static func readSessionFile(
        _ file: URL, snapshot: ProjectUsageFileSnapshot, cached: ProjectUsageFileCache?,
        now: Date, observer: ((URL, UInt64, Int) -> Void)?
    ) -> ProjectUsageFileCache {
        var empty = ProjectUsageFileCache(fallbackID: file.path)
        guard let handle = try? FileHandle(forReadingFrom: file) else { return empty }
        defer { try? handle.close() }
        do {
            var canContinue = false
            if let cached, cached.succeeded, let old = cached.snapshot,
               snapshot.hasSameIdentity(as: old), snapshot.size > old.size,
               cached.bytesRead == UInt64(old.size) {
                // Check both old boundaries, including the pending partial line.
                // The main read still starts exactly at the old byte offset.
                let prefix = try handle.read(upToCount: cached.prefix.count) ?? Data()
                try handle.seek(toOffset: cached.bytesRead - UInt64(cached.suffix.count))
                let suffix = try handle.read(upToCount: cached.suffix.count) ?? Data()
                canContinue = prefix == cached.prefix && suffix == cached.suffix
            }
            var result = canContinue ? cached! : empty
            let offset = result.bytesRead
            try handle.seek(toOffset: offset)
            let data = try handle.read(upToCount: snapshot.size - Int(offset)) ?? Data()
            observer?(file, offset, data.count)
            guard data.count == snapshot.size - Int(offset) else { return empty }
            var buffer = result.pendingLine
            buffer.append(data)
            result.pendingLine = result.accumulator.consumeCompleteJSONLines(
                in: buffer, startOfDay: ProjectUsageLogic.startOfDay(containing: now),
                includesSessionMetadata: true
            )
            result.bytesRead = UInt64(snapshot.size)
            let sampleCount = min(snapshot.size, 4096)
            try handle.seek(toOffset: 0)
            result.prefix = try handle.read(upToCount: sampleCount) ?? Data()
            try handle.seek(toOffset: UInt64(snapshot.size - sampleCount))
            result.suffix = try handle.read(upToCount: sampleCount) ?? Data()
            // If the file changed during reading, retry next scan rather than
            // publishing a mixture of two file versions or caching a torn read.
            guard ProjectUsageFileSnapshot.read(file) == snapshot else { return empty }
            result.snapshot = snapshot
            result.succeeded = true
            return result
        } catch {
            empty.succeeded = false
            return empty
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
        projects.reduce(.zero) { ProjectUsageMath.adding($0, $1.totals) }
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
                    totals: ProjectUsageMath.adding(existing.totals, session.totals),
                    lastActivity: max(existing.lastActivity, session.lastActivity)
                )
            } else {
                grouped[session.directory] = ProjectUsageReading(
                    directory: session.directory,
                    projectName: name.isEmpty ? session.directory : name,
                    totals: ProjectUsageMath.adding(.zero, session.totals),
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
