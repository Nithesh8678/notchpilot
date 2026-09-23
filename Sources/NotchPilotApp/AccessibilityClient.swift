import AppKit
import ApplicationServices
import NotchPilotCore

struct AXNode {
    let element: AXUIElement
    let role: String
    let title: String
    let label: String
    let identifier: String
    var names: [String] { [title, label].filter { !$0.isEmpty } }
}
/// Bounded searches, no coordinates and no stored snapshots. Call only off the main actor.
final class AccessibilityClient: @unchecked Sendable {
    let app: AXUIElement
    let pid: pid_t
    private var observer: AXObserver?
    private let signal = DispatchSemaphore(value: 0)
    init(pid: pid_t) throws {
        guard AXIsProcessTrusted() else { throw PilotError.unavailable("Allow NotchPilot in System Settings → Privacy & Security → Accessibility.") }
        self.pid = pid; self.app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var observer: AXObserver?
        if AXObserverCreate(pid, { _, _, _, ref in
            if let ref { Unmanaged<AccessibilityClient>.fromOpaque(ref).takeUnretainedValue().signal.signal() }
        }, &observer) == .success, let observer {
            self.observer = observer
            for name in [kAXWindowCreatedNotification, kAXFocusedUIElementChangedNotification, kAXValueChangedNotification, kAXLayoutChangedNotification] {
                AXObserverAddNotification(observer, app, name as CFString, Unmanaged.passUnretained(self).toOpaque())
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
    }
    deinit { if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) } }
    func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }
    func string(_ element: AXUIElement, _ key: String) -> String { attribute(element, key) as? String ?? "" }
    func node(_ element: AXUIElement) -> AXNode {
        AXNode(element: element, role: string(element, kAXRoleAttribute), title: string(element, kAXTitleAttribute), label: string(element, kAXDescriptionAttribute), identifier: string(element, kAXIdentifierAttribute))
    }
    func children(_ element: AXUIElement) -> [AXUIElement] { attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
    func windows() -> [AXUIElement] { attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] }
    func search(root: AXUIElement? = nil, includeChatList: Bool = false, includeMessages: Bool = false, matching: (AXNode) -> Bool) -> [AXNode] {
        var queue: [(AXUIElement, Int)] = [(root ?? app, 0)], offset = 0, matches: [AXNode] = []
        let deadline = Date().addingTimeInterval(0.5)
        while offset < queue.count, offset < 600, Date() < deadline {
            let (element, depth) = queue[offset]; offset += 1
            let item = node(element)
            if matching(item) { matches.append(item) }
            guard depth < 16 else { continue }
            if !includeChatList && item.identifier == "ChatListView_TableView" { continue }
            if !includeMessages && item.identifier == "ChatMessagesTableView" { continue }
            queue.append(contentsOf: children(element).map { ($0, depth + 1) })
        }
        return matches
    }
    func unique(identifier: String, root: AXUIElement? = nil) throws -> AXNode {
        let matches = search(root: root) { $0.identifier == identifier }
        guard matches.count == 1 else { throw PilotError.unavailable("WhatsApp's interface changed or is not ready. No action was taken.") }
        return matches[0]
    }
    func wait(token: CancellationToken, revision: Int? = nil, timeout: TimeInterval = 10, until condition: () throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            try token.check(revision: revision); try Task.checkCancellation()
            if try condition() { return }
            // Observer wakes promptly; timeout covers apps that omit notifications.
            _ = await Task.detached(priority: .utility) { [signal] in signal.wait(timeout: .now() + 0.2) }.value
        } while Date() < deadline
        throw PilotError.timeout
    }
    func press(_ node: AXNode, token: CancellationToken, revision: Int) throws {
        try token.check(revision: revision)
        guard AXUIElementPerformAction(node.element, kAXPressAction as CFString) == .success else { throw PilotError.unavailable("This control does not expose a supported press action.") }
    }
    func setText(_ node: AXNode, text: String, previous: String? = nil, token: CancellationToken, revision: Int) throws {
        try token.check(revision: revision)
        let old = string(node.element, kAXValueAttribute)
        guard old.isEmpty || old == previous || old == text else { throw PilotError.unsafe("The field already contains text. Clear it yourself before continuing.") }
        if old == text { return }
        if AXUIElementSetAttributeValue(node.element, kAXValueAttribute as CFString, text as CFString) == .success,
           string(node.element, kAXValueAttribute) == text { return }
        // Verified keyboard fallback: exact AX focus and target process are required.
        guard AXUIElementSetAttributeValue(node.element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success,
              let focused = attribute(app, kAXFocusedUIElementAttribute), CFEqual(focused, node.element) else { throw PilotError.unavailable("This field cannot be edited safely through Accessibility.") }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { throw PilotError.unsafe("WhatsApp lost focus. No text was entered.") }
        try token.check(revision: revision)
        if !old.isEmpty { try key(0, flags: .maskCommand, token: token, revision: revision) }
        let units = Array(text.utf16)
        for start in stride(from: 0, to: units.count, by: 16) {
            try token.check(revision: revision)
            let part = Array(units[start..<min(start + 16, units.count)])
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true), let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { throw PilotError.unavailable("Keyboard input unavailable.") }
            part.withUnsafeBufferPointer { pointer in
                down.keyboardSetUnicodeString(stringLength: part.count, unicodeString: pointer.baseAddress)
                up.keyboardSetUnicodeString(stringLength: part.count, unicodeString: pointer.baseAddress)
            }
            down.postToPid(pid); up.postToPid(pid)
        }
    }
    func key(_ code: CGKeyCode, flags: CGEventFlags = [], token: CancellationToken, revision: Int) throws {
        try token.check(revision: revision)
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { throw PilotError.unsafe("WhatsApp lost focus.") }
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true), let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else { return }
        down.flags = flags; up.flags = flags; down.postToPid(pid); up.postToPid(pid)
    }
}
