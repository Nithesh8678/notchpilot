import Foundation

public enum PilotError: Error, LocalizedError, Sendable {
  case unavailable(String)
  case unsafe(String)
  case cancelled, timeout
  public var errorDescription: String? {
    switch self {
    case .unavailable(let text), .unsafe(let text): return text
    case .cancelled: return "Cancelled"
    case .timeout: return "The application did not respond in time. Try again."
    }
  }
}
