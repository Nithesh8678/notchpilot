import AppKit
import NotchPilotCore
import SwiftUI

@MainActor final class AppController: ObservableObject {
  let settings = LocalSettings()
  let permissions = PermissionCoordinator()
  let overlay = NotchOverlay()
  let hotkeys = HotkeyManager()
  let speech = SpeechPipeline()
  let laya = LayaDecisionService()
  let diagnostics = Diagnostics()
  let performance = PerformanceMonitor()
  @Published var listening = false
  @Published var paused = false
  @Published var confirmationNeeded = false
  @Published var diagnosticText = ""
  @Published var notice = ""
  private var session = UUID()
  private var token: CancellationToken?
  private var queue: ActionQueue?
  private var activation: Task<Void, Never>?
  private var cleanup: Task<Void, Never>?
  private var processing: Task<Void, Never>?
  private var retention: Task<Void, Never>?
  private var sessionTimeout: Task<Void, Never>?
  private var updates: AsyncStream<SpeechUpdate>.Continuation?
  private var settingsWindow: NSWindow?
  private var statusItem: NSStatusItem?
  func launch() {
    hotkeys.onPress = { [weak self] in self?.toggle() }
    hotkeys.onRelease = { [weak self] in if self?.settings.holdToTalk == true { self?.cancel() } }
    hotkeys.onCancel = { [weak self] in self?.cancel() }
    applyHotkey()
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem?.button?.image = NSImage(
      systemSymbolName: "waveform.circle", accessibilityDescription: "NotchPilot")
    let menu = NSMenu()
    for (title, selector) in [
      ("Start / Stop Listening", #selector(toggleFromMenu)),
      ("Confirm Pending Send", #selector(confirmFromMenu)),
      ("Settings…", #selector(settingsFromMenu)), ("Diagnostics…", #selector(diagnosticsFromMenu)),
      ("Pause / Resume", #selector(pauseFromMenu)), ("Quit NotchPilot", #selector(quit)),
    ] {
      let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
      item.target = self
      menu.addItem(item)
    }
    statusItem?.menu = menu
    if !UserDefaults.standard.bool(forKey: "onboarded") { showSettings() }
    Task {
      do {
        try await speech.prepare(language: settings.language)
        permissions.speechStatus = "On-device speech ready"
      } catch { permissions.speechStatus = "On-device assets need setup" }
    }
    Task { [weak self] in
      guard let self, !self.settings.lowResource else { return }
      let response = await self.laya.request("prepare")
      self.performance.modelStatus =
        response["summary"] as? String ?? "Optional Laya unavailable; direct commands ready"
    }
    if CommandLine.arguments.contains("--demo") { startDemo() }
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--acceptance-report"), args.count > i + 1 {
      Task {
        await AcceptanceHarness.pause(1)
        await AcceptanceHarness.run(controller: self, output: URL(fileURLWithPath: args[i + 1]))
      }
    }
    if let i = args.firstIndex(of: "--speech-fixture"), args.count > i + 2 {
      Task {
        await AcceptanceHarness.transcribe(
          file: URL(fileURLWithPath: args[i + 1]), output: URL(fileURLWithPath: args[i + 2]),
          controller: self)
      }
    }
    if let i = args.firstIndex(of: "--desktop-smoke"), args.count > i + 1 {
      Task { await AcceptanceHarness.desktopSmoke(output: URL(fileURLWithPath: args[i + 1])) }
    }
    if let i = args.firstIndex(of: "--speech-command-smoke"), args.count > i + 2 {
      Task {
        await AcceptanceHarness.speechCommands(
          file: URL(fileURLWithPath: args[i + 1]), output: URL(fileURLWithPath: args[i + 2]),
          controller: self)
      }
    }
    if let i = args.firstIndex(of: "--microphone-command-smoke"), args.count > i + 2 {
      Task {
        await AcceptanceHarness.speechCommands(
          file: URL(fileURLWithPath: args[i + 1]), output: URL(fileURLWithPath: args[i + 2]),
          controller: self, microphone: true)
      }
    }
    if let i = args.firstIndex(of: "--whatsapp-dry-run"), args.count > i + 1 {
      Task { await AcceptanceHarness.whatsappDryRun(output: URL(fileURLWithPath: args[i + 1])) }
    }
  }
  func applyHotkey() {
    if !hotkeys.register(code: settings.hotkeyCode, modifiers: settings.hotkeyModifiers) {
      notice = "Shortcut is already in use. Record a different one."
    }
  }
  @objc private func toggleFromMenu() { toggle() }
  @objc private func confirmFromMenu() { confirm() }
  @objc private func settingsFromMenu() { showSettings() }
  @objc private func diagnosticsFromMenu() {
    Task {
      diagnosticText = await diagnostics.read()
      showSettings()
    }
  }
  @objc private func pauseFromMenu() {
    paused.toggle()
    if paused { cancel() }
  }
  @objc private func quit() {
    token?.cancel()
    laya.stop()
    NSApplication.shared.terminate(nil)
  }
  func toggle() { if listening { cancel() } else { start() } }
  func start() {
    guard !paused else {
      notice = "Resume NotchPilot from the menu bar first."
      return
    }
    let begin = CACurrentMediaTime()
    overlay.show(.activating, action: "Starting on-device listening")
    performance.hotkeyMilliseconds = (CACurrentMediaTime() - begin) * 1000
    permissions.refresh()
    guard permissions.microphone == .authorized else {
      overlay.show(.error, action: "Microphone permission is needed")
      showSettings()
      return
    }
    beginSession()
    let current = session
    let previousCleanup = cleanup
    activation = Task { [weak self] in
      guard let self else { return }
      await previousCleanup?.value
      do {
        try Task.checkCancellation()
        try await self.speech.start(
          language: self.settings.language,
          update: { [weak self] update in
            Task { @MainActor in
              guard let self, self.session == current, self.listening else { return }
              self.overlay.model.transcript = update.text
              self.updates?.yield(update)
            }
          },
          level: { [weak self] level in
            Task { @MainActor in
              if self?.session == current, self?.listening == true {
                self?.overlay.model.level = level
              }
            }
          },
          failure: { [weak self] message in
            Task { @MainActor in if self?.session == current { self?.fail(message) } }
          })
        guard self.session == current, self.listening else { return }
        self.permissions.speechStatus = "On-device speech ready"
        self.overlay.show(.listening, action: "Listening · audio stays on this Mac")
      } catch is CancellationError {} catch {
        if self.session == current { self.fail(error.localizedDescription) }
      }
    }
  }
  private func beginSession(adapter: (any ApplicationAdapter)? = nil) {
    retention?.cancel()
    sessionTimeout?.cancel()
    confirmationNeeded = false
    notice = ""
    session = UUID()
    listening = true
    hotkeys.enableEscape(true)
    overlay.model.transcript = ""
    overlay.model.next = ""
    let token = CancellationToken()
    self.token = token
    let current = session
    let selectedAdapter = adapter ?? DesktopAdapter(aliases: settings.aliases)
    let queue = ActionQueue(
      adapter: selectedAdapter, token: token,
      policy: SafetyPolicy(
        dryRun: adapter != nil || settings.dryRun, confirmAll: settings.confirmAll),
      event: { [weak self] event in
        Task { @MainActor in
          guard let self, self.session == current else { return }
          self.receive(event)
          await self.diagnostics.record(event)
        }
      })
    self.queue = queue
    let (stream, continuation) = AsyncStream<SpeechUpdate>.makeStream(
      bufferingPolicy: .bufferingNewest(8))
    updates = continuation
    processing = Task.detached(priority: .userInitiated) { [self, laya] in
      var decision: Task<Void, Never>?
      defer { decision?.cancel() }
      var machine = CommandStateMachine()
      for await update in stream {
        if Task.isCancelled { return }
        decision?.cancel()
        decision = nil
        let time = ProcessInfo.processInfo.systemUptime
        let batch = machine.ingest(text: update.text, committed: update.committed, now: time)
        token.update(revision: batch.revision)
        if machine.cancelled {
          await self.cancel()
          return
        }
        await queue.submit(batch)
        if batch.commands.isEmpty && update.isFinal && !update.text.isEmpty {
          // Optional constrained app-launch classification. Never pass dictation or contacts.
          let lower = TextNormalization.identity(update.text)
          if ["message", "password", "type", "say", "send", "contact", "pay"].contains(
            where: lower.contains)
          {
            await self.unsupported()
            continue
          }
          decision = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            let response = await laya.request("choose", state: update.text)
            if response["status"] as? String == "choice", let label = response["label"] as? String,
              let app = [
                "open_whatsapp": "WhatsApp", "open_safari": "Safari", "open_notes": "Notes",
                "open_finder": "Finder",
              ][label]
            {
              let command = Command(id: 0, kind: .openApp, value: app, endOffset: 0)
              await queue.submit(
                CommandBatch(
                  revision: batch.revision, commands: [command], stableEnd: 0, committedEnd: 0))
            } else {
              await self.unsupported()
            }
          }
        }
        await MainActor.run {
          guard self.session == current else { return }
          self.performance.directMilliseconds = (ProcessInfo.processInfo.systemUptime - time) * 1000
          self.overlay.model.next =
            batch.commands.count > 1 ? "Follow-up actions queued · Esc cancels" : ""
        }
      }
    }
    sessionTimeout = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 60_000_000_000)
      guard !Task.isCancelled, self?.session == current else { return }
      self?.cancel()
    }
  }
  private func receive(_ event: ExecutionEvent) {
    if event.status.hasPrefix("error: ") {
      notice = String(event.status.dropFirst(7))
      overlay.show(.error, action: notice)
      overlay.model.next = "Listening continues · Esc cancels · restart to retry"
      permissions.refresh()
      return
    }
    if event.status == "waiting" {
      overlay.show(.understanding, action: "Waiting for the complete app name · still listening")
      return
    }
    if event.status == "confirmation" {
      confirmationNeeded = true
      overlay.show(.needsConfirmation, action: "Review the draft; confirm from the menu bar")
      return
    }
    if event.status == "executing" {
      let titles: [CommandKind: String] = [
        .openApp: "Opening application", .contact: "Finding the exact conversation",
        .typeText: "Entering your words", .send: "Verifying before send",
      ]
      overlay.show(.executing, action: titles[event.kind] ?? "Working")
    } else if event.status == "dispatched" {
      overlay.show(.listening, action: "Action dispatched · still listening")
    } else if event.status == "dryRun" {
      overlay.show(.success, action: "Dry Run complete · message was not sent")
    } else {
      overlay.show(
        event.kind == .send ? .success : .listening,
        action: event.kind == .typeText
          ? "Draft entered · say ‘and send’ to send" : "Action verified · still listening")
    }
  }
  func confirm() {
    guard confirmationNeeded else { return }
    confirmationNeeded = false
    Task { await queue?.confirm() }
  }
  func unsupported() { overlay.show(.understanding, action: "I can’t do that yet.") }
  func cancel() {
    token?.cancel()
    activation?.cancel()
    processing?.cancel()
    updates?.finish()
    updates = nil
    sessionTimeout?.cancel()
    confirmationNeeded = false
    listening = false
    hotkeys.enableEscape(false)
    let oldQueue = queue
    queue = nil
    cleanup = Task { [speech] in
      await speech.cancel()
      await oldQueue?.cancel()
    }
    overlay.show(.cancelled, action: "Cancelled · queued actions cleared")
    scheduleClear()
    if settings.lowResource { laya.stop() }
  }
  private func fail(_ message: String) {
    cancel()
    overlay.show(.error, action: message)
    notice = message
    permissions.refresh()
    // An action error must not repeatedly steal focus or interrupt dictation.
    // Permission controls remain available from the menu bar.
  }
  private func scheduleClear() {
    let current = session
    let seconds = max(5, min(120, settings.retention))
    retention = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9))
      guard !Task.isCancelled, self?.session == current, self?.listening == false else { return }
      self?.overlay.model.transcript = ""
      self?.overlay.model.next = ""
      self?.overlay.hide()
    }
  }
  func installSpeech() {
    permissions.speechStatus = "Preparing local speech assets…"
    Task {
      do {
        try await speech.prepare(language: settings.language, installAssets: true)
        permissions.speechStatus = "On-device speech ready"
      } catch { permissions.speechStatus = error.localizedDescription }
    }
  }
  func showSettings() {
    permissions.refresh()
    if settingsWindow == nil {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 590, height: 690),
        styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
        defer: false)
      window.title = "NotchPilot Settings"
      window.contentView = NSHostingView(
        rootView: SettingsView(
          controller: self, settings: settings, permissions: permissions, performance: performance))
      window.isReleasedWhenClosed = false
      window.center()
      settingsWindow = window
    }
    NSApplication.shared.activate()
    settingsWindow?.makeKeyAndOrderFront(nil)
  }
  func startDemo() {
    beginSession(adapter: DemoAdapter())
    overlay.show(.listening, action: "Synthetic demo · no real messages")
    let continuation = updates
    Task {
      for text in [
        "Open WhatsApp", "Open WhatsApp, go to Mummy", "Open WhatsApp, go to Mummy, type hi",
        "Open WhatsApp, go to Mummy, type hi and send",
      ] {
        overlay.model.transcript = text
        continuation?.yield(SpeechUpdate(text: text, committed: text, isFinal: true))
        try? await Task.sleep(nanoseconds: 800_000_000)
      }
    }
  }
}
actor DemoAdapter: ApplicationAdapter {
  func execute(_ command: Command, token: CancellationToken, revision: Int, policy: SafetyPolicy)
    async throws -> String
  {
    try token.check(revision: revision)
    try await Task.sleep(nanoseconds: 150_000_000)
    try token.check(revision: revision)
    return command.kind == .send ? "dryRun" : "success"
  }
  func reset() {}
}
