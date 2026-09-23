import AppKit
import Carbon
import ServiceManagement
import SwiftUI

struct SettingsView: View {
  @ObservedObject var controller: AppController
  @ObservedObject var settings: LocalSettings
  @ObservedObject var permissions: PermissionCoordinator
  @ObservedObject var performance: PerformanceMonitor
  @State private var alias = ""
  @State private var exactName = ""
  @State private var recording = false
  @State private var loginEnabled = SMAppService.mainApp.status == .enabled
  var body: some View {
    TabView {
      Form {
        Section("Welcome to NotchPilot") {
          Text("Speak locally. Act deliberately.").font(.title2.bold())
          Text(
            "Audio and transcripts stay on this Mac. Dry Run enters a draft but never presses Send. Start with ‘open WhatsApp’. Press Escape at any time to cancel queued work."
          ).font(.callout)
        }
        Section("Permissions") {
          HStack {
            Text("Microphone: \(permissions.microphone == .authorized ? "Allowed" : "Needed")")
            Spacer()
            Button("Allow Microphone") { Task { await permissions.requestMicrophone() } }
          }
          Text("Used only while a listening session is active. Raw audio is never saved.").font(
            .caption)
          HStack {
            Text("Accessibility: \(permissions.accessibility ? "Allowed" : "Needed")")
            Spacer()
            Button("Open Accessibility Settings") { permissions.openAccessibility() }
          }
          Text(
            "Allows broad control of other apps. NotchPilot restricts this to supported actions and verifies the target before sending."
          ).font(.caption)
          Button("Refresh permission status") { permissions.refresh() }
        }
        Section("On-device speech") {
          TextField("Language identifier", text: $settings.language).accessibilityLabel(
            "Speech language identifier")
          Text("Examples: en-US, en-IN. Command grammar currently uses English.").font(.caption)
          Text(permissions.speechStatus).font(.caption)
          Button("Install / Prepare Speech Assets") { controller.installSpeech() }
          Text(
            "Apple may download language assets. Recognition runs locally; no cloud fallback is used."
          ).font(.caption)
        }
        Button("Finish onboarding") {
          UserDefaults.standard.set(true, forKey: "onboarded")
          NSApp.keyWindow?.close()
        }
        if !controller.notice.isEmpty {
          Text(controller.notice).foregroundStyle(.orange).font(.caption)
        }
      }.formStyle(.grouped).tabItem { Label("Setup", systemImage: "checkmark.shield") }
      Form {
        Section("Activation") {
          HStack {
            Text("Global shortcut")
            Spacer()
            HotkeyRecorder(
              code: $settings.hotkeyCode, modifiers: $settings.hotkeyModifiers,
              recording: $recording, changed: controller.applyHotkey
            ).frame(width: 230, height: 30)
          }
          Toggle("Hold to talk (release cancels pending actions)", isOn: $settings.holdToTalk)
          Toggle("Reduce animations", isOn: $settings.reducedAnimations)
          Toggle("Launch at login", isOn: $loginEnabled).onChange(of: loginEnabled) { _, enabled in
            do {
              if enabled {
                try SMAppService.mainApp.register()
              } else {
                try SMAppService.mainApp.unregister()
              }
            } catch {
              controller.notice =
                "Launch at login could not be updated. Install the app in Applications first."
              loginEnabled = SMAppService.mainApp.status == .enabled
            }
          }
          Stepper(
            "Clear transcript after \(Int(settings.retention)) seconds", value: $settings.retention,
            in: 5...120, step: 5)
        }
        Section("Safety") {
          Toggle("Dry Run — never send messages", isOn: $settings.dryRun)
          Toggle("Confirm every live send", isOn: $settings.confirmAll)
          Text(
            "Sensitive messages always require confirmation. Changes apply to the next listening session. Live testing is never enabled by scripts."
          ).font(.caption)
          if controller.confirmationNeeded {
            Button("Confirm the pending send") { controller.confirm() }.tint(.orange)
          }
        }
        Section("Resources") {
          Picker("Laya mode", selection: $settings.lowResource) {
            Text("Fast response (recommended)").tag(false)
            Text("Low resource").tag(true)
          }
          Text(performance.modelStatus).font(.caption)
          Text(
            "One checkpoint and one inference at a time. Known commands work even when Laya is unavailable."
          ).font(.caption)
        }
      }.formStyle(.grouped).tabItem { Label("General", systemImage: "slider.horizontal.3") }
      Form {
        Section("Private WhatsApp aliases") {
          Text(
            "Map a spoken name to a unique, exact WhatsApp display name. These mappings stay in local preferences."
          ).font(.caption)
          TextField("Spoken alias", text: $alias)
          TextField("Exact WhatsApp display name", text: $exactName)
          Button("Save alias") {
            let key = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = exactName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty && !value.isEmpty {
              settings.aliases[key] = value
              alias = ""
              exactName = ""
            }
          }
          ForEach(settings.aliases.keys.sorted(), id: \.self) { key in
            HStack {
              Text(key)
              Image(systemName: "arrow.right")
              Text(settings.aliases[key] ?? "")
              Spacer()
              Button("Remove") { settings.aliases.removeValue(forKey: key) }
            }
          }
        }
        Section("Supported commands") {
          Text(
            "Open WhatsApp, Safari, Notes, Finder, Calendar, Music, Calculator or System Settings.\n\nOpen WhatsApp, go to Mummy, type hi and send.\n\nType hi leaves a draft. ‘And send’ must be a separate trailing instruction. Escape cancels."
          )
          Button("Show synthetic demo") { controller.startDemo() }
        }
      }.formStyle(.grouped).tabItem { Label("Commands", systemImage: "text.bubble") }
      Form {
        Section("Local performance") {
          Text("Overlay submission: \(performance.hotkeyMilliseconds, specifier: "%.1f") ms")
          Text(
            "Latest parser and queue submission: \(performance.directMilliseconds, specifier: "%.1f") ms"
          )
          Text("Native resident memory: \(PerformanceMonitor.residentMB(), specifier: "%.1f") MB")
        }
        Section("Privacy-safe audit") {
          HStack {
            Button("Refresh") {
              Task { controller.diagnosticText = await controller.diagnostics.read() }
            }
            Button("Delete diagnostics") {
              Task {
                await controller.diagnostics.delete()
                controller.diagnosticText = ""
              }
            }
          }
          ScrollView {
            Text(
              controller.diagnosticText.isEmpty
                ? "No local action records." : controller.diagnosticText
            ).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(
              maxWidth: .infinity, alignment: .leading)
          }.frame(minHeight: 250)
        }
      }.formStyle(.grouped).tabItem { Label("Diagnostics", systemImage: "stethoscope") }
    }.padding(12).frame(minWidth: 560, minHeight: 620)
  }
}
struct HotkeyRecorder: NSViewRepresentable {
  @Binding var code: UInt32
  @Binding var modifiers: UInt32
  @Binding var recording: Bool
  let changed: () -> Void
  func makeNSView(context: Context) -> RecorderButton {
    let view = RecorderButton()
    updateNSView(view, context: context)
    return view
  }
  func updateNSView(_ view: RecorderButton, context: Context) {
    view.title =
      recording
      ? "Press a shortcut…"
      : (code == 49 && modifiers == UInt32(optionKey)
        ? "⌥ Space · Click to change" : "Shortcut \(code) · Click to change")
    view.onBegin = { recording = true }
    view.onKey = { event in
      if event.keyCode == 53 {
        recording = false
        return
      }
      let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      guard flags.contains(.option) || flags.contains(.control),
        !(event.keyCode == 49 && flags.contains(.command))
      else { return }
      code = UInt32(event.keyCode)
      modifiers =
        (flags.contains(.option) ? UInt32(optionKey) : 0)
        | (flags.contains(.control) ? UInt32(controlKey) : 0)
        | (flags.contains(.command) ? UInt32(cmdKey) : 0)
        | (flags.contains(.shift) ? UInt32(shiftKey) : 0)
      recording = false
      changed()
    }
  }
}
final class RecorderButton: NSButton {
  var onBegin: (() -> Void)?
  var onKey: ((NSEvent) -> Void)?
  override var acceptsFirstResponder: Bool { true }
  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    onBegin?()
  }
  override func keyDown(with event: NSEvent) {
    onKey?(event)
    window?.makeFirstResponder(nil)
  }
}
