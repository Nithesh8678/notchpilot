import Foundation

public enum CommandKind: String, Codable, Sendable {
  case openApp, contact, typeText, send, cancel, unsupported
}
public struct Command: Equatable, Sendable {
  public let id: Int
  public let kind: CommandKind
  public let value: String
  public let endOffset: Int
  public init(id: Int, kind: CommandKind, value: String, endOffset: Int) {
    self.id = id
    self.kind = kind
    self.value = value
    self.endOffset = endOffset
  }
  public var auditName: String { kind.rawValue }
}
public enum TextNormalization {
  public static func identity(_ text: String) -> String {
    text.replacingOccurrences(
      of: "[\\u200E\\u200F\\u202A-\\u202E\\u2066-\\u2069]", with: "", options: .regularExpression
    ).folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")
    )
    .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
  }
}
/// Deliberately narrow grammar. Dictation is opaque except an explicit terminal send clause.
public struct StreamingCommandParser: Sendable {
  public init() {}
  public func parse(_ text: String) -> [Command] {
    let source = text as NSString
    let pattern =
      #"(?i)(?:^\s*(?:please\s+)?|[,;]\s*(?:(?:and|then|after that)\s+)?|\s+(?:and|then|after that)\s+)(open|launch|focus|go to|type|say|send|cancel)\b\s*"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
    var commands: [Command] = []
    for (index, match) in matches.enumerated() {
      let verb = source.substring(with: match.range(at: 1)).lowercased()
      let start = NSMaxRange(match.range)
      let next = index + 1 < matches.count ? matches[index + 1].range.location : source.length
      let kind: CommandKind
      switch verb {
      case "open", "launch", "focus": kind = .openApp
      case "go to": kind = .contact
      case "type", "say": kind = .typeText
      case "send": kind = .send
      case "cancel": kind = .cancel
      default: kind = .unsupported
      }
      if kind == .typeText {
        let remainder = source.substring(from: start)
        let sendRegex = try! NSRegularExpression(
          pattern: #"(?i)(?:,\s*|\s+)(?:and\s+|then\s+|after that\s+)send[.!?]?\s*$"#)
        let send = sendRegex.firstMatch(
          in: remainder, range: NSRange(location: 0, length: (remainder as NSString).length))
        let body =
          send.map { (remainder as NSString).substring(to: $0.range.location) } ?? remainder
        let value = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
          commands.append(
            Command(
              id: commands.count, kind: .typeText, value: value,
              endOffset: start + (body as NSString).length))
        }
        if send != nil {
          commands.append(
            Command(id: commands.count, kind: .send, value: "", endOffset: source.length))
        }
        return commands
      }
      let value = source.substring(with: NSRange(location: start, length: next - start))
        .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".!?")))
      if kind == .send || kind == .cancel {
        // Reject e.g. "send money" and "send later" as unsupported commands.
        if value.isEmpty {
          commands.append(Command(id: commands.count, kind: kind, value: "", endOffset: next))
        }
      } else if !value.isEmpty {
        commands.append(Command(id: commands.count, kind: kind, value: value, endOffset: next))
      }
    }
    return commands
  }
}

public struct TranscriptStability: Sendable {
  private var previous = ""
  private var firstSeen: [TimeInterval] = []
  public private(set) var volatile = ""
  public private(set) var committedPrefix = ""
  public init() {}
  public mutating func update(text: String, committed: String, now: TimeInterval) -> Int {
    volatile = text
    committedPrefix = committed
    let a = Array(previous.utf16)
    let b = Array(text.utf16)
    var common = 0
    while common < min(a.count, b.count), a[common] == b[common] { common += 1 }
    firstSeen = Array(firstSeen.prefix(common)) + Array(repeating: now, count: b.count - common)
    var stable = 0
    while stable < common, now - firstSeen[stable] >= 0.15 { stable += 1 }
    previous = text
    return max((committed as NSString).length, stable)
  }
}
