import AppKit
import NotchPilotCore

actor MacExecutor {
    static let applications = ["whatsapp": "net.whatsapp.WhatsApp", "safari": "com.apple.Safari", "notes": "com.apple.Notes", "finder": "com.apple.finder", "calendar": "com.apple.iCal", "music": "com.apple.Music", "calculator": "com.apple.calculator", "system settings": "com.apple.systempreferences"]
    func launch(_ name: String, token: CancellationToken) async throws -> pid_t {
        try token.check()
        guard let bundle = Self.applications[TextNormalization.identity(name)] else { throw PilotError.unavailable("I can’t open that app yet. See supported apps in Settings.") }
        guard let url = await MainActor.run(body: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) }) else { throw PilotError.unavailable("\(name) is not installed. Install it, then try again.") }
        let config = NSWorkspace.OpenConfiguration(); config.activates = true
        let application = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
        try token.check()
        guard !application.isTerminated else { throw PilotError.unavailable("The application exited during launch.") }
        return application.processIdentifier
    }
}
