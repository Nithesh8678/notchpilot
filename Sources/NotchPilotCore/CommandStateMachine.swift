import Foundation

public struct CommandBatch: Sendable {
    public let revision: Int
    public let commands: [Command]
    public let stableEnd: Int
    public let committedEnd: Int
}
public struct CommandStateMachine: Sendable {
    private var stability = TranscriptStability()
    private var previous = ""
    public private(set) var revision = 0
    public private(set) var cancelled = false
    public init() {}
    public mutating func ingest(text: String, committed: String, now: TimeInterval) -> CommandBatch {
        if text != previous { revision += 1; previous = text }
        let stable = stability.update(text: text, committed: committed, now: now)
        let commands = StreamingCommandParser().parse(text)
        if commands.contains(where: { $0.kind == .cancel && $0.endOffset <= stable }) { cancelled = true }
        return CommandBatch(revision: revision, commands: cancelled ? [] : commands, stableEnd: stable, committedEnd: (committed as NSString).length)
    }
    public mutating func cancel() { cancelled = true; revision += 1 }
}

/// Synchronous cancellation remains available while a worker is awaiting an AX reply.
public final class CancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var revision = 0
    public init() {}
    public func update(revision: Int) { lock.lock(); self.revision = revision; lock.unlock() }
    public func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    public func check(revision expected: Int? = nil) throws {
        lock.lock(); defer { lock.unlock() }
        if cancelled || (expected != nil && revision != expected) { throw PilotError.cancelled }
    }
}
public struct SafetyPolicy: Sendable {
    public var dryRun: Bool
    public var confirmAll: Bool
    public init(dryRun: Bool = true, confirmAll: Bool = false) { self.dryRun = dryRun; self.confirmAll = confirmAll }
    public func needsConfirmation(_ message: String) -> Bool {
        if confirmAll { return true }
        let text = TextNormalization.identity(message)
        let risks = ["password", "passcode", "otp", "verification code", "bank", "account number", "transfer", "pay", "payment", "purchase", "buy", "delete", "security", "passport", "aadhaar", "identity", "credit card", "pin", "public", "post", "money"]
        return risks.contains { text.range(of: #"\b"# + NSRegularExpression.escapedPattern(for: $0) + #"\b"#, options: .regularExpression) != nil } || text.range(of: #"\b\d{4,}\b"#, options: .regularExpression) != nil
    }
}
public protocol ApplicationAdapter: Sendable {
    func execute(_ command: Command, token: CancellationToken, revision: Int, policy: SafetyPolicy) async throws -> String
    func reset() async
}
public struct ExecutionEvent: Sendable {
    public let kind: CommandKind
    public let status: String
    public let milliseconds: Double
    public init(kind: CommandKind, status: String, milliseconds: Double) { self.kind = kind; self.status = status; self.milliseconds = milliseconds }
}
public actor ActionQueue {
    private let adapter: any ApplicationAdapter
    private let token: CancellationToken
    private let policy: SafetyPolicy
    private let event: @Sendable (ExecutionEvent) -> Void
    private var pending: [Command] = []
    private var revision = 0
    private var completed: [Int: Command] = [:]
    private var worker: Task<Void, Never>?
    private var failed = false
    private var approvedRevision: Int?
    public init(adapter: any ApplicationAdapter, token: CancellationToken, policy: SafetyPolicy, event: @escaping @Sendable (ExecutionEvent) -> Void) {
        self.adapter = adapter; self.token = token; self.policy = policy; self.event = event
    }
    public func submit(_ batch: CommandBatch) {
        guard !failed else { return }
        revision = batch.revision
        token.update(revision: revision)
        // Revisions of already committed recipients are unsafe. Require a fresh session.
        for old in completed.values where old.kind != .typeText {
            if batch.commands.first(where: { $0.id == old.id }) != old {
                cancel(); event(.init(kind: old.kind, status: "error: Speech changed an executed command. Start again.", milliseconds: 0)); return
            }
        }
        pending = batch.commands.filter { command in
            guard command.endOffset <= batch.stableEnd else { return false }
            if command.kind == .send && command.endOffset > batch.committedEnd { return false }
            if let old = completed[command.id], old == command { return false }
            return true
        }
        if worker == nil { worker = Task { await drain() } }
    }
    public func confirm() { approvedRevision = revision; if worker == nil { worker = Task { await drain() } } }
    public func cancel() { token.cancel(); pending = []; worker?.cancel(); worker = nil; failed = true }
    private func drain() async {
        defer { worker = nil }
        while !pending.isEmpty, !failed, !Task.isCancelled {
            let command = pending.removeFirst(), currentRevision = revision
            do {
                try token.check(revision: currentRevision)
                if command.kind == .send {
                    let message = completed.values.first(where: { $0.kind == .typeText })?.value ?? ""
                    guard !message.isEmpty else { throw PilotError.unsafe("Dictate a message before sending.") }
                    if !policy.dryRun && policy.needsConfirmation(message) && approvedRevision != currentRevision {
                        pending.insert(command, at: 0)
                        event(.init(kind: .send, status: "confirmation", milliseconds: 0)); return
                    }
                }
                event(.init(kind: command.kind, status: "executing", milliseconds: 0))
                let start = ContinuousClock.now
                let result = try await adapter.execute(command, token: token, revision: currentRevision, policy: policy)
                let duration = start.duration(to: .now)
                let milliseconds = Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
                completed[command.id] = command
                // An in-flight command may have been included in a replacement batch.
                pending.removeAll { $0 == command }
                event(.init(kind: command.kind, status: result, milliseconds: milliseconds))
            } catch PilotError.cancelled {
                // Obsolete work is discarded; the revised batch can proceed.
                if (try? token.check()) == nil { failed = true; pending = [] }
            } catch {
                failed = true; pending = []
                event(.init(kind: command.kind, status: "error: " + error.localizedDescription, milliseconds: 0))
            }
        }
    }
}
