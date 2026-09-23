import AppKit
import Carbon

@MainActor final class HotkeyManager {
  private var hotkey: EventHotKeyRef?
  private var escape: EventHotKeyRef?
  private var handler: EventHandlerRef?
  var onPress: (() -> Void)?
  var onRelease: (() -> Void)?
  var onCancel: (() -> Void)?
  init() {
    var types = [
      EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
      EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
    ]
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, data in
        guard let event, let data else { return OSStatus(eventNotHandledErr) }
        var id = EventHotKeyID()
        GetEventParameter(
          event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
          MemoryLayout<EventHotKeyID>.size, nil, &id)
        let manager = Unmanaged<HotkeyManager>.fromOpaque(data).takeUnretainedValue()
        let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
        MainActor.assumeIsolated {
          if id.id == 2 {
            if pressed { manager.onCancel?() }
          } else if pressed {
            manager.onPress?()
          } else {
            manager.onRelease?()
          }
        }
        return noErr
      }, 2, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
  }
  func register(code: UInt32, modifiers: UInt32) -> Bool {
    if let hotkey { UnregisterEventHotKey(hotkey) }
    hotkey = nil
    return RegisterEventHotKey(
      code, modifiers, EventHotKeyID(signature: 0x4E50_4C54, id: 1), GetApplicationEventTarget(), 0,
      &hotkey) == noErr
  }
  func enableEscape(_ enabled: Bool) {
    if let escape { UnregisterEventHotKey(escape) }
    escape = nil
    if enabled {
      RegisterEventHotKey(
        53, 0, EventHotKeyID(signature: 0x4E50_4C54, id: 2), GetApplicationEventTarget(), 0, &escape
      )
    }
  }
}
