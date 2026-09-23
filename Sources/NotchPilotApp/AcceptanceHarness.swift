import AppKit
import ApplicationServices
import NotchPilotCore

@MainActor enum AcceptanceHarness {
    static func press(_ code: CGKeyCode, flags: CGEventFlags = []) {
        let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)
        down?.flags = flags; up?.flags = flags
        down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
    }
    static func pause(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9)) }
    static func run(controller: AppController, output: URL) async {
        var report: [String: Any] = [:]
        controller.settings.dryRun = true
        controller.permissions.refresh()
        report["microphone_granted"] = controller.permissions.microphone == .authorized
        report["accessibility_granted"] = controller.permissions.accessibility
        controller.overlay.hide()
        press(49, flags: .maskAlternate); await pause(1)
        report["hotkey_starts_listening"] = controller.listening
        report["hotkey_shows_overlay"] = controller.overlay.visible
        press(49, flags: .maskAlternate); await pause(0.5)
        report["second_hotkey_stops"] = !controller.listening
        press(49, flags: .maskAlternate); await pause(0.5)
        press(53); await pause(0.5)
        report["escape_cancels"] = !controller.listening
        controller.overlay.hide()
        var latencies: [Double] = []
        for _ in 0..<30 {
            let begin = CACurrentMediaTime()
            controller.overlay.show(.listening, action: "Synthetic performance test")
            latencies.append((CACurrentMediaTime() - begin)*1000)
            controller.overlay.hide(); await pause(0.01)
        }
        latencies.sort()
        report["overlay_submit_p50_ms"] = latencies[latencies.count/2]
        report["overlay_submit_p95_ms"] = latencies[Int(Double(latencies.count)*0.95)]
        let timings = DispatchTimingAdapter()
        var direct: [Double] = []
        for _ in 0..<100 {
            let token = CancellationToken()
            let queue = ActionQueue(adapter: timings, token: token, policy: SafetyPolicy(), event: { _ in })
            var machine = CommandStateMachine()
            let begin = ProcessInfo.processInfo.systemUptime
            await timings.begin(begin)
            await queue.submit(machine.ingest(text: "Open WhatsApp", committed: "Open WhatsApp", now: begin))
            while await timings.last() == nil { await Task.yield() }
            if let elapsed = await timings.last() { direct.append(elapsed) }
        }
        direct.sort()
        report["direct_dispatch_p50_ms"] = direct[direct.count/2]
        report["direct_dispatch_p95_ms"] = direct[Int(Double(direct.count)*0.95)]
        report["direct_samples"] = direct.count
        // Off-main-process inference while measuring main-run-loop wake delays.
        let inference = Task.detached { await controller.laya.request("choose", state: "Show me Safari") }
        var wake: [Double] = []
        for _ in 0..<200 {
            let begin = CACurrentMediaTime(); await pause(0.016)
            wake.append(max(0, (CACurrentMediaTime()-begin)*1000 - 16))
        }
        let answer = await inference.value
        wake.sort()
        report["laya_response"] = answer["status"] ?? "unavailable"
        report["main_loop_lateness_p95_ms"] = wake[Int(Double(wake.count)*0.95)]
        controller.overlay.hide(); await pause(2)
        report["native_resident_mb"] = PerformanceMonitor.residentMB()
        report["screen_has_notch"] = NSScreen.screens.contains { $0.safeAreaInsets.top > 0 }
        report["screen_count"] = NSScreen.screens.count
        report["measured_at"] = ISO8601DateFormatter().string(from: Date())
        do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic) } catch {}
    }
    static func transcribe(file: URL, output: URL, controller: AppController) async {
        let collector = FixtureCollector()
        let pipeline = SpeechPipeline()
        do {
            try await pipeline.transcribeFixture(file, language: "en-US") { update in
                collector.add(update)
                Task { @MainActor in controller.overlay.model.transcript = update.text; controller.overlay.show(.listening, action: "Synthetic on-device speech test") }
            }
            let result = collector.report()
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: output)
        } catch {
            try? JSONSerialization.data(withJSONObject: ["error": error.localizedDescription]).write(to: output)
        }
        await pipeline.cancel()
    }
    static func whatsappDryRun(output: URL) async {
        let adapter = WhatsAppAdapter(aliases: [:]), token = CancellationToken()
        var stages: [String: String] = [:]
        let commands = StreamingCommandParser().parse("Open WhatsApp, go to Mummy, type hi and send")
        for command in commands {
            do { stages[command.kind.rawValue] = try await adapter.execute(command, token: token, revision: 0, policy: SafetyPolicy(dryRun: true)) }
            catch { stages[command.kind.rawValue] = error.localizedDescription; break }
        }
        try? JSONSerialization.data(withJSONObject: stages, options: [.prettyPrinted, .sortedKeys]).write(to: output)
    }
}
actor DispatchTimingAdapter: ApplicationAdapter {
    private var started = 0.0
    private var elapsed: Double?
    func begin(_ time: Double) { started = time; elapsed = nil }
    func last() -> Double? { elapsed }
    func execute(_ command: Command, token: CancellationToken, revision: Int, policy: SafetyPolicy) async throws -> String {
        try token.check(revision: revision); elapsed = (ProcessInfo.processInfo.systemUptime - started)*1000; return "success"
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
        lock.lock(); defer { lock.unlock() }
        samples += 1; if !update.isFinal { volatile += 1 }
        text = update.text
        let batch = machine.ingest(text: update.text, committed: update.committed, now: ProcessInfo.processInfo.systemUptime)
        if !update.isFinal && batch.commands.contains(where: { $0.kind == .openApp && $0.endOffset <= batch.stableEnd }) { early = true }
    }
    func report() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return ["samples": samples, "volatile_samples": volatile, "early_open": early, "synthetic_transcript": text, "command_kinds": StreamingCommandParser().parse(text).map { $0.kind.rawValue }]
    }
}
