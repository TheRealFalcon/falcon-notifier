import Foundation

private struct RPCError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// An observer only. Never resumes threads, subscribes to turns, or answers approvals.
@MainActor
public final class CodexSource: StatusSource {
    public var onChange: ((Indicator) -> Void)?
    private let url: URL
    private let session: URLSession
    private var socket: URLSessionWebSocketTask?
    private var runner: Task<Void, Never>?
    private var receiver: Task<Void, Never>?
    private var pollDelay: Task<Void, Error>?
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var nextID = 0
    private var state = CodexState()
    private var lastIndicator: Indicator?
    private var hasSnapshot = false

    public init(url: URL) {
        self.url = url
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        session = URLSession(configuration: configuration)
    }

    public func start() {
        guard runner == nil else { return }
        runner = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await connect()
                    while !Task.isCancelled {
                        try await refresh()
                        guard socket != nil else { throw RPCError(message: "Disconnected") }
                        let delay = Task { try await Task.sleep(for: .seconds(30)) }
                        pollDelay = delay
                        try await delay.value
                        pollDelay = nil
                    }
                } catch {
                    if Task.isCancelled { break }
                    disconnect(error)
                    publish(Indicator(level: .unavailable,
                                      summary: "Codex unavailable: \(error.localizedDescription)"))
                    do { try await Task.sleep(for: .seconds(5)) } catch { break }
                }
            }
        }
    }

    public func stop() {
        runner?.cancel()
        runner = nil
        disconnect(CancellationError())
        lastIndicator = nil
    }

    private func connect() async throws {
        state = CodexState()
        hasSnapshot = false
        let connection = session.webSocketTask(with: url)
        connection.maximumMessageSize = 16 * 1024 * 1024
        socket = connection
        connection.resume()
        receiver = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    let message = try await connection.receive()
                    guard let self, self.socket === connection else { return }
                    let data: Data
                    switch message {
                    case .string(let text): data = Data(text.utf8)
                    case .data(let bytes): data = bytes
                    @unknown default: continue
                    }
                    try self.receive(data)
                }
            } catch {
                guard let self, self.socket === connection else { return }
                self.disconnect(error)
                self.publish(Indicator(level: .unavailable,
                                       summary: "Codex unavailable: \(error.localizedDescription)"))
            }
        }
        _ = try await request("initialize", params: [
            "clientInfo": ["name": "falcon-notifier", "title": "falcon-notifier", "version": "0.1.0"],
            "capabilities": ["experimentalApi": true],
        ])
        try Task.checkCancellation()
        try await send(["method": "initialized", "params": [:]])
    }

    private struct LoadedPage: Decodable {
        let data: [String]
        let nextCursor: String?
    }

    private struct ThreadResult: Decodable {
        struct Thread: Decodable { let status: ThreadStatus }
        let thread: Thread
    }

    private func refresh() async throws {
        state.beginSnapshot()
        var snapshot: [String: ThreadStatus] = [:]
        var cursor: String?
        var seenCursors = Set<String>()
        repeat {
            var params: [String: Any] = ["limit": 100]
            if let cursor { params["cursor"] = cursor }
            let page = try JSONDecoder().decode(LoadedPage.self,
                from: await request("thread/loaded/list", params: params))
            for id in page.data {
                let result = try JSONDecoder().decode(ThreadResult.self,
                    from: await request("thread/read", params: ["threadId": id, "includeTurns": false]))
                snapshot[id] = result.thread.status
            }
            cursor = page.nextCursor
            if let cursor, !seenCursors.insert(cursor).inserted {
                throw RPCError(message: "Repeated pagination cursor")
            }
        } while cursor != nil
        state.completeSnapshot(snapshot)
        hasSnapshot = true
        publish(state.indicator)
    }

    private func receive(_ data: Data) throws {
        guard let message = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RPCError(message: "Invalid server message")
        }
        // Server-initiated requests belong to the controlling Codex client. Ignore them.
        if message["method"] == nil, let id = message["id"] as? Int,
           let continuation = pending.removeValue(forKey: id) {
            if let error = message["error"] as? [String: Any] {
                continuation.resume(throwing: RPCError(message: error["message"] as? String ?? "RPC failed"))
            } else {
                do {
                    let result = try JSONSerialization.data(withJSONObject: message["result"] ?? NSNull(),
                                                            options: [.fragmentsAllowed])
                    continuation.resume(returning: result)
                } catch { continuation.resume(throwing: error) }
            }
            return
        }
        guard message["id"] == nil,
              let method = message["method"] as? String,
              let params = message["params"] as? [String: Any],
              let id = params["threadId"] as? String else { return }
        if method == "thread/status/changed", let status = params["status"] {
            let statusData = try JSONSerialization.data(withJSONObject: status)
            state.update(id: id, status: try JSONDecoder().decode(ThreadStatus.self, from: statusData))
        } else if ["thread/closed", "thread/archived", "thread/deleted"].contains(method) {
            state.update(id: id, status: ThreadStatus(type: "notLoaded"))
        } else { return }
        if hasSnapshot { publish(state.indicator) }
    }

    private func request(_ method: String, params: [String: Any]) async throws -> Data {
        try Task.checkCancellation()
        guard let socket else { throw RPCError(message: "Disconnected") }
        nextID += 1
        let id = nextID
        let data = try JSONSerialization.data(withJSONObject: ["id": id, "method": method, "params": params])
        let timeout = Task {
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            pending.removeValue(forKey: id)?.resume(throwing: RPCError(message: "\(method) timed out"))
        }
        defer { timeout.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            Task {
                do { try await socket.send(.string(String(decoding: data, as: UTF8.self))) }
                catch { pending.removeValue(forKey: id)?.resume(throwing: error) }
            }
        }
    }

    private func send(_ message: [String: Any]) async throws {
        guard let socket else { throw RPCError(message: "Disconnected") }
        let data = try JSONSerialization.data(withJSONObject: message)
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }

    private func disconnect(_ error: Error) {
        pollDelay?.cancel()
        pollDelay = nil
        receiver?.cancel()
        receiver = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        hasSnapshot = false
        let requests = pending
        pending.removeAll()
        for continuation in requests.values { continuation.resume(throwing: error) }
    }

    private func publish(_ indicator: Indicator) {
        guard indicator != lastIndicator else { return }
        lastIndicator = indicator
        onChange?(indicator)
    }
}
