import AVFoundation
import Speech
import NotchPilotCore

struct SpeechUpdate: Sendable {
    let text: String
    let committed: String
    let isFinal: Bool
}
actor SpeechPipeline {
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var format: AVAudioFormat?
    private var language = ""
    private let capture = AudioCapture()
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var generation = UUID()
    func prepare(language: String, installAssets: Bool = false) async throws {
        guard analyzer == nil || self.language != language else { return }
        guard SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) else { throw PilotError.unavailable("This speech language is not available on this Mac.") }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults, .fastResults], attributeOptions: [])
        let status = await AssetInventory.status(forModules: [transcriber])
        if status != .installed {
            guard installAssets else { throw PilotError.unavailable("Install on-device speech in Settings before listening.") }
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) { try await request.downloadAndInstall() }
        }
        try Task.checkCancellation()
        let analyzer = SpeechAnalyzer(modules: [transcriber], options: .init(priority: .userInitiated, modelRetention: .lingering))
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else { throw PilotError.unavailable("No compatible on-device audio format.") }
        try await analyzer.prepareToAnalyze(in: format)
        self.language = language; self.transcriber = transcriber; self.analyzer = analyzer; self.format = format
    }
    func start(language: String, update: @escaping @Sendable (SpeechUpdate) -> Void, level: @escaping @Sendable (Float) -> Void, failure: @escaping @Sendable (String) -> Void) async throws {
        let session = UUID(); generation = session
        try await prepare(language: language)
        try Task.checkCancellation()
        guard generation == session, let transcriber, let analyzer, let format else { throw CancellationError() }
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingNewest(32))
        input = continuation
        resultsTask = Task {
            var committed = ""
            do {
                for try await result in transcriber.results {
                    try Task.checkCancellation()
                    let segment = String(result.text.characters)
                    if result.isFinal { committed += segment }
                    update(SpeechUpdate(text: result.isFinal ? committed : committed + segment, committed: committed, isFinal: result.isFinal))
                }
            } catch is CancellationError {} catch { failure("On-device recognition stopped. Start a new session.") }
        }
        try await analyzer.start(inputSequence: stream)
        try Task.checkCancellation()
        guard generation == session else { throw CancellationError() }
        try await capture.start(format: format, yield: { continuation.yield($0) }, level: level)
        if generation != session || Task.isCancelled { await capture.stop(); throw CancellationError() }
    }
    func cancel() async {
        generation = UUID()
        await capture.stop(); input?.finish(); input = nil
        resultsTask?.cancel(); resultsTask = nil
        let old = analyzer; analyzer = nil; transcriber = nil; format = nil
        await old?.cancelAndFinishNow()
    }
    func transcribeFixture(_ url: URL, language: String, update: @escaping @Sendable (SpeechUpdate) -> Void) async throws {
        try await prepare(language: language)
        guard let transcriber, let analyzer else { return }
        let task = Task {
            var committed = ""
            for try await result in transcriber.results {
                let segment = String(result.text.characters)
                if result.isFinal { committed += segment }
                update(SpeechUpdate(text: result.isFinal ? committed : committed + segment, committed: committed, isFinal: result.isFinal))
            }
        }
        let file = try AVAudioFile(forReading: url)
        try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
        try await task.value
        self.analyzer = nil; self.transcriber = nil
    }
}
