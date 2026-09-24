import Foundation

public enum SafeDesktopAction {
  public static func webURL(_ text: String) -> URL? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.contains(where: { $0.isWhitespace }), trimmed.contains(".") else { return nil }
    let candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed
    guard let url = URL(string: candidate),
      ["https", "http"].contains(url.scheme?.lowercased() ?? ""), let host = url.host,
      host.contains("."), url.user == nil, url.password == nil
    else { return nil }
    return url
  }
  public static func prohibitedControl(_ name: String) -> Bool {
    let value = TextNormalization.identity(name)
    return value.range(
      of:
        #"\b(send|submit|delete|remove|erase|trash|buy|purchase|pay|transfer|checkout|publish|post|password|passcode|unlock|authorize|approve|allow|install|grant|confirm|sign out|log out|ok|yes|continue|proceed|done)\b"#,
      options: .regularExpression) != nil
  }
  public static func scrollDirection(_ text: String) -> (horizontal: Bool, amount: Int32)? {
    switch TextNormalization.identity(text) {
    case "down": return (false, -5)
    case "up": return (false, 5)
    case "left": return (true, 5)
    case "right": return (true, -5)
    default: return nil
    }
  }
}
