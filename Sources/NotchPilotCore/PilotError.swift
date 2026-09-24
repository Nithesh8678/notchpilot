import Foundation

public enum PilotError: Error, LocalizedError, Sendable {
  case unavailable(String)
  case unsafe(String)
  case cancelled, timeout, incompleteCommand
  public var errorDescription: String? {
    switch self {
    case .unavailable(let text), .unsafe(let text): return text
    case .cancelled: return "Cancelled"
    case .incompleteCommand: return "Waiting for the complete application name."
    case .timeout: return "The application did not respond in time. Try again."
    }
  }
}
