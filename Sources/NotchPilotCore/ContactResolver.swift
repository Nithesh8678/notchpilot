import Foundation

public enum ContactResolver {
  public static func resolve(_ spoken: String, aliases: [String: String]) -> String {
    aliases.first { TextNormalization.identity($0.key) == TextNormalization.identity(spoken) }?
      .value ?? spoken
  }
  public static func exactIndex(target: String, candidates: [String]) throws -> Int {
    let matches = candidates.indices.filter {
      TextNormalization.identity(candidates[$0]) == TextNormalization.identity(target)
    }
    guard matches.count == 1 else {
      throw PilotError.unsafe(
        matches.isEmpty
          ? "No exact conversation found. Check the name or add an alias in Settings."
          : "Multiple conversations match. Use a unique name; nothing was sent.")
    }
    return matches[0]
  }
}
