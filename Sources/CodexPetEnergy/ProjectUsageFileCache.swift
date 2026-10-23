import Foundation
import Darwin

struct ProjectUsageFileSnapshot: Equatable {
    let device: Int32
    let inode: UInt64
    let size: Int
    let modifiedSeconds: Int
    let modifiedNanos: Int
    let changedSeconds: Int
    let changedNanos: Int

    var modified: Date {
        Date(timeIntervalSince1970: Double(modifiedSeconds) + Double(modifiedNanos) / 1_000_000_000)
    }

    func hasSameIdentity(as other: Self) -> Bool {
        device == other.device && inode == other.inode
    }

    static func read(_ file: URL) -> Self? {
        var status = stat()
        guard file.path.withCString({ fstatat(AT_FDCWD, $0, &status, 0) }) == 0,
              (status.st_mode & S_IFMT) == S_IFREG,
              status.st_size >= 0, status.st_size <= Int.max else { return nil }
        return Self(device: status.st_dev, inode: status.st_ino, size: Int(status.st_size),
                    modifiedSeconds: status.st_mtimespec.tv_sec, modifiedNanos: status.st_mtimespec.tv_nsec,
                    changedSeconds: status.st_ctimespec.tv_sec, changedNanos: status.st_ctimespec.tv_nsec)
    }
}

struct ProjectUsageFileCache {
    var snapshot: ProjectUsageFileSnapshot?
    var accumulator: ProjectUsageSessionAccumulator
    var bytesRead: UInt64 = 0
    var pendingLine = Data()
    // Small boundary samples validate an append without rereading the old log.
    var prefix = Data()
    var suffix = Data()
    var succeeded = false

    init(fallbackID: String) {
        accumulator = ProjectUsageSessionAccumulator(fallbackID: fallbackID)
    }

    var session: ProjectUsageSession? { accumulator.makeSession() }
}
