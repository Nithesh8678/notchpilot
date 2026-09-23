import AppKit
import NotchPilotCore
import SwiftUI

@MainActor final class OverlayModel: ObservableObject {
  @Published var state: OverlayState = .idle
  @Published var transcript = ""
  @Published var action = "Ready when you are"
  @Published var next = ""
  @Published var level: Float = 0
  @Published var reduceMotion = false
}
private final class OverlayPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}
@MainActor final class NotchOverlay {
  let model = OverlayModel()
  private let panel: NSPanel
  private var screenObserver: NSObjectProtocol?
  private var focusObserver: NSObjectProtocol?
  init() {
    panel = OverlayPanel(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    panel.level = .statusBar
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    panel.collectionBehavior = [
      .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
    ]
    panel.hidesOnDeactivate = false
    panel.ignoresMouseEvents = true
    panel.contentView = NSHostingView(rootView: OverlayView(model: model))
    screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [weak self] _ in MainActor.assumeIsolated { self?.reposition() } }
    focusObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { [weak self] _ in MainActor.assumeIsolated { self?.reposition() } }
  }
  func reposition() {
    // Main screen follows the key window; pointer screen is a fallback.
    guard
      let screen = NSScreen.main
        ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
    else { return }
    let layout = DisplayLayout(
      frame: screen.frame, visibleFrame: screen.visibleFrame, topInset: screen.safeAreaInsets.top,
      leftAuxiliary: screen.auxiliaryTopLeftArea, rightAuxiliary: screen.auxiliaryTopRightArea)
    panel.setFrame(layout.capsule(expanded: true), display: true)
  }
  func show(_ state: OverlayState, action: String) {
    model.reduceMotion =
      NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
      || UserDefaults.standard.bool(forKey: "reducedAnimations")
    model.state = state
    model.action = action
    let wasVisible = panel.isVisible
    reposition()
    let expanded = panel.frame
    if !wasVisible && !model.reduceMotion {
      panel.setFrame(
        NSRect(x: expanded.midX - 100, y: expanded.maxY - 38, width: 200, height: 38),
        display: false)
      panel.orderFrontRegardless()
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.16
        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
        panel.animator().setFrame(expanded, display: true)
      }
    } else {
      panel.orderFrontRegardless()
    }
  }
  func hide() {
    panel.orderOut(nil)
    model.level = 0
    model.state = .idle
  }
  var visible: Bool { panel.isVisible }
}
private struct OverlayView: View {
  @ObservedObject var model: OverlayModel
  var color: Color {
    switch model.state {
    case .error: return .red
    case .needsConfirmation: return .orange
    case .success: return .green
    default: return .cyan
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Image(systemName: model.state == .success ? "checkmark.circle.fill" : "waveform")
          .foregroundStyle(color)
        Text("NotchPilot").fontWeight(.semibold)
        Spacer()
        Text(
          model.state.rawValue == "needsConfirmation"
            ? "Confirm in menu" : model.state.rawValue.capitalized
        )
        .foregroundStyle(color).font(.caption)
      }
      Text(model.action).font(.system(size: 14, weight: .medium)).lineLimit(1)
      Text(model.transcript.isEmpty ? "Speak a command · Esc to cancel" : model.transcript)
        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
      HStack {
        Text(model.next).font(.caption2).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
        Spacer()
        if model.state == .listening {
          HStack(spacing: 3) {
            ForEach(0..<9) { i in
              Capsule().fill(color).frame(
                width: 3,
                height: CGFloat(3 + (model.reduceMotion ? 2 : model.level * Float(10 + i % 3 * 8))))
            }
          }.frame(height: 20).accessibilityLabel("Microphone level")
        }
      }
    }.padding(.horizontal, 22).padding(.vertical, 14).frame(
      maxWidth: .infinity, maxHeight: .infinity
    )
    .foregroundStyle(.white).background(
      .black,
      in: UnevenRoundedRectangle(
        topLeadingRadius: 12, bottomLeadingRadius: 28, bottomTrailingRadius: 28,
        topTrailingRadius: 12)
    )
    .overlay(
      UnevenRoundedRectangle(
        topLeadingRadius: 12, bottomLeadingRadius: 28, bottomTrailingRadius: 28,
        topTrailingRadius: 12
      ).strokeBorder(.white.opacity(0.12))
    )
    .accessibilityElement(children: .combine)
  }
}
