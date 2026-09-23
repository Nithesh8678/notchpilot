import AppKit
import Combine
import Carbon

@MainActor final class LocalSettings: ObservableObject {
    private let defaults = UserDefaults.standard
    @Published var hotkeyCode: UInt32 { didSet { defaults.set(hotkeyCode, forKey: "hotkeyCode") } }
    @Published var hotkeyModifiers: UInt32 { didSet { defaults.set(hotkeyModifiers, forKey: "hotkeyModifiers") } }
    @Published var holdToTalk: Bool { didSet { defaults.set(holdToTalk, forKey: "holdToTalk") } }
    @Published var dryRun: Bool { didSet { defaults.set(dryRun, forKey: "dryRun") } }
    @Published var lowResource: Bool { didSet { defaults.set(lowResource, forKey: "lowResource") } }
    @Published var reducedAnimations: Bool { didSet { defaults.set(reducedAnimations, forKey: "reducedAnimations") } }
    @Published var confirmAll: Bool { didSet { defaults.set(confirmAll, forKey: "confirmAll") } }
    @Published var language: String { didSet { defaults.set(language, forKey: "language") } }
    @Published var retention: Double { didSet { defaults.set(retention, forKey: "retention") } }
    @Published var aliases: [String: String] { didSet { defaults.set(aliases, forKey: "aliases") } }
    init() {
        defaults.register(defaults: ["hotkeyCode": 49, "hotkeyModifiers": optionKey, "dryRun": true, "language": "en-US", "retention": 30.0])
        hotkeyCode = UInt32(defaults.integer(forKey: "hotkeyCode")); hotkeyModifiers = UInt32(defaults.integer(forKey: "hotkeyModifiers"))
        holdToTalk = defaults.bool(forKey: "holdToTalk"); dryRun = defaults.bool(forKey: "dryRun")
        lowResource = defaults.bool(forKey: "lowResource"); reducedAnimations = defaults.bool(forKey: "reducedAnimations")
        confirmAll = defaults.bool(forKey: "confirmAll"); language = defaults.string(forKey: "language") ?? "en-US"
        retention = defaults.double(forKey: "retention"); aliases = defaults.dictionary(forKey: "aliases") as? [String: String] ?? [:]
    }
}
