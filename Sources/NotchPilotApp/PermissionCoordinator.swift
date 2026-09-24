import AVFoundation
import AppKit
import ApplicationServices
import NotchPilotCore

@MainActor final class PermissionCoordinator: ObservableObject {
  @Published var microphone = AVCaptureDevice.authorizationStatus(for: .audio)
  @Published var accessibility = AXIsProcessTrusted()
  @Published var speechStatus = "On-device assets not checked"
  func refresh() {
    microphone = AVCaptureDevice.authorizationStatus(for: .audio)
    accessibility = AXIsProcessTrusted()
    if accessibility { repairStatus = "Accessibility is enabled for this build." }
  }
  func requestMicrophone() async {
    if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
      _ = await AVCaptureDevice.requestAccess(for: .audio)
    } else if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
      openPane("Privacy_Microphone")
    }
    refresh()
  }
  @Published var repairStatus = ""
  func repairAccessibility() async {
    repairStatus = "Removing only NotchPilot’s stale approval…"
    let success = await Task.detached(priority: .utility) {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
      process.arguments = ["reset", "Accessibility", "org.notchpilot.app"]
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
      do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
      } catch { return false }
    }.value
    repairStatus =
      success
      ? "Enable the newly listed NotchPilot entry. This reset affects no other app."
      : "Remove NotchPilot with the minus button in Accessibility, then add the installed app again."
    openAccessibility()
    refresh()
  }
  func openAccessibility() {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    openPane("Privacy_Accessibility")
  }
  func openPane(_ anchor: String) {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + anchor) {
      NSWorkspace.shared.open(url)
    }
  }
}
