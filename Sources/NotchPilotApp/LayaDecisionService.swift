import Foundation
import NotchPilotCore

/// Private inherited pipes. The worker owns a single Python process and serializes requests.
final class LayaDecisionService: @unchecked Sendable {
  private let worker = DispatchQueue(label: "NotchPilot.laya", qos: .utility)
  private let lock = NSLock()
  private var process: Process?
  private var input: FileHandle?
  private var output: FileHandle?
  private var pendingBytes = Data()
  private var configuration: [String: Any] = [:]
  func stop() {
    lock.lock()
    let process = process
    lock.unlock()
    if process?.isRunning == true { process?.terminate() }
  }
  func request(_ operation: String, state: String = "") async -> [String: Any] {
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        worker.async {
          do { continuation.resume(returning: try self.exchange(operation, state: state)) } catch {
            self.stop()
            self.input = nil
            self.output = nil
            continuation.resume(returning: ["status": "unavailable"])
          }
        }
      }
    } onCancel: {
      self.stop()
    }
  }
  private func launchIfNeeded() throws {
    if process?.isRunning == true { return }
    let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Library/Application Support/NotchPilot")
    let configURL = directory.appendingPathComponent("runtime.json")
    configuration =
      (try JSONSerialization.jsonObject(with: Data(contentsOf: configURL))) as? [String: Any] ?? [:]
    guard let python = configuration["python"] as? String,
      let service = Bundle.main.resourceURL?.appendingPathComponent("sidecar/service.py"),
      FileManager.default.isExecutableFile(atPath: python)
    else { throw PilotError.unavailable("Run bootstrap.sh to set up the optional Laya model.") }
    let child = Process()
    let stdin = Pipe()
    let stdout = Pipe()
    child.executableURL = URL(fileURLWithPath: python)
    child.arguments = [service.path, configURL.path]
    child.standardInput = stdin
    child.standardOutput = stdout
    child.standardError = FileHandle.nullDevice
    child.environment = [
      "PATH": "/usr/bin:/bin", "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
      "USE_TF": "0", "HF_HUB_OFFLINE": "1", "TRANSFORMERS_OFFLINE": "1",
      "TOKENIZERS_PARALLELISM": "false", "HF_HUB_DISABLE_TELEMETRY": "1",
    ]
    try child.run()
    lock.lock()
    process = child
    lock.unlock()
    input = stdin.fileHandleForWriting
    output = stdout.fileHandleForReading
    pendingBytes = Data()
  }
  private func exchange(_ operation: String, state: String) throws -> [String: Any] {
    try launchIfNeeded()
    let id = UUID().uuidString
    let choices = [
      "open_whatsapp": "Launch or focus WhatsApp",
      "open_safari": "Launch or focus Safari web browser",
      "open_notes": "Launch or focus Apple Notes", "open_finder": "Launch or focus Finder",
      "unsupported": "Any other action or no explicit request to open an application",
    ]
    let request: [String: Any] = ["id": id, "op": operation, "state": state, "choices": choices]
    var bytes = try JSONSerialization.data(withJSONObject: request)
    bytes.append(10)
    guard bytes.count <= 32768 else { throw PilotError.unsafe("Decision request too large.") }
    guard let input, let output, let child = process else { throw PilotError.cancelled }
    let timeout = DispatchWorkItem { if child.isRunning { child.terminate() } }
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 30, execute: timeout)
    defer { timeout.cancel() }
    try input.write(contentsOf: bytes)
    while !pendingBytes.contains(10) {
      let data = output.availableData
      guard !data.isEmpty else {
        throw PilotError.unavailable("Laya unavailable")
      }
      pendingBytes.append(data)
      guard pendingBytes.count <= 32768 else { throw PilotError.unsafe("Invalid sidecar frame") }
    }
    let end = pendingBytes.firstIndex(of: 10)!
    let data = pendingBytes[..<end]
    pendingBytes.removeSubrange(...end)
    let reply = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    guard reply["id"] as? String == id else { throw PilotError.unsafe("Invalid sidecar response") }
    return reply
  }
}
