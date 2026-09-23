import CoreGraphics
import Foundation

public struct DisplayLayout: Sendable {
  public var frame: CGRect
  public var visibleFrame: CGRect
  public var topInset: CGFloat
  public var leftAuxiliary: CGRect?
  public var rightAuxiliary: CGRect?
  public init(
    frame: CGRect, visibleFrame: CGRect, topInset: CGFloat = 0, leftAuxiliary: CGRect? = nil,
    rightAuxiliary: CGRect? = nil
  ) {
    self.frame = frame
    self.visibleFrame = visibleFrame
    self.topInset = topInset
    self.leftAuxiliary = leftAuxiliary
    self.rightAuxiliary = rightAuxiliary
  }
  public var housing: CGRect? {
    guard topInset > 0, let l = leftAuxiliary, let r = rightAuxiliary, r.minX > l.maxX else {
      return nil
    }
    return CGRect(x: l.maxX, y: frame.maxY - topInset, width: r.minX - l.maxX, height: topInset)
  }
  public func capsule(expanded: Bool) -> CGRect {
    let width = min(frame.width - 24, expanded ? 440 : max(190, (housing?.width ?? 180) + 24))
    let height: CGFloat = expanded ? 146 : 38
    // Stay below the menu bar: the camera housing itself cannot render pixels.
    let top = housing?.minY ?? visibleFrame.maxY - 6
    return CGRect(
      x: (housing?.midX ?? frame.midX) - width / 2, y: top - height, width: width, height: height)
  }
}
public enum OverlayState: String, Sendable {
  case idle, activating, listening, understanding, executing, success, needsConfirmation, cancelled,
    error
}
public enum PermissionState: String, Sendable { case unknown, denied, granted, restricted }
public struct PermissionSnapshot: Sendable {
  public var microphone: PermissionState
  public var accessibility: Bool
  public var canListen: Bool { microphone == .granted }
  public var canControl: Bool { canListen && accessibility }
  public init(microphone: PermissionState, accessibility: Bool) {
    self.microphone = microphone
    self.accessibility = accessibility
  }
}
