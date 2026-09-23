import Foundation
import Testing

@testable import NotchPilotCore

@Test func continuousPhrasePreservesMessage() {
  let commands = StreamingCommandParser().parse(
    "Open WhatsApp, go to Mummy, type Hi there! and send")
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
  let token = CancellationToken()
  token.update(revision: 2)
  try token.check(revision: 2)
  #expect(throws: PilotError.self) { try token.check(revision: 1) }
  token.cancel()
  #expect(throws: PilotError.self) { try token.check() }
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
  func execute(_ command: Command, token: CancellationToken, revision: Int, policy: SafetyPolicy)
    async throws -> String
  {
    if delay > 0 { try await Task.sleep(nanoseconds: delay) }
    try token.check(revision: revision)
    commands.append(command)
    return policy.dryRun && command.kind == .send ? "dryRun" : "success"
  }
  func reset() {}
  func setDelay(_ delay: UInt64) { self.delay = delay }
}
@Test func queueDoesNotDuplicateAndNeverReallySends() async throws {
  let adapter = MockAdapter()
  let token = CancellationToken()
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
  let adapter = MockAdapter()
  let token = CancellationToken()
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
  let adapter = MockAdapter()
  let token = CancellationToken()
  await adapter.setDelay(30_000_000)
  let queue = ActionQueue(adapter: adapter, token: token, policy: SafetyPolicy(), event: { _ in })
  var machine = CommandStateMachine()
  let text = "Open WhatsApp, go to Mummy, type hi and send"
  await queue.submit(machine.ingest(text: text, committed: text, now: 1))
  token.cancel()
  await queue.cancel()
  try await Task.sleep(nanoseconds: 60_000_000)
  #expect(await adapter.commands.isEmpty)
}
@Test func exactContactsAndAliases() throws {
  #expect(ContactResolver.resolve("Mummy", aliases: ["mummy": "Test Contact"]) == "Test Contact")
  #expect(
    try ContactResolver.exactIndex(target: "Mummy", candidates: ["Mummy Work", "\u{200e}Mummy"])
      == 1)
  #expect(throws: PilotError.self) {
    try ContactResolver.exactIndex(target: "Mummy", candidates: ["Mummy", "MUMMY"])
  }
  #expect(throws: PilotError.self) {
    try ContactResolver.exactIndex(target: "Mummy", candidates: [])
  }
}

actor RejectingContactAdapter: ApplicationAdapter {
  var kinds: [CommandKind] = []
  func execute(_ command: Command, token: CancellationToken, revision: Int, policy: SafetyPolicy)
    async throws -> String
  {
    try token.check(revision: revision)
    kinds.append(command.kind)
    if command.kind == .contact { throw PilotError.unsafe("Multiple conversations match.") }
    return "success"
  }
  func reset() {}
}
@Test func ambiguousContactPreventsTypingAndSending() async throws {
  let adapter = RejectingContactAdapter()
  let queue = ActionQueue(
    adapter: adapter, token: CancellationToken(), policy: SafetyPolicy(), event: { _ in })
  var machine = CommandStateMachine()
  let text = "Open WhatsApp, go to Test Contact, type synthetic text and send"
  await queue.submit(machine.ingest(text: text, committed: text, now: 1))
  try await Task.sleep(nanoseconds: 30_000_000)
  #expect(await adapter.kinds == [.openApp, .contact])
}
@Test func volatileSendCannotRun() async throws {
  let adapter = MockAdapter()
  let queue = ActionQueue(
    adapter: adapter, token: CancellationToken(), policy: SafetyPolicy(), event: { _ in })
  var machine = CommandStateMachine()
  let text = "type hi and send"
  _ = machine.ingest(text: text, committed: "", now: 1)
  await queue.submit(machine.ingest(text: text, committed: "type hi", now: 1.3))
  try await Task.sleep(nanoseconds: 30_000_000)
  #expect(await adapter.commands.map(\.kind) == [.typeText])
}
@Test func dictatedCancelIsNotAnAction() {
  let commands = StreamingCommandParser().parse("type cancel my reservation")
  #expect(commands.map(\.kind) == [.typeText])
  #expect(commands.first?.value == "cancel my reservation")
}
@Test func deniedAdapterCannotCommitQueuedActions() async throws {
  let adapter = RejectingContactAdapter()
  let queue = ActionQueue(
    adapter: adapter, token: CancellationToken(), policy: SafetyPolicy(), event: { _ in })
  let commands = [
    Command(id: 0, kind: .contact, value: "Synthetic", endOffset: 0),
    Command(id: 1, kind: .send, value: "", endOffset: 0),
  ]
  await queue.submit(CommandBatch(revision: 0, commands: commands, stableEnd: 0, committedEnd: 0))
  try await Task.sleep(nanoseconds: 30_000_000)
  #expect(await adapter.kinds == [.contact])
}

@Test func messageSearchHitsAreNotRecipients() {
  var section = ConversationSearchSection()
  #expect(!section.acceptsConversation)
  section.enter("\u{200e}Chats")
  #expect(section.acceptsConversation)
  section.enter("Groups in common")
  #expect(!section.acceptsConversation)
  section.enter("Messages")
  #expect(!section.acceptsConversation)
  section.enter("Contacts")
  #expect(section.acceptsConversation)
}

@Test func frequentPartialUpdatesKeepPrefixAge() {
  var machine = CommandStateMachine()
  _ = machine.ingest(text: "Open WhatsApp", committed: "", now: 1)
  _ = machine.ingest(text: "Open WhatsApp, then", committed: "", now: 1.05)
  _ = machine.ingest(text: "Open WhatsApp, then go", committed: "", now: 1.10)
  let batch = machine.ingest(text: "Open WhatsApp, then go to Mummy", committed: "", now: 1.16)
  #expect(batch.commands.first?.kind == .openApp)
  #expect(batch.commands.first!.endOffset <= batch.stableEnd)
}

actor StageGateAdapter: ApplicationAdapter {
  let heldKind: CommandKind
  var enteredGate = false
  var completed: [CommandKind] = []
  private var continuation: CheckedContinuation<Void, Never>?
  init(heldKind: CommandKind) { self.heldKind = heldKind }
  func execute(_ command: Command, token: CancellationToken, revision: Int, policy: SafetyPolicy)
    async throws -> String
  {
    try token.check(revision: revision)
    if command.kind == heldKind {
      enteredGate = true
      await withCheckedContinuation { continuation = $0 }
    }
    try token.check(revision: revision)
    completed.append(command.kind)
    return command.kind == .send ? "dryRun" : "success"
  }
  func release() {
    continuation?.resume()
    continuation = nil
  }
  func reset() {}
}

@Test(arguments: [CommandKind.openApp, .contact, .typeText, .send])
func cancellationAtEveryActionBoundary(_ heldKind: CommandKind) async throws {
  let adapter = StageGateAdapter(heldKind: heldKind)
  let token = CancellationToken()
  let queue = ActionQueue(adapter: adapter, token: token, policy: SafetyPolicy(), event: { _ in })
  var machine = CommandStateMachine()
  let phrase = "Open WhatsApp, go to Synthetic Contact, type synthetic draft and send"
  await queue.submit(machine.ingest(text: phrase, committed: phrase, now: 1))
  let deadline = ContinuousClock.now.advanced(by: .seconds(2))
  while !(await adapter.enteredGate), ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(1))
  }
  #expect(await adapter.enteredGate)
  token.cancel()
  await queue.cancel()
  await adapter.release()
  try await Task.sleep(for: .milliseconds(20))
  let kinds: [CommandKind] = [.openApp, .contact, .typeText, .send]
  let index = kinds.firstIndex(of: heldKind)!
  #expect(await adapter.completed == Array(kinds.prefix(index)))
}

@Test func opensBeforeFinalWhileLaterClausesAreStillArriving() async throws {
  let adapter = MockAdapter()
  let queue = ActionQueue(
    adapter: adapter, token: CancellationToken(), policy: SafetyPolicy(), event: { _ in })
  var machine = CommandStateMachine()
  await queue.submit(machine.ingest(text: "Open WhatsApp", committed: "", now: 1))
  await queue.submit(machine.ingest(text: "Open WhatsApp, go to", committed: "", now: 1.2))
  try await Task.sleep(for: .milliseconds(20))
  #expect(await adapter.commands.map(\.kind) == [.openApp])
  let phrase = "Open WhatsApp, go to Synthetic Contact, type hi and send"
  await queue.submit(machine.ingest(text: phrase, committed: "Open WhatsApp", now: 1.3))
  await queue.submit(machine.ingest(text: phrase, committed: "Open WhatsApp", now: 1.6))
  try await Task.sleep(for: .milliseconds(20))
  #expect(await adapter.commands.map(\.kind) == [.openApp, .contact, .typeText])
  await queue.submit(machine.ingest(text: phrase, committed: phrase, now: 2))
  try await Task.sleep(for: .milliseconds(20))
  #expect(await adapter.commands.map(\.kind) == [.openApp, .contact, .typeText, .send])
}
