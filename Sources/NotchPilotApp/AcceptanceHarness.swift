import AVFoundation
import AppKit
import ApplicationServices
import Carbon
import NotchPilotCore

@MainActor enum AcceptanceHarness {
  static func press(_ code: CGKeyCode, flags: CGEventFlags = []) {
    let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)
    let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)
    down?.flags = flags
    up?.flags = flags
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
  }
  static func pause(_ seconds: Double) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9))
  }
  static func run(controller: AppController, output: URL) async {
    var report: [String: Any] = [:]
    let previousHoldMode = controller.settings.holdToTalk
    controller.settings.holdToTalk = false
    defer { controller.settings.holdToTalk = previousHoldMode }
    controller.settings.dryRun = true
    controller.permissions.refresh()
    report["microphone_granted"] = controller.permissions.microphone == .authorized
    report["accessibility_granted"] = controller.permissions.accessibility
    controller.overlay.hide()
    var flags: CGEventFlags = []
    let modifiers = controller.settings.hotkeyModifiers
    if modifiers & UInt32(optionKey) != 0 { flags.insert(.maskAlternate) }
    if modifiers & UInt32(controlKey) != 0 { flags.insert(.maskControl) }
    if modifiers & UInt32(cmdKey) != 0 { flags.insert(.maskCommand) }
    if modifiers & UInt32(shiftKey) != 0 { flags.insert(.maskShift) }
    let code = CGKeyCode(controller.settings.hotkeyCode)
    press(code, flags: flags)
    await pause(1)
    report["hotkey_starts_listening"] = controller.listening
    report["hotkey_shows_overlay"] = controller.overlay.visible
    if controller.listening {
      report["hotkey_callback_overlay_submit_ms"] = controller.performance.hotkeyMilliseconds
    }
    press(code, flags: flags)
    await pause(0.5)
    report["second_hotkey_stops"] =
      (report["hotkey_starts_listening"] as? Bool == true) && !controller.listening
    press(code, flags: flags)
    await pause(0.5)
    let restarted = controller.listening
    press(53)
    await pause(0.5)
    report["escape_cancels"] = restarted && !controller.listening
    controller.overlay.hide()
    var latencies: [Double] = []
    for _ in 0..<30 {
      let begin = CACurrentMediaTime()
      controller.overlay.show(.listening, action: "Synthetic performance test")
      latencies.append((CACurrentMediaTime() - begin) * 1000)
      controller.overlay.hide()
      await pause(0.01)
    }
    latencies.sort()
    report["overlay_submit_p50_ms"] = latencies[latencies.count / 2]
    report["overlay_submit_p95_ms"] = latencies[Int(Double(latencies.count) * 0.95)]
    let timings = DispatchTimingAdapter()
    var direct: [Double] = []
    for _ in 0..<100 {
      let token = CancellationToken()
      let queue = ActionQueue(
        adapter: timings, token: token, policy: SafetyPolicy(), event: { _ in })
      var machine = CommandStateMachine()
      let begin = ProcessInfo.processInfo.systemUptime
      await timings.begin(begin)
      await queue.submit(
        machine.ingest(text: "Open WhatsApp", committed: "Open WhatsApp", now: begin))
      while await timings.last() == nil { await Task.yield() }
      if let elapsed = await timings.last() { direct.append(elapsed) }
    }
    direct.sort()
    report["direct_dispatch_p50_ms"] = direct[direct.count / 2]
    report["direct_dispatch_p95_ms"] = direct[Int(Double(direct.count) * 0.95)]
    report["direct_samples"] = direct.count
    // Off-main-process inference while measuring main-run-loop wake delays.
    let inference = Task.detached {
      await controller.laya.request("choose", state: "Show me Safari")
    }
    var wake: [Double] = []
    for _ in 0..<200 {
      let begin = CACurrentMediaTime()
      await pause(0.016)
      wake.append(max(0, (CACurrentMediaTime() - begin) * 1000 - 16))
    }
    let answer = await inference.value
    wake.sort()
    report["laya_response"] = answer["status"] ?? "unavailable"
    report["main_loop_lateness_p95_ms"] = wake[Int(Double(wake.count) * 0.95)]
    controller.overlay.hide()
    await pause(2)
    report["native_resident_mb"] = PerformanceMonitor.residentMB()
    report["screen_has_notch"] = NSScreen.screens.contains { $0.safeAreaInsets.top > 0 }
    report["screen_count"] = NSScreen.screens.count
    report["measured_at"] = ISO8601DateFormatter().string(from: Date())
    do {
      try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        .write(to: output, options: .atomic)
    } catch {}
  }
  static func transcribe(file: URL, output: URL, controller: AppController) async {
    let collector = FixtureCollector()
    let pipeline = SpeechPipeline()
    do {
      try await pipeline.transcribeFixture(file, language: "en-US") { update in
        collector.add(update)
        Task { @MainActor in
          controller.overlay.model.transcript = update.text
          controller.overlay.show(.listening, action: "Synthetic on-device speech test")
        }
      }
      let result = collector.report()
      try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        .write(to: output)
    } catch {
      try? JSONSerialization.data(withJSONObject: ["error": error.localizedDescription]).write(
        to: output)
    }
    await pipeline.cancel()
  }
  static func desktopSmoke(output: URL) async {
    let adapter = DesktopAdapter(aliases: [:])
    let token = CancellationToken()
    var report: [String: Any] = [:]
    let apps = await ApplicationCatalog.shared.applications()
    report["installed_app_count"] = apps.count
    for name in ["Calculator", "TextEdit", "Safari", "Finder"] {
      do {
        _ = try await adapter.execute(
          Command(id: 0, kind: .openApp, value: name, endOffset: 0), token: token, revision: 0,
          policy: SafetyPolicy())
        report[name + "_launch"] = true
      } catch {
        report[name + "_launch"] = false
        report[name + "_error"] = error.localizedDescription
      }
    }
    try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      .write(to: output)
  }
  /// Real on-device speech and the real queue/executor. The probe only permits
  /// Calculator and TextEdit launches; fixture tests cannot send or type anything.
  static func speechCommands(
    file: URL, output: URL, controller: AppController, microphone: Bool = false
  ) async {
    let probe = SpeechCommandProbe()
    let token = CancellationToken()
    let queue = ActionQueue(adapter: probe, token: token, policy: SafetyPolicy(), event: { _ in })
    let pipeline = SpeechPipeline()
    let (stream, continuation) = AsyncStream<SpeechUpdate>.makeStream()
    let consumer = Task {
      var machine = CommandStateMachine()
      for await update in stream {
        await probe.setVolatile(!update.isFinal)
        controller.overlay.model.transcript = update.text
        controller.overlay.show(.listening, action: "Synthetic speech → real application launch")
        await queue.submit(
          machine.ingest(
            text: update.text, committed: update.committed,
            now: ProcessInfo.processInfo.systemUptime))
      }
    }
    var failure = false
    do {
      if microphone {
        guard controller.permissions.microphone == .authorized else {
          throw PilotError.unavailable("Approve microphone access before the acoustic smoke test.")
        }
        try await pipeline.start(
          language: "en-US", update: { continuation.yield($0) }, level: { _ in },
          failure: { _ in continuation.finish() })
        let playback = SyntheticPlayback()
        let duration = try await playback.play(file)
        await pause(duration + 4)
        await playback.stop()
        await pipeline.cancel()
      } else {
        try await pipeline.transcribeFixture(file, language: "en-US") { continuation.yield($0) }
      }
    } catch { failure = true }
    continuation.finish()
    await consumer.value
    for _ in 0..<100 {
      if await probe.count() >= 2 { break }
      await pause(0.1)
    }
    await queue.cancel()
    let report = await probe.report(speechFailed: failure)
    try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      .write(to: output)
    controller.overlay.hide()
    await pipeline.cancel()
  }
  static func whatsappDryRun(output: URL) async {
    let adapter = WhatsAppAdapter(aliases: [:])
    let token = CancellationToken()
    var stages: [String: String] = [:]
    let commands = StreamingCommandParser().parse("Open WhatsApp, go to Mummy, type hi and send")
    for command in commands {
      do {
        stages[command.kind.rawValue] = try await adapter.execute(
          command, token: token, revision: 0, policy: SafetyPolicy(dryRun: true))
      } catch {
        stages[command.kind.rawValue] = error.localizedDescription
        break
      }
    }
    try? JSONSerialization.data(withJSONObject: stages, options: [.prettyPrinted, .sortedKeys])
      .write(to: output)
  }
}
private actor SyntheticPlayback {
  private var player: AVAudioPlayer?
  func play(_ url: URL) throws -> Double {
    let player = try AVAudioPlayer(contentsOf: url)
    guard player.duration > 0 else { throw PilotError.unavailable("The fixture has no audio.") }
    player.prepareToPlay()
    guard player.play() else { throw PilotError.unavailable("Audio playback is unavailable.") }
    self.player = player
    return player.duration
  }
  func stop() {
    player?.stop()
    player = nil
  }
}
actor SpeechCommandProbe: ApplicationAdapter {
  private let desktop = DesktopAdapter(aliases: [:])
  private var volatile = false
  private var launches: [String] = []
  private var early = false
  func setVolatile(_ value: Bool) { volatile = value }
  func count() -> Int { launches.count }
  func reset() async { await desktop.reset() }
  func execute(_ command: Command, token: CancellationToken, revision: Int, policy: SafetyPolicy)
    async throws -> String
  {
    let target = TextNormalization.appIdentity(command.value)
    guard command.kind == .openApp, ["calculator", "textedit"].contains(target) else {
      throw PilotError.incompleteCommand
    }
    let beforeFinal = volatile
    let result = try await desktop.execute(
      command, token: token, revision: revision, policy: policy)
    launches.append(target)
    early = early || beforeFinal
    return result
  }
  func report(speechFailed: Bool) -> [String: Any] {
    [
      "speech_failed": speechFailed, "launched_apps": launches, "real_launch_before_final": early,
      "duplicate_launches": launches.count != Set(launches).count,
    ]
  }
}
actor DispatchTimingAdapter: ApplicationAdapter {
  private var started = 0.0
  private var elapsed: Double?
  func begin(_ time: Double) {
    started = time
    elapsed = nil
  }
  func last() -> Double? { elapsed }
  func execute(_ command: Command, token: CancellationToken, revision: Int, policy: SafetyPolicy)
    async throws -> String
  {
    try token.check(revision: revision)
    elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1000
    return "success"
  }
  func reset() {}
}
final class FixtureCollector: @unchecked Sendable {
  private let lock = NSLock()
  private var samples = 0, volatile = 0
  private var text = ""
  private var early = false
  private var machine = CommandStateMachine()
  func add(_ update: SpeechUpdate) {
    lock.lock()
    defer { lock.unlock() }
    samples += 1
    if !update.isFinal { volatile += 1 }
    text = update.text
    let batch = machine.ingest(
      text: update.text, committed: update.committed, now: ProcessInfo.processInfo.systemUptime)
    if !update.isFinal
      && batch.commands.contains(where: { $0.kind == .openApp && $0.endOffset <= batch.stableEnd })
    {
      early = true
    }
  }
  func report() -> [String: Any] {
    lock.lock()
    defer { lock.unlock() }
    return [
      "samples": samples, "volatile_samples": volatile, "early_open": early,
      "synthetic_transcript": text,
      "command_kinds": StreamingCommandParser().parse(text).map { $0.kind.rawValue },
    ]
  }
}
