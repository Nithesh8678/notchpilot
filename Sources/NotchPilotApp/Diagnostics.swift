import Foundation
import NotchPilotCore

actor Diagnostics {
  struct Entry: Codable, Sendable {
    let timestamp: Date
    let action: String
    let application: String
    let result: String
    let milliseconds: Double
  }
  private var entries: [Entry] = []
  private var url: URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Library/Application Support/NotchPilot/audit.json")
  }
  func record(_ event: ExecutionEvent) {
    let result =
      event.status.hasPrefix("error")
      ? "failure"
      : ["success", "executing", "dryRun", "confirmation"].contains(event.status)
        ? event.status : "cancelled"
    entries.append(
      Entry(
        timestamp: Date(), action: event.kind.rawValue,
        application: event.kind == .openApp ? "application" : "WhatsApp", result: result,
        milliseconds: event.milliseconds))
    entries = Array(entries.suffix(200))
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      try JSONEncoder().encode(entries).write(to: url, options: .atomic)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    } catch {
      // Diagnostics must never prevent control or log private exception text.
    }
  }
  func read() -> String {
    if entries.isEmpty, let data = try? Data(contentsOf: url),
      let saved = try? JSONDecoder().decode([Entry].self, from: data)
    {
      entries = saved
    }
    return entries.suffix(100).map {
      "\($0.timestamp.formatted()) · \($0.action) · \($0.result) · \(Int($0.milliseconds)) ms"
    }.joined(separator: "\n")
  }
  func delete() {
    entries = []
    try? FileManager.default.removeItem(at: url)
  }
}
@MainActor final class PerformanceMonitor: ObservableObject {
  @Published var hotkeyMilliseconds: Double = 0
  @Published var directMilliseconds: Double = 0
  @Published var modelStatus = "Optional model not ready"
  static func residentMB() -> Double {
    var info = mach_task_basic_info()
    var size = mach_msg_type_number_t(
      MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &size)
      }
    }
    return result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : 0
  }
}
