import AppKit
import ApplicationServices
import NotchPilotCore

actor WhatsAppAdapter: ApplicationAdapter {
  private let executor = MacExecutor()
  private let aliases: [String: String]
  private var client: AccessibilityClient?
  private var recipient: String?
  private var draft = ""
  private var targetIsWhatsApp = false
  init(aliases: [String: String]) { self.aliases = aliases }
  func reset() {
    client = nil
    recipient = nil
    draft = ""
    targetIsWhatsApp = false
  }
  func execute(_ command: Command, token: CancellationToken, revision: Int, policy: SafetyPolicy)
    async throws -> String
  {
    try token.check(revision: revision)
    switch command.kind {
    case .openApp:
      let pid = try await executor.launch(command.value, token: token)
      targetIsWhatsApp = TextNormalization.identity(command.value) == "whatsapp"
      if targetIsWhatsApp { client = try AccessibilityClient(pid: pid) }
      return "success"
    case .contact:
      guard targetIsWhatsApp, let client else {
        throw PilotError.unsafe("Say ‘open WhatsApp’ before choosing a conversation.")
      }
      try await client.wait(token: token) { !client.windows().isEmpty }
      let target = ContactResolver.resolve(command.value, aliases: aliases)
      // Use the application's native File > Search menu command. Merely pressing
      // the Catalyst search label does not reliably focus the editable control.
      var menuItems = client.search {
        $0.role == kAXMenuItemRole && TextNormalization.identity($0.identifier) == "search"
      }
      if menuItems.isEmpty {
        let fileMenu = client.search {
          $0.role == kAXMenuBarItemRole
            && $0.names.contains { TextNormalization.identity($0) == "file" }
        }
        guard fileMenu.count == 1 else {
          throw PilotError.unavailable("WhatsApp Search menu is unavailable.")
        }
        try client.press(fileMenu[0], token: token, revision: revision)
        menuItems = client.search {
          $0.role == kAXMenuItemRole && TextNormalization.identity($0.identifier) == "search"
        }
      }
      guard menuItems.count == 1 else {
        throw PilotError.unavailable("A unique WhatsApp Search menu command is required.")
      }
      try client.press(menuItems[0], token: token, revision: revision)
      let search = try client.unique(identifier: "TokenizedSearchBar_TextView")
      let oldSearch = client.string(search.element, kAXValueAttribute)
      try client.setText(
        search, text: target, previous: oldSearch, token: token, revision: revision)
      try await client.wait(token: token, revision: revision, timeout: 5) {
        client.string(search.element, kAXValueAttribute) == target
      }
      var candidates: [AXNode] = []
      try await client.wait(token: token, revision: revision, timeout: 8) {
        // Read only labels, never chat preview values or unrelated message tables.
        let roots = client.search { TextNormalization.identity($0.label) == "search results" }
        guard roots.count == 1 else { return false }
        candidates = []
        var section = ConversationSearchSection()
        for child in client.children(roots[0].element) {
          let node = client.node(child)
          let headings = client.search(root: child) { $0.role == kAXHeadingRole }.flatMap(\.names)
          if let heading = headings.first(where: { ConversationSearchSection.isHeading($0) }) {
            section.enter(heading)
            continue
          }
          guard section.acceptsConversation,
            node.names.contains(where: {
              TextNormalization.identity($0) == TextNormalization.identity(target)
            })
          else { continue }
          candidates.append(node)
        }
        return !candidates.isEmpty
      }
      let index = try ContactResolver.exactIndex(
        target: target,
        candidates: candidates.map { node in
          node.names.first(where: {
            TextNormalization.identity($0) == TextNormalization.identity(target)
          }) ?? ""
        })
      try client.press(candidates[index], token: token, revision: revision)
      try await client.wait(token: token, revision: revision, timeout: 8) {
        self.headerMatches(target, client: client)
      }
      recipient = target
      draft = ""
      return "success"
    case .typeText:
      guard let client, let recipient, headerMatches(recipient, client: client) else {
        throw PilotError.unsafe("Choose an exact WhatsApp conversation first.")
      }
      let composer = try client.unique(identifier: "ChatBar_ComposerTextView")
      try client.setText(
        composer, text: command.value, previous: draft, preferKeyboard: true, token: token,
        revision: revision)
      try await client.wait(token: token, revision: revision, timeout: 4) {
        client.string(composer.element, kAXValueAttribute) == command.value
      }
      draft = command.value
      return "success"
    case .send:
      guard let client, let recipient, !draft.isEmpty, headerMatches(recipient, client: client)
      else {
        throw PilotError.unsafe("Recipient or message could not be verified. Nothing was sent.")
      }
      let composer = try client.unique(identifier: "ChatBar_ComposerTextView")
      guard client.string(composer.element, kAXValueAttribute) == draft else {
        throw PilotError.unsafe("The composer changed. Nothing was sent.")
      }
      if policy.dryRun { return "dryRun" }
      let buttons = client.search {
        $0.identifier == "ChatBar_SendButton"
          || ($0.role == kAXButtonRole
            && $0.names.contains { TextNormalization.identity($0) == "send" })
      }
      guard buttons.count == 1 else {
        throw PilotError.unavailable("A unique Send button is not available. Nothing was sent.")
      }
      let before = matchingMessageCount(client, recipient: recipient, message: draft)
      try token.check(revision: revision)
      // Recheck immediately at the irreversible boundary.
      guard headerMatches(recipient, client: client),
        client.string(composer.element, kAXValueAttribute) == draft
      else { throw PilotError.unsafe("Conversation changed before sending.") }
      try client.press(buttons[0], token: token, revision: revision)
      try await client.wait(token: token, timeout: 8) {
        client.string(composer.element, kAXValueAttribute).isEmpty
          && self.matchingMessageCount(client, recipient: recipient, message: self.draft) > before
      }
      draft = ""
      return "success"
    case .cancel: throw PilotError.cancelled
    case .unsupported: throw PilotError.unavailable("I can’t do that yet.")
    }
  }
  private func headerMatches(_ target: String, client: AccessibilityClient) -> Bool {
    let headers = client.search { $0.identifier == "NavigationBar_HeaderViewButton" }
    return headers.count == 1
      && headers[0].names.contains {
        TextNormalization.identity($0) == TextNormalization.identity(target)
      }
  }
  private func matchingMessageCount(
    _ client: AccessibilityClient, recipient: String, message: String
  ) -> Int {
    guard headerMatches(recipient, client: client),
      let table = try? client.unique(identifier: "ChatMessagesTableView")
    else { return 0 }
    return client.search(root: table.element, includeMessages: true) {
      guard $0.identifier == "WAMessageBubbleTableViewCell" else { return false }
      let label = TextNormalization.identity($0.label)
      // Native WhatsApp exposes outgoing message content in its accessible description.
      return label.hasPrefix("your message, " + TextNormalization.identity(message) + ",")
        && label.contains("sent to " + TextNormalization.identity(recipient))
    }.count
  }
}
