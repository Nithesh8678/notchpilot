import AppKit
import ApplicationServices
import CoreAudio
import NotchPilotCore

/// General app control with exact semantic targets; messaging retains its verified adapter.
actor DesktopAdapter: ApplicationAdapter {
  private let executor = MacExecutor()
  private let whatsapp: WhatsAppAdapter
  private var targetPID: pid_t?
  private var isWhatsApp = false
  private var drafts: [Int: (AXUIElement, String)] = [:]
  init(aliases: [String: String]) { whatsapp = WhatsAppAdapter(aliases: aliases) }
  func reset() async {
    targetPID = nil
    drafts = [:]
    isWhatsApp = false
    await whatsapp.reset()
  }
  func execute(_ command: Command, token: CancellationToken, revision: Int, policy: SafetyPolicy)
    async throws -> String
  {
    try token.check(revision: revision)
    switch command.kind {
    case .openApp:
      if SafeDesktopAction.webURL(command.value) != nil {
        try await executor.openURL(command.value, token: token)
        targetPID = nil
        isWhatsApp = false
        return "success"
      }
      if ["downloads", "documents", "desktop", "home"].contains(
        TextNormalization.identity(command.value))
      {
        try await executor.openPath(command.value, token: token)
        targetPID = nil
        isWhatsApp = false
        return "success"
      }
      isWhatsApp = TextNormalization.identity(command.value) == "whatsapp"
      if isWhatsApp {
        let result = try await whatsapp.execute(
          command, token: token, revision: revision, policy: policy)
        targetPID = await MainActor.run {
          NSWorkspace.shared.frontmostApplication?.processIdentifier
        }
        return result
      }
      targetPID = try await executor.launch(command.value, token: token)
      return "success"
    case .openURL:
      try await executor.openURL(command.value, token: token)
      targetPID = nil
      isWhatsApp = false
      return "success"
    case .openPath:
      try await executor.openPath(command.value, token: token)
      targetPID = nil
      isWhatsApp = false
      return "success"
    case .volume:
      try VolumeControl.perform(command.value, token: token)
      return "success"
    case .contact, .send:
      if isWhatsApp {
        return try await whatsapp.execute(command, token: token, revision: revision, policy: policy)
      }
      if command.kind == .contact, SafeDesktopAction.webURL(command.value) != nil {
        try await executor.openURL(command.value, token: token)
        return "success"
      }
      throw PilotError.unsafe(
        "Sending and recipient selection require a supported messaging adapter. General controls cannot send messages."
      )
    case .typeText:
      if isWhatsApp {
        return try await whatsapp.execute(command, token: token, revision: revision, policy: policy)
      }
      let client = try await activeClient()
      guard let focused = client.focusedNode(),
        [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(focused.role),
        client.string(focused.element, kAXSubroleAttribute) != kAXSecureTextFieldSubrole
      else {
        throw PilotError.unsafe("Focus an editable, non-password field before saying ‘type’.")
      }
      if let previous = drafts[command.id], !CFEqual(previous.0, focused.element) {
        throw PilotError.unsafe("The focused field changed. Start a new command.")
      }
      guard !command.value.contains("\n"), !command.value.contains("\r") else {
        throw PilotError.unsafe("Multiline keyboard dictation is not supported in generic fields.")
      }
      try client.setText(
        focused, text: command.value, previous: drafts[command.id]?.1, token: token,
        revision: revision)
      try await client.wait(token: token, revision: revision, timeout: 3) {
        client.string(focused.element, kAXValueAttribute) == command.value
      }
      drafts[command.id] = (focused.element, command.value)
      return "success"
    case .click, .media:
      let client = try await activeClient()
      let aliases = ["resume": "play", "next track": "next", "previous track": "previous"]
      let label = aliases[TextNormalization.identity(command.value)] ?? command.value
      guard !SafeDesktopAction.prohibitedControl(label) else {
        throw PilotError.unsafe(
          "That control can commit a sensitive action. Use the app directly or a supported verified adapter."
        )
      }
      let matches = client.search { node in
        [
          kAXButtonRole, kAXMenuItemRole, kAXCheckBoxRole, kAXRadioButtonRole,
          kAXPopUpButtonRole,
        ].contains(node.role)
          && node.names.contains {
            TextNormalization.identity($0) == TextNormalization.identity(label)
          }
          && !node.names.contains(where: SafeDesktopAction.prohibitedControl)
          && client.attribute(node.element, kAXEnabledAttribute) as? Bool != false
      }
      guard matches.count == 1 else {
        throw PilotError.unavailable(
          matches.isEmpty
            ? "No accessible control matches that name. Say its exact visible label."
            : "Several controls have that label. No click was made.")
      }
      try client.press(matches[0], token: token, revision: revision)
      // AXPress acknowledgement establishes dispatch, not completion of an unknown app's operation.
      return "dispatched"
    case .search:
      let client = try await activeClient()
      let matches = client.search { node in
        [kAXTextFieldRole, kAXComboBoxRole].contains(node.role)
          && (client.string(node.element, kAXSubroleAttribute) == kAXSearchFieldSubrole
            || node.names.contains { TextNormalization.identity($0) == "search" })
      }
      guard matches.count == 1 else {
        throw PilotError.unavailable("Focus or reveal a unique Search field in this app first.")
      }
      let field = matches[0]
      try client.setText(
        field, text: command.value, previous: client.string(field.element, kAXValueAttribute),
        token: token, revision: revision)
      try await client.wait(token: token, revision: revision, timeout: 3) {
        client.string(field.element, kAXValueAttribute) == command.value
      }
      return "success"
    case .scroll:
      let client = try await activeClient()
      guard let direction = SafeDesktopAction.scrollDirection(command.value) else {
        throw PilotError.unavailable("Say scroll up, down, left, or right.")
      }
      try token.check(revision: revision)
      guard
        let event = CGEvent(
          scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
          wheel1: direction.horizontal ? 0 : direction.amount,
          wheel2: direction.horizontal ? direction.amount : 0, wheel3: 0)
      else { throw PilotError.unavailable("Scrolling is unavailable.") }
      event.postToPid(client.pid)
      return "dispatched"
    case .key:
      let client = try await activeClient()
      let keys: [String: (CGKeyCode, CGEventFlags)] = [
        "new tab": (17, .maskCommand), "new window": (45, .maskCommand),
        "copy": (8, .maskCommand), "paste": (9, .maskCommand), "undo": (6, .maskCommand),
        "redo": (6, [.maskCommand, .maskShift]), "select all": (0, .maskCommand),
        "back": (33, .maskCommand), "forward": (30, .maskCommand),
        "reload": (15, .maskCommand), "refresh": (15, .maskCommand),
        "tab": (48, []), "escape": (53, []), "command f": (3, .maskCommand),
      ]
      guard let key = keys[TextNormalization.identity(command.value)] else {
        throw PilotError.unsafe(
          "That key action is not supported. Return and destructive shortcuts are not automated.")
      }
      if ["paste", "copy", "select all"].contains(TextNormalization.identity(command.value)) {
        guard let field = client.focusedNode(),
          [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(field.role),
          client.string(field.element, kAXSubroleAttribute) != kAXSecureTextFieldSubrole
        else { throw PilotError.unsafe("Focus a non-password text field for this shortcut.") }
      }
      try client.key(key.0, flags: key.1, token: token, revision: revision)
      return "dispatched"
    case .window:
      let client = try await activeClient()
      guard let window = client.windows().first else {
        throw PilotError.unavailable("No app window is available.")
      }
      let name = TextNormalization.identity(command.value)
      if name == "minimize" {
        try token.check(revision: revision)
        guard
          AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            == .success
        else { throw PilotError.unavailable("This window cannot be minimized.") }
        try await client.wait(token: token, revision: revision) {
          client.attribute(window, kAXMinimizedAttribute) as? Bool == true
        }
        return "success"
      }
      guard name == "maximize", let zoom = client.attribute(window, kAXZoomButtonAttribute),
        CFGetTypeID(zoom) == AXUIElementGetTypeID()
      else { throw PilotError.unavailable("This window does not expose a zoom control.") }
      try client.press(
        client.node(unsafeBitCast(zoom, to: AXUIElement.self)), token: token, revision: revision)
      return "dispatched"
    case .cancel: throw PilotError.cancelled
    case .unsupported: throw PilotError.unavailable("I can’t do that yet.")
    }
  }
  private func activeClient() async throws -> AccessibilityClient {
    let front = await MainActor.run { NSWorkspace.shared.frontmostApplication }
    guard let front, front.bundleIdentifier != Bundle.main.bundleIdentifier else {
      throw PilotError.unavailable("Focus the app you want to control first.")
    }
    guard
      ![
        "com.apple.Terminal", "com.googlecode.iterm2", "com.agilebits.onepassword7",
        "com.1password.1password", "com.apple.Passwords", "com.apple.systempreferences",
      ].contains(front.bundleIdentifier ?? "")
    else {
      throw PilotError.unsafe(
        "Terminal, password managers, and security settings require direct interaction.")
    }
    if let targetPID, front.processIdentifier != targetPID {
      throw PilotError.unsafe("The target app lost focus. Start a new command in the intended app.")
    }
    return try AccessibilityClient(pid: front.processIdentifier)
  }
}

private enum VolumeControl {
  static func perform(_ instruction: String, token: CancellationToken) throws {
    var device = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    guard
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr
    else { throw PilotError.unavailable("No audio output device is available.") }
    let text = TextNormalization.identity(instruction)
    let mute = text == "mute" || text == "unmute"
    let selector = mute ? kAudioDevicePropertyMute : kAudioDevicePropertyVolumeScalar
    var elements: [AudioObjectPropertyElement] = [kAudioObjectPropertyElementMain]
    func writable(_ element: AudioObjectPropertyElement) -> Bool {
      var property = AudioObjectPropertyAddress(
        mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
      var settable = DarwinBoolean(false)
      return AudioObjectIsPropertySettable(device, &property, &settable) == noErr
        && settable.boolValue
    }
    if !writable(kAudioObjectPropertyElementMain) {
      var stereo: [UInt32] = [1, 2]
      var stereoAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyPreferredChannelsForStereo,
        mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
      var stereoSize = UInt32(MemoryLayout<UInt32>.size * 2)
      _ = AudioObjectGetPropertyData(device, &stereoAddress, 0, nil, &stereoSize, &stereo)
      elements = stereo.filter { writable($0) }
    }
    guard !elements.isEmpty else {
      throw PilotError.unavailable("This output device manages volume externally.")
    }
    for element in elements {
      try token.check()
      address = AudioObjectPropertyAddress(
        mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
      if mute {
        var value: UInt32 = text == "mute" ? 1 : 0
        guard
          AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout.size(ofValue: value)), &value) == noErr
        else { throw PilotError.unavailable("Mute could not be changed.") }
      } else {
        var current: Float32 = 0
        size = UInt32(MemoryLayout.size(ofValue: current))
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &current) == noErr else {
          throw PilotError.unavailable("Volume could not be read.")
        }
        var output: Float32
        if ["volume up", "increase volume"].contains(text) {
          output = min(1, current + 0.1)
        } else if ["volume down", "decrease volume"].contains(text) {
          output = max(0, current - 0.1)
        } else if let percentage = Float32(
          text.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "percent", with: "")
            .trimmingCharacters(in: .whitespaces)), (0...100).contains(percentage)
        {
          output = percentage / 100
        } else {
          throw PilotError.unavailable("Say set volume to a number from zero to one hundred.")
        }
        guard AudioObjectSetPropertyData(device, &address, 0, nil, size, &output) == noErr else {
          throw PilotError.unavailable("Volume could not be changed.")
        }
        var readback: Float32 = 0
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &readback) == noErr,
          abs(readback - output) < 0.02
        else { throw PilotError.unavailable("The audio device did not confirm the volume change.") }
      }
    }
  }
}
