import CoreGraphics
import Foundation
import Testing

@testable import NotchPilotCore

@Test func displayGeometry() {
  let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
  let notch = DisplayLayout(
    frame: frame, visibleFrame: CGRect(x: 0, y: 32, width: 1512, height: 918), topInset: 32,
    leftAuxiliary: CGRect(x: 0, y: 950, width: 660, height: 32),
    rightAuxiliary: CGRect(x: 852, y: 950, width: 660, height: 32))
  #expect(notch.housing?.width == 192)
  #expect(notch.capsule(expanded: true).maxY == 950)
  let external = DisplayLayout(
    frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
    visibleFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1055))
  #expect(external.housing == nil)
  #expect(external.capsule(expanded: true).midX == -960)
  #expect(external.capsule(expanded: true).maxY < 1055)
}
@Test func deniedPermissionsAreSafe() {
  #expect(!PermissionSnapshot(microphone: .denied, accessibility: false).canControl)
  #expect(PermissionSnapshot(microphone: .granted, accessibility: false).canListen)
}
