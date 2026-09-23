import Foundation
import Testing
@testable import NotchPilotCore

@Test func continuousPhrasePreservesMessage() {
    let commands = StreamingCommandParser().parse("Open WhatsApp, go to Mummy, type Hi there! and send")
    #expect(commands.map(\.kind) == [.openApp, .contact, .typeText, .send])
    #expect(commands[2].value == "Hi there!")
}
@Test func dictationIsOpaque() {
    let commands = StreamingCommandParser().parse("type open the door and then say hello")
    #expect(commands.count == 1)
    #expect(commands.first?.value == "open the door and then say hello")
    #expect(StreamingCommandParser().parse("type hi").map(\.kind) == [.typeText])
    #expect(StreamingCommandParser().parse("type please send it tomorrow").count == 1)
}
@Test func earlyOpenAndCommittedSend() {
    var machine = CommandStateMachine()
    let first = machine.ingest(text: "Open WhatsApp", committed: "", now: 1)
    #expect(first.stableEnd == 0)
    let partial = machine.ingest(text: "Open WhatsApp, go to Mummy", committed: "", now: 1.25)
    #expect(partial.commands[0].endOffset <= partial.stableEnd)
    let phrase = "Open WhatsApp, go to Mummy, type hi and send"
    _ = machine.ingest(text: phrase, committed: "", now: 1.5)
    let stillVolatile = machine.ingest(text: phrase, committed: "", now: 1.8)
    #expect(stillVolatile.commands.last!.endOffset > stillVolatile.committedEnd)
    let final = machine.ingest(text: phrase, committed: phrase, now: 2)
    #expect(final.commands.last!.endOffset <= final.committedEnd)
}
@Test func cancellationIsImmediate() throws {
    let token = CancellationToken(); token.update(revision: 2)
    try token.check(revision: 2)
    #expect(throws: PilotError.self) { try token.check(revision: 1) }
    token.cancel(); #expect(throws: PilotError.self) { try token.check() }
}
@Test func safetyPolicy() {
    #expect(SafetyPolicy().dryRun)
    #expect(SafetyPolicy().needsConfirmation("my password is secret"))
    #expect(SafetyPolicy().needsConfirmation("pay 100 tomorrow"))
    #expect(!SafetyPolicy().needsConfirmation("hi"))
}
actor MockAdapter: ApplicationAdapter {
    var commands: [Command] = []
    var delay: UInt64 = 0
    func execute(_ command: Command, token: CancellationToken, revision: Int, policy: SafetyPolicy) async throws -> String {
        if delay > 0 { try await Task.sleep(nanoseconds: delay) }
        try token.check(revision: revision)
        commands.append(command)
        return policy.dryRun && command.kind == .send ? "dryRun" : "success"
    }
    func reset() {}
    func setDelay(_ delay: UInt64) { self.delay = delay }
}
@Test func queueDoesNotDuplicateAndNeverReallySends() async throws {
    let adapter = MockAdapter(), token = CancellationToken()
    let queue = ActionQueue(adapter: adapter, token: token, policy: SafetyPolicy(), event: { _ in })
    var machine = CommandStateMachine()
    let text = "Open WhatsApp, go to Mummy, type hi and send"
    let batch = machine.ingest(text: text, committed: text, now: 1)
    await queue.submit(batch)
    try await Task.sleep(nanoseconds: 30_000_000)
    await queue.submit(batch)
    try await Task.sleep(nanoseconds: 30_000_000)
    #expect(await adapter.commands.map(\.kind) == [.openApp, .contact, .typeText, .send])
}
@Test func revisedDraftReplacesUncommittedSend() async throws {
    let adapter = MockAdapter(), token = CancellationToken()
    await adapter.setDelay(20_000_000)
    let queue = ActionQueue(adapter: adapter, token: token, policy: SafetyPolicy(), event: { _ in })
    var machine = CommandStateMachine()
    let first = "type hi and send"
    await queue.submit(machine.ingest(text: first, committed: first, now: 1))
    let next = "type hello"
    await queue.submit(machine.ingest(text: next, committed: next, now: 2))
    try await Task.sleep(nanoseconds: 100_000_000)
    #expect(await adapter.commands.contains(where: { $0.kind == .send }) == false)
    #expect(await adapter.commands.last?.value == "hello")
}
@Test func cancellationClearsQueue() async throws {
    let adapter = MockAdapter(), token = CancellationToken()
    await adapter.setDelay(30_000_000)
    let queue = ActionQueue(adapter: adapter, token: token, policy: SafetyPolicy(), event: { _ in })
    var machine = CommandStateMachine()
    let text = "Open WhatsApp, go to Mummy, type hi and send"
    await queue.submit(machine.ingest(text: text, committed: text, now: 1))
    token.cancel(); await queue.cancel()
    try await Task.sleep(nanoseconds: 60_000_000)
    #expect(await adapter.commands.isEmpty)
}
@Test func exactContactsAndAliases() throws {
    #expect(ContactResolver.resolve("Mummy", aliases: ["mummy": "Test Contact"]) == "Test Contact")
    #expect(try ContactResolver.exactIndex(target: "Mummy", candidates: ["Mummy Work", "\u{200e}Mummy"]) == 1)
    #expect(throws: PilotError.self) { try ContactResolver.exactIndex(target: "Mummy", candidates: ["Mummy", "MUMMY"]) }
    #expect(throws: PilotError.self) { try ContactResolver.exactIndex(target: "Mummy", candidates: []) }
}
