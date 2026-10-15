import Darwin
import Foundation
import Observation
import UIKit

@Observable @MainActor
final class BenchmarkModel {
    var status = "Prepare a synthetic corpus to load the real model."
    var stage = "idle"
    var isBusy = false
    var docCount = 0
    var currentMemoryMiB = 0.0
    var peakMemoryMiB = 0.0
    var modelMode = BenchmarkMode.textOnly
    var results: [BenchmarkHit] = []
    var report: BenchmarkReport?
    var error: String?
    var lastSearchMilliseconds: Double?
    let availableFullModel: Bool

    @ObservationIgnored private var runner: BenchmarkRunner?
    @ObservationIgnored private var sampler: MemorySampler?
    @ObservationIgnored private var configuredCorpusSize = 128
    @ObservationIgnored private var handledLaunch = false
    @ObservationIgnored private var pendingLaunch: Task<Void, Never>?
    @ObservationIgnored private var sceneState = "unknown"

    init() {
        let text = Self.bundledModel("embeddinggemma-2-Q8_0")
        let media = Self.bundledModel("mmproj-embeddinggemma-2-Q8_0")
        availableFullModel = media != nil
        let samples = MemorySampler { [weak self] sample, peak in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentMemoryMiB = sample.footprintMiB ?? 0
                self.peakMemoryMiB = peak
            }
        }
        sampler = samples
        samples.begin()
        guard let text else {
            error = "The pinned text model is missing from this app's Models bundle."
            status = "Model missing"
            return
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SearchBench", isDirectory: true)
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        runner = BenchmarkRunner(textModelURL: text, mediaModelURL: media, storage: support, reports: documents,
            sampler: samples) { [weak self] update in
                Task { @MainActor [weak self] in self?.apply(update) }
            }
    }

    func prepare(corpusSize: Int = 128, mode: BenchmarkMode = .textOnly) {
        guard !isBusy, let runner else { return }
        guard requireForeground(for: "preparing an index") else { return }
        configuredCorpusSize = corpusSize
        modelMode = mode
        startOperation("Preparing corpus", stage: "baseline")
        docCount = 0
        results = []
        let evidence = deviceEvidence()
        Task {
            do {
                report = try await runner.prepare(corpusSize: corpusSize, mode: mode,
                    runID: "prepare-" + UUID().uuidString, device: evidence)
                stage = "ready"
                status = "Ready · \(docCount) indexed records"
            } catch { record(error) }
            finishOperation()
        }
    }

    func search(query: String) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isBusy, !query.isEmpty, let runner else { return }
        guard requireForeground(for: "searching with the model") else { return }
        startOperation("Embedding query and searching locally", stage: "interactive-search")
        Task {
            do {
                let result = try await runner.search(query: query)
                results = result.hits
                lastSearchMilliseconds = result.milliseconds
                status = "\(results.count) results · \(String(format: "%.1f", result.milliseconds)) ms"
                stage = "ready"
            } catch { record(error) }
            finishOperation()
        }
    }

    func runBenchmark(corpusSize: Int? = nil, mode: BenchmarkMode? = nil, runID: String? = nil) {
        guard !isBusy, let runner else { return }
        guard requireForeground(for: "running a benchmark") else { return }
        let count = corpusSize ?? configuredCorpusSize
        let chosenMode = mode ?? modelMode
        configuredCorpusSize = count
        modelMode = chosenMode
        startOperation("Starting a fresh real-model benchmark", stage: "baseline")
        docCount = 0
        results = []
        let evidence = deviceEvidence()
        Task {
            do {
                report = try await runner.runBenchmark(corpusSize: count, mode: chosenMode,
                    runID: runID ?? UUID().uuidString, device: evidence)
                stage = "finished"
                let passed = report?.correctnessChecks.filter { $0.expectedInTopFive == true }.count ?? 0
                status = "Complete · \(passed)/8 fixtures in top 5 · model released"
            } catch { record(error) }
            finishOperation()
        }
    }

    func releaseModel() {
        guard !isBusy, let runner else { return }
        guard requireForeground(for: "releasing the model") else { return }
        startOperation("Releasing model memory", stage: "release")
        Task {
            await runner.releaseModel()
            status = "Model released; the next search reloads it."
            stage = "released"
            finishOperation()
        }
    }

    /// Device launch accepts --benchmark --mode text|full --corpus 128 --run-id token.
    func handleLaunchArguments() {
        guard !handledLaunch else { return }
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--benchmark") else {
            guard sceneState == "active", UIApplication.shared.applicationState == .active else { return }
            handledLaunch = true
            return
        }
        // A launch request may create an inactive/background process. Do not consume it until both the scene
        // and UIKit application are active; native Metal activation must start in the foreground.
        guard pendingLaunch == nil, !isBusy, runner != nil,
              requireForeground(for: "running the requested benchmark", automatic: true) else { return }
        func value(after key: String) -> String? {
            guard let index = args.firstIndex(of: key), index + 1 < args.count else { return nil }
            return args[index + 1]
        }
        let mode = value(after: "--mode").flatMap(BenchmarkMode.init(rawValue:)) ?? .textOnly
        let corpus = value(after: "--corpus").flatMap(Int.init) ?? 128
        let runID = value(after: "--run-id")
        status = "Waiting for a stable foreground before starting the benchmark."
        pendingLaunch = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(1500)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.pendingLaunch = nil
            guard self.requireForeground(for: "running the requested benchmark", automatic: true) else { return }
            self.handledLaunch = true
            guard !self.isBusy else { return }
            self.runBenchmark(corpusSize: corpus, mode: mode, runID: runID)
        }
    }

    func recordSceneState(_ value: String) {
        sceneState = value
        let actualState = Self.uiKitApplicationState()
        sampler?.setApplicationState(actualState)
        if value != "active" || actualState != "active" {
            pendingLaunch?.cancel()
            pendingLaunch = nil
        }
    }

    private func requireForeground(for operation: String, automatic: Bool = false) -> Bool {
        let actualState = Self.uiKitApplicationState()
        sampler?.setApplicationState(actualState)
        guard sceneState == "active", UIApplication.shared.applicationState == .active else {
            let reason = "Foreground required for \(operation); scene is \(sceneState), UIKit application is \(actualState)."
            status = automatic ? "Waiting for SearchBench to become active in the foreground." : "Foreground required"
            if !automatic { error = reason }
            print("SEARCHBENCH foreground-start-rejected: \(reason)")
            fflush(nil)
            return false
        }
        return true
    }

    private static func uiKitApplicationState() -> String {
        switch UIApplication.shared.applicationState {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown"
        }
    }

    private func startOperation(_ message: String, stage: String) {
        error = nil
        isBusy = true
        status = message
        self.stage = stage
        // Benchmarking stays in the foreground; the user can still intentionally background it.
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func finishOperation() {
        isBusy = false
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func record(_ failure: any Error) {
        error = failure.localizedDescription
        status = "Operation failed"
        stage = "failed"
    }

    private func apply(_ progress: BenchmarkProgress) {
        status = progress.status
        stage = progress.stage
        docCount = progress.documents
        results = progress.results
        if let report = progress.report {
            self.report = report
            if report.firstSearchMilliseconds > 0 { lastSearchMilliseconds = report.firstSearchMilliseconds }
        }
    }

    private static func bundledModel(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "gguf", subdirectory: "Models")
            ?? Bundle.main.url(forResource: name, withExtension: "gguf")
    }

    private func deviceEvidence() -> DeviceEvidence {
        var info = utsname()
        uname(&info)
        let capacity = MemoryLayout.size(ofValue: info.machine)
        let model = withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return DeviceEvidence(deviceName: UIDevice.current.name, hardwareModel: model,
            systemVersion: UIDevice.current.systemName + " " + UIDevice.current.systemVersion,
            appVersion: version + " (" + build + ")",
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            processorCount: ProcessInfo.processInfo.activeProcessorCount,
            initialThermalState: MemorySampler.thermalState(), initialApplicationState: Self.uiKitApplicationState())
    }
}
