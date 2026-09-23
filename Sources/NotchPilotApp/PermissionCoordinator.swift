import AppKit
import AVFoundation
import ApplicationServices
import NotchPilotCore

@MainActor final class PermissionCoordinator: ObservableObject {
    @Published var microphone = AVCaptureDevice.authorizationStatus(for: .audio)
    @Published var accessibility = AXIsProcessTrusted()
    @Published var speechStatus = "On-device assets not checked"
    func refresh() { microphone = AVCaptureDevice.authorizationStatus(for: .audio); accessibility = AXIsProcessTrusted() }
    func requestMicrophone() async { _ = await AVCaptureDevice.requestAccess(for: .audio); refresh() }
    func openAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        openPane("Privacy_Accessibility")
    }
    func openPane(_ anchor: String) { if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + anchor) { NSWorkspace.shared.open(url) } }
}
