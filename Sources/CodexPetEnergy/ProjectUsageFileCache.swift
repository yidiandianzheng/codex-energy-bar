import Foundation

struct ProjectUsageFileCache {
    var modified: Date
    var size: Int
    var accumulator: ProjectUsageSessionAccumulator
    var bytesRead: UInt64
    var pendingLine: Data

    init(fallbackID: String, modified: Date, size: Int) {
        self.modified = modified
        self.size = size
        accumulator = ProjectUsageSessionAccumulator(fallbackID: fallbackID)
        bytesRead = 0
        pendingLine = Data()
    }

    var session: ProjectUsageSession? {
        accumulator.makeSession()
    }
}
