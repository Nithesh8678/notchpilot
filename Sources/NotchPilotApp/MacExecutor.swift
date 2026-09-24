import AppKit
import NotchPilotCore

struct InstalledApplication: Sendable {
  let name: String
  let identifier: String
  let url: URL
}

/// Application metadata only. Enumerated off the main actor, cached for the session.
actor ApplicationCatalog {
  static let shared = ApplicationCatalog()
  private var cached: [InstalledApplication] = []
  func applications() -> [InstalledApplication] {
    if !cached.isEmpty { return cached }
    let manager = FileManager.default
    let roots = [
      URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications"),
      manager.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
    ]
    var found: [String: InstalledApplication] = [:]
    for root in roots {
      guard
        let enumerator = manager.enumerator(
          at: root, includingPropertiesForKeys: [.isDirectoryKey],
          options: [.skipsHiddenFiles, .skipsPackageDescendants])
      else { continue }
      for case let url as URL in enumerator {
        if enumerator.level > 4 {
          enumerator.skipDescendants()
          continue
        }
        guard url.pathExtension == "app", let bundle = Bundle(url: url),
          let identifier = bundle.bundleIdentifier
        else { continue }
        let name =
          bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
          ?? url.deletingPathExtension().lastPathComponent
        found[identifier] = InstalledApplication(name: name, identifier: identifier, url: url)
      }
    }
    cached = Array(found.values)
    return cached
  }
  func resolve(_ requested: String) throws -> InstalledApplication {
    let aliases = [
      "settings": "system settings", "vs code": "visual studio code",
      "vscode": "visual studio code", "chrome": "google chrome", "app store": "app store",
    ]
    let normalized = TextNormalization.identity(requested)
    let key = aliases[normalized] ?? normalized
    let matches = applications().filter {
      [
        TextNormalization.identity($0.name),
        TextNormalization.identity($0.url.deletingPathExtension().lastPathComponent),
        TextNormalization.identity($0.identifier),
      ].contains(key)
    }
    guard matches.count == 1 else {
      if matches.isEmpty {
        if !key.isEmpty
          && applications().contains(where: {
            TextNormalization.identity($0.name).hasPrefix(key)
              || TextNormalization.identity($0.url.deletingPathExtension().lastPathComponent)
                .hasPrefix(key)
          })
        {
          throw PilotError.incompleteCommand
        }
        throw PilotError.unavailable(
          "No installed app matches that name. Say its exact Applications name.")
      }
      throw PilotError.unsafe("More than one app matches. Say its full name.")
    }
    return matches[0]
  }
}
actor MacExecutor {
  func launch(_ name: String, token: CancellationToken) async throws -> pid_t {
    try token.check()
    let app = try await ApplicationCatalog.shared.resolve(name)
    let config = NSWorkspace.OpenConfiguration()
    config.activates = true
    let application = try await NSWorkspace.shared.openApplication(
      at: app.url, configuration: config)
    try token.check()
    guard !application.isTerminated else {
      throw PilotError.unavailable("The application exited during launch.")
    }
    return application.processIdentifier
  }
  func openURL(_ text: String, token: CancellationToken) async throws {
    guard let url = SafeDesktopAction.webURL(text) else {
      throw PilotError.unsafe("Say a complete website address, such as example.com.")
    }
    try token.check()
    let opened = await MainActor.run { NSWorkspace.shared.open(url) }
    guard opened else { throw PilotError.unavailable("The website could not be opened.") }
  }
  func openPath(_ text: String, token: CancellationToken) async throws {
    let manager = FileManager.default
    let names = [
      "downloads": "Downloads", "documents": "Documents", "desktop": "Desktop",
      "applications": "Applications", "home": "",
    ]
    let key = TextNormalization.identity(text)
    let url: URL
    if let directory = names[key] {
      url = manager.homeDirectoryForCurrentUser.appendingPathComponent(directory)
    } else if text.hasPrefix("/") || text.hasPrefix("~/") {
      url = URL(fileURLWithPath: (text as NSString).expandingTildeInPath)
    } else {
      throw PilotError.unavailable(
        "Say Downloads, Documents, Desktop, Home, or an exact absolute file path.")
    }
    guard manager.fileExists(atPath: url.path) else {
      throw PilotError.unavailable("That file or folder does not exist.")
    }
    try token.check()
    guard await MainActor.run(body: { NSWorkspace.shared.open(url) }) else {
      throw PilotError.unavailable("The file or folder could not be opened.")
    }
  }
}
