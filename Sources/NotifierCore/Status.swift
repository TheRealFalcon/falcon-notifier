import Foundation

/// The presentation boundary: future sources can supply their own symbol and summary.
public struct Indicator: Equatable, Sendable, Codable {
    public enum Level: String, Sendable, Codable {
        case ready, busy, attention, unavailable
    }

    public var level: Level
    public var summary: String
    public var symbol: String

    public init(level: Level, summary: String, symbol: String = "circle.fill") {
        self.level = level
        self.summary = summary
        self.symbol = symbol
    }
}

@MainActor
public protocol StatusSource: AnyObject {
    var onChange: ((Indicator) -> Void)? { get set }
    func start()
    func stop()
}

struct ThreadStatus: Decodable, Equatable {
    var type: String
    var activeFlags: [String]?

    var waiting: Bool {
        type == "active" && (activeFlags ?? []).contains {
            $0 == "waitingOnApproval" || $0 == "waitingOnUserInput"
        }
    }
}

/// Polls reconcile the full set; notifications win over any snapshot already in flight.
struct CodexState {
    private(set) var statuses: [String: ThreadStatus] = [:]
    private var snapshotChanges: [String: ThreadStatus]?

    mutating func beginSnapshot() {
        snapshotChanges = [:]
    }

    mutating func update(id: String, status: ThreadStatus) {
        statuses[id] = status.type == "notLoaded" ? nil : status
        snapshotChanges?[id] = status
    }

    mutating func completeSnapshot(_ snapshot: [String: ThreadStatus]) {
        var merged = snapshot
        for (id, status) in snapshotChanges ?? [:] { merged[id] = status }
        statuses = merged.filter { $0.value.type != "notLoaded" }
        snapshotChanges = nil
    }

    var indicator: Indicator {
        let waiting = statuses.values.filter(\.waiting).count
        let working = statuses.values.filter { $0.type == "active" && !$0.waiting }.count
        let errors = statuses.values.filter { $0.type == "systemError" }.count
        let idle = statuses.count - waiting - working - errors
        let summary = statuses.isEmpty
            ? "Codex: no loaded sessions"
            : "Codex: \(waiting) waiting · \(working) working · \(idle) idle"
                + (errors > 0 ? " · \(errors) errored" : "")
        return Indicator(level: waiting > 0 ? .attention : working > 0 ? .busy : .ready,
                         summary: summary)
    }
}
