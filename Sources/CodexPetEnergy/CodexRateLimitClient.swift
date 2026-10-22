import Foundation

final class CodexRateLimitClient {
    var onSnapshot: ((RateLimitReadResult) -> Void)?
    var onUnavailable: (() -> Void)?

    private let ioQueue = DispatchQueue(label: "codex.pet.energy.rpc")
    private let executableOverride: URL?
    private let timeoutInterval: TimeInterval

    init(executable: URL? = nil, timeoutInterval: TimeInterval = 12) {
        self.executableOverride = executable
        self.timeoutInterval = timeoutInterval
    }
    private var process: Process?
    private var input: FileHandle?
    private var outputBuffer = Data()
    private var refreshTimer: DispatchSourceTimer?
    private var reconnectWorkItem: DispatchWorkItem?
    private var snapshotTimeout: DispatchWorkItem?
    private var initializationTimeout: DispatchWorkItem?
    private var nextRequestID = 2
    private var pendingRequestID: Int?
    private var latestSnapshot: RateLimitReadResult?
    private var stopped = false
    private var reconnectAttempt = 0
    private var snapshotRequestPending = false

    func start() {
        ioQueue.async { [weak self] in
            self?.stopped = false
            self?.connect()
        }
    }

    func stop() {
        ioQueue.async { [weak self] in
            guard let self else { return }
            self.stopped = true
            self.reconnectWorkItem?.cancel()
            self.refreshTimer?.cancel()
            self.process?.terminate()
            self.cleanupProcess()
        }
    }

    func refresh() {
        ioQueue.async { [weak self] in
            guard let self else { return }
            if self.process == nil {
                self.connect()
            } else {
                self.requestSnapshot()
            }
        }
    }

    private func connect() {
        guard !stopped, process == nil else { return }
        guard let executable = executableOverride ?? Self.findCodexExecutable() else {
            publishUnavailable()
            scheduleReconnect()
            return
        }

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        self.process = process
        input = stdinPipe.fileHandleForWriting
        outputBuffer.removeAll(keepingCapacity: true)

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.ioQueue.async { self?.consume(data) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        process.terminationHandler = { [weak self] _ in
            self?.ioQueue.async {
                guard let self, !self.stopped else { return }
                self.cleanupProcess()
                self.publishUnavailable()
                self.scheduleReconnect()
            }
        }

        do {
            try process.run()
            let timeout = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.process?.terminate()
                self.publishUnavailable()
            }
            initializationTimeout = timeout
            ioQueue.asyncAfter(deadline: .now() + timeoutInterval, execute: timeout)
            send([
                "method": "initialize",
                "id": 1,
                "params": [
                    "clientInfo": [
                        "name": "codex-pet-energy",
                        "title": "Codex 算力条",
                        "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.0",
                    ],
                    "capabilities": [
                        "experimentalApi": false,
                        "requestAttestation": false,
                    ],
                ],
            ])
        } catch {
            cleanupProcess()
            publishUnavailable()
            scheduleReconnect()
        }
    }

    private func consume(_ data: Data) {
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer[..<newline]
            outputBuffer.removeSubrange(...newline)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
            else { continue }
            handle(object)
        }
    }

    private func handle(_ message: [String: Any]) {
        if (message["id"] as? Int) == 1 {
            initializationTimeout?.cancel()
            initializationTimeout = nil
            guard message["error"] == nil else {
                process?.terminate()
                publishUnavailable()
                return
            }
            send(["method": "initialized"])
            requestSnapshot()
            startRefreshTimer()
            return
        }

        if (message["id"] as? Int) == pendingRequestID && pendingRequestID != nil,
           let result = message["result"],
           let decoded: RateLimitReadResult = decode(result) {
            snapshotRequestPending = false
            snapshotTimeout?.cancel()
            snapshotTimeout = nil
            reconnectAttempt = 0
            latestSnapshot = decoded
            publish(decoded)
            return
        }

        if (message["method"] as? String) == "account/rateLimits/updated",
           let params = message["params"] as? [String: Any],
           let snapshotObject = params["rateLimits"],
           let snapshot: RateLimitSnapshot = decode(snapshotObject) {
            let merged = latestSnapshot.map { EnergyLogic.mergingSparseUpdate(snapshot, into: $0) }
                ?? RateLimitReadResult(rateLimits: snapshot, rateLimitsByLimitId: [snapshot.limitId ?? "default": snapshot])
            latestSnapshot = merged
            publish(merged)
            return
        }

        if (message["id"] as? Int) == pendingRequestID && pendingRequestID != nil, message["error"] != nil {
            snapshotRequestPending = false
            snapshotTimeout?.cancel()
            snapshotTimeout = nil
            publishUnavailable()
        }
    }

    private func requestSnapshot() {
        guard !snapshotRequestPending, input != nil else { return }
        snapshotRequestPending = true
        pendingRequestID = nextRequestID
        nextRequestID += 1
        snapshotTimeout?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.snapshotRequestPending = false
            self.publishUnavailable()
        }
        snapshotTimeout = timeout
        ioQueue.asyncAfter(deadline: .now() + timeoutInterval, execute: timeout)
        send(["method": "account/rateLimits/read", "id": pendingRequestID!])
    }

    private func startRefreshTimer() {
        refreshTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: ioQueue)
        timer.schedule(deadline: .now() + 60, repeating: 60)
        timer.setEventHandler { [weak self] in self?.requestSnapshot() }
        timer.resume()
        refreshTimer = timer
    }

    private func send(_ object: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let input
        else { return }
        var line = data
        line.append(0x0A)
        do {
            try input.write(contentsOf: line)
        } catch {
            snapshotRequestPending = false
            snapshotTimeout?.cancel()
            snapshotTimeout = nil
            publishUnavailable()
        }
    }

    private func decode<T: Decodable>(_ object: Any) -> T? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object)
        else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func publish(_ snapshot: RateLimitReadResult) {
        DispatchQueue.main.async { [weak self] in self?.onSnapshot?(snapshot) }
    }

    private func publishUnavailable() {
        DispatchQueue.main.async { [weak self] in self?.onUnavailable?() }
    }

    private func scheduleReconnect() {
        guard !stopped else { return }
        reconnectAttempt += 1
        let delays: [TimeInterval] = [2, 5, 15, 30]
        let delay = delays[min(reconnectAttempt - 1, delays.count - 1)]
        let item = DispatchWorkItem { [weak self] in self?.connect() }
        reconnectWorkItem = item
        ioQueue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func cleanupProcess() {
        initializationTimeout?.cancel()
        initializationTimeout = nil
        pendingRequestID = nil
        refreshTimer?.cancel()
        refreshTimer = nil
        snapshotTimeout?.cancel()
        snapshotTimeout = nil
        snapshotRequestPending = false
        input = nil
        process = nil
        outputBuffer.removeAll(keepingCapacity: true)
    }

    static func findCodexExecutable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex"),
            URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
            home.appendingPathComponent(".codex/packages/standalone/current/codex"),
            home.appendingPathComponent(".local/bin/codex"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
