import Darwin
import Foundation

/// One bounded request per same-user Unix connection. Never accepts network traffic.
final class LocalControlServer {
    private var descriptor: Int32 = -1
    private static var directory: String {
        FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Caches/CodexPetEnergy/control"
    }
    private static var path: String { directory + "/app.sock" }

    @MainActor func start(handler: @escaping @MainActor (EnergyCLIRequest) -> [String: Any]) throws {
        try FileManager.default.createDirectory(atPath: Self.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard lstat(Self.directory, &info) == 0, info.st_uid == getuid(), (info.st_mode & S_IFMT) == S_IFDIR else {
            throw CLIError.message("CLI 目录所有者或类型不正确")
        }
        chmod(Self.directory, 0o700)
        // A second instance must never steal a live app's socket.
        let probe = try Self.makeSocket()
        if Self.address({ connect(probe, $0, $1) }) == 0 {
            close(probe)
            throw CLIError.message("CLI 已由另一个应用实例提供")
        }
        close(probe)
        unlink(Self.path)
        let fd = try Self.makeSocket()
        guard Self.address({ bind(fd, $0, $1) }) == 0 else { close(fd); throw CLIError.message("无法绑定本地 CLI") }
        chmod(Self.path, 0o600)
        guard listen(fd, 8) == 0 else { close(fd); unlink(Self.path); throw CLIError.message("无法启动本地 CLI") }
        descriptor = fd
        DispatchQueue.global(qos: .utility).async {
            while true {
                let client = accept(fd, nil, nil)
                if client < 0 { break }
                var uid: uid_t = 0
                var gid: gid_t = 0
                guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else { close(client); continue }
                Self.configure(client)
                defer { close(client) }
                do {
                    let request = try JSONDecoder().decode(EnergyCLIRequest.self, from: Self.readLine(client)).validated()
                    let result = DispatchQueue.main.sync { MainActor.assumeIsolated { handler(request) } }
                    try Self.writeLine(client, data: JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]))
                } catch {
                    let data = try? JSONSerialization.data(withJSONObject: ["ok": false, "error": String(describing: error)])
                    if let data { try? Self.writeLine(client, data: data) }
                }
            }
        }
    }

    func stop() {
        if descriptor >= 0 {
            shutdown(descriptor, SHUT_RDWR)
            close(descriptor)
            descriptor = -1
            unlink(Self.path)
        }
    }

    static func call(_ request: EnergyCLIRequest) throws -> Data {
        let fd = try makeSocket()
        defer { close(fd) }
        guard address({ connect(fd, $0, $1) }) == 0 else {
            throw CLIError.message("算力环未运行或 CLI 不可用，请先启动已安装应用")
        }
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else { throw CLIError.message("CLI 服务用户不匹配") }
        try writeLine(fd, data: JSONEncoder().encode(request))
        return try readLine(fd)
    }

    private static func makeSocket() throws -> Int32 {
        guard path.utf8.count < 104 else { throw CLIError.message("本地 CLI 路径过长") }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw CLIError.message("无法创建本地 socket") }
        configure(fd)
        return fd
    }

    private static func configure(_ fd: Int32) {
        var noSignal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout.size(ofValue: noSignal)))
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
    }

    private static func address(_ operation: (UnsafePointer<sockaddr>, socklen_t) -> Int32) -> Int32 {
        var value = sockaddr_un()
        value.sun_family = sa_family_t(AF_UNIX)
        value.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutablePointer(to: &value.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 104) { _ = strlcpy($0, path, 104) }
        }
        return withUnsafePointer(to: &value) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { operation($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
    }

    private static func readLine(_ fd: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count < 65536 {
            let count = read(fd, &buffer, buffer.count)
            guard count > 0 else { throw CLIError.message("CLI 响应超时或连接关闭") }
            data.append(contentsOf: buffer.prefix(count))
            if let newline = data.firstIndex(of: 10) { return data.prefix(upTo: newline) }
        }
        throw CLIError.message("CLI 请求过大")
    }

    private static func writeLine(_ fd: Int32, data: Data) throws {
        let payload = data + Data([10])
        try payload.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                guard written > 0 else { throw CLIError.message("CLI 发送失败") }
                offset += written
            }
        }
    }
}
