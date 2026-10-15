import Darwin
import Foundation
import LocalSearchKit

struct BenchmarkProgress: Sendable {
    var status: String
    var stage: String
    var documents: Int
    var results: [BenchmarkHit] = []
    var report: BenchmarkReport?
    var searchMilliseconds: Double?
}

private final class FactoryTiming: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0.0
    var milliseconds: Double { lock.withLock { value } }
    func record(_ milliseconds: Double) { lock.withLock { value = milliseconds } }
}

/// Inference and SQLite work stay on engine/runner actors, off the UI's actor.
actor BenchmarkRunner {
    private let textModelURL: URL
    private let mediaModelURL: URL?
    private let storage: URL
    private let reports: URL
    private let sampler: MemorySampler
    private let progress: @Sendable (BenchmarkProgress) -> Void
    private var engine: LocalSearchEngine?
    private var currentReport: BenchmarkReport?
    private var latestResults: [BenchmarkHit] = []

    init(textModelURL: URL, mediaModelURL: URL?, storage: URL, reports: URL,
         sampler: MemorySampler, progress: @escaping @Sendable (BenchmarkProgress) -> Void) {
        self.textModelURL = textModelURL
        self.mediaModelURL = mediaModelURL
        self.storage = storage
        self.reports = reports
        self.sampler = sampler
        self.progress = progress
    }

    func prepare(corpusSize: Int, mode: BenchmarkMode, runID: String, device: DeviceEvidence,
                 benchmark: Bool = false) async throws -> BenchmarkReport {
        guard [32, 128, 512].contains(corpusSize) else { throw BenchError("Choose a corpus of 32, 128, or 512 records.") }
        guard mode != .full || mediaModelURL != nil else { throw BenchError("The full model's vision/audio file is not bundled.") }
        await engine?.releaseModel()
        engine = nil
        latestResults = []
        sampler.end()
        try await Task.sleep(for: .milliseconds(200))
        sampler.configureActivationJournal(directory: reports, runID: runID, mode: mode)
        sampler.begin()
        var report = BenchmarkReport(runID: runID, startedAt: Date(), mode: mode, corpusSize: corpusSize, device: device)
        if mode == .full { report.modelFiles.append("mmproj-embeddinggemma-2-Q8_0.gguf") }
        let baseline = sampler.mark("baseline")
        report.baselineFootprintMiB = baseline.footprintMiB ?? 0
        report.notes.append("P50 and P95 use the nearest-rank convention, not an interpolated or averaged median. Memory sampling target is 100 ms, with 10 ms dispatch leeway.")
        report.notes.append("The kernel ledger lifetime footprint peak is recorded separately; it includes earlier work in this app process and cannot be reset per run.")
        report.notes.append("During model activation only, a utility queue atomically saves memory-latest.json every 500 ms with the latest 100 ms samples; periodic journal disk writes stop once activation completes.")
        try checkpoint(&report, stage: "baseline", status: "Fresh \(mode.title.lowercased()) run · \(corpusSize) records")
        do {
            let samples = sampler
            let native = LocalSearchEngine.nativeFactory(textModelURL: textModelURL,
                mediaModelURL: mode == .full ? mediaModelURL : nil,
                diagnostic: { phase in
                    samples.recordNativePhase(phase)
                    Self.emit(["event": "native-phase", "phase": phase,
                               "uptimeNanoseconds": String(BenchmarkClock.now())])
                })
            let timing = FactoryTiming()
            let factory: LocalSearchEmbedderFactory = {
                let start = BenchmarkClock.now()
                defer { timing.record(BenchmarkClock.milliseconds(since: start)) }
                return try native()
            }
            let directory = storage.appendingPathComponent("run-" + UUID().uuidString, isDirectory: true)
            let search = try LocalSearchEngine(indexDirectory: directory, embedderFactory: factory)
            engine = search
            try checkpoint(&report, stage: "loading", status: "Verifying weights, loading model, warming Metal pipelines")
            let activation = BenchmarkClock.now()
            // Even an empty semantic index embeds a query, triggering the lazy native factory.
            _ = try await search.search("warm up local semantic search", mode: .semantic, limit: 5, zGate: 0)
            report.setupQueryMilliseconds = BenchmarkClock.milliseconds(since: activation)
            report.coldLoadMilliseconds = timing.milliseconds
            report.modelFilesVerified = true
            try checkpoint(&report, stage: "loaded", status: "Model verified and loaded")
            await sampler.flushJournal()

            let documents = SyntheticCorpus.documents(count: corpusSize)
            try checkpoint(&report, stage: "indexing", status: "Embedding \(corpusSize) synthetic passages")
            let indexing = BenchmarkClock.now()
            // One atomic batch keeps index timing comparable across runs.
            try await search.add(documents)
            report.indexingMilliseconds = BenchmarkClock.milliseconds(since: indexing)
            report.indexMillisecondsPerDocument = report.indexingMilliseconds / Double(corpusSize)
            let statistics = try await search.statistics()
            report.indexedDocuments = statistics.documents
            report.indexedVectors = statistics.vectors
            guard statistics.documents == corpusSize, statistics.vectors == corpusSize else {
                throw BenchError("Expected \(corpusSize) real-model vectors; got \(statistics.vectors) vectors and \(statistics.documents) documents.")
            }
            if let identity = statistics.model {
                report.modelIdentity = ["model": identity.model, "revision": identity.revision,
                    "runtime": identity.runtime, "dtype": identity.dtype, "dimension": String(identity.dimension),
                    "textOnly": String(identity.textOnly)]
                guard identity.dimension == 768, identity.textOnly == (mode == .textOnly) else {
                    throw BenchError("The loaded model identity does not match the requested mode.")
                }
            } else { throw BenchError("The index has no model identity.") }
            try checkpoint(&report, stage: "indexed", status: "\(corpusSize) real-model vectors indexed")
            try checkpoint(&report, stage: "first-search", status: "Timing the first query after indexing")
            let first = try await query(SyntheticCorpus.fixtures[0].query, expectedID: "capacitor", engine: search)
            report.firstSearchMilliseconds = first.measurement.milliseconds
            latestResults = first.hits
            try checkpoint(&report, stage: "ready", status: "Ready · \(corpusSize) indexed records")
            if !benchmark {
                sampler.end()
                refreshMemory(&report)
                currentReport = report
                try save(report)
            }
            return report
        } catch {
            await engine?.releaseModel()
            report.error = String(describing: error)
            report.finishedAt = Date()
            sampler.end()
            try? checkpoint(&report, stage: "failed", status: "Run failed: \(error)")
            throw error
        }
    }

    func runBenchmark(corpusSize: Int, mode: BenchmarkMode, runID: String,
                      device: DeviceEvidence) async throws -> BenchmarkReport {
        var report = try await prepare(corpusSize: corpusSize, mode: mode, runID: runID, device: device, benchmark: true)
        guard let engine else { throw BenchError("Prepare an index first.") }
        do {
            try checkpoint(&report, stage: "correctness", status: "Checking 8 semantic fixture queries")
            for fixture in SyntheticCorpus.fixtures {
                let result = try await query(fixture.query, expectedID: fixture.id, engine: engine)
                report.correctnessChecks.append(result.measurement)
                latestResults = result.hits
            }
            try checkpoint(&report, stage: "unique-searches", status: "Timing 25 distinct query embeddings")
            for (index, fixture) in SyntheticCorpus.uniqueQueries.enumerated() {
                let result = try await query(fixture.0, expectedID: fixture.1, engine: engine)
                report.uniqueQuerySamples.append(result.measurement)
                latestResults = result.hits
                if (index + 1) % 5 == 0 {
                    report.uniqueQueries = LatencySummary(report.uniqueQuerySamples.map(\.milliseconds))
                    try checkpoint(&report, stage: "unique-searches", status: "Distinct queries \(index + 1) / 25")
                }
            }
            report.uniqueQueries = LatencySummary(report.uniqueQuerySamples.map(\.milliseconds))
            try checkpoint(&report, stage: "repeated-searches", status: "Timing 25 repeated inputs, without a query cache")
            for index in 0..<25 {
                let result = try await query(SyntheticCorpus.fixtures[0].query, expectedID: "capacitor", engine: engine)
                report.repeatedQuerySamples.append(result.measurement)
                latestResults = result.hits
                if (index + 1) % 5 == 0 {
                    report.repeatedQueries = LatencySummary(report.repeatedQuerySamples.map(\.milliseconds))
                    try checkpoint(&report, stage: "repeated-searches", status: "Repeated queries \(index + 1) / 25")
                }
            }
            report.repeatedQueries = LatencySummary(report.repeatedQuerySamples.map(\.milliseconds))
            try checkpoint(&report, stage: "release", status: "Releasing model and vector matrix")
            await engine.releaseModel()
            // Backend/Metal caches and SQLite stay alive. Observe the OS after a short settle.
            try await Task.sleep(for: .seconds(1))
            report.footprintAfterReleaseMiB = sampler.mark("released").footprintMiB
            report.finishedAt = Date()
            sampler.end()
            refreshMemory(&report)
            guard report.memorySnapshots.allSatisfy({ $0.applicationState == "active" }) else {
                throw BenchError("Search Bench left the foreground during this run. Keep it open until completion; these samples do not establish foreground search performance.")
            }
            report.completed = true
            let correctness = report.correctnessChecks.filter { $0.expectedInTopFive == true }.count
            try checkpoint(&report, stage: "finished", status: "Benchmark complete · \(correctness)/8 fixtures in top 5 · model released")
            Self.emit(["event": "benchmark-finished", "runID": report.runID, "mode": mode.rawValue,
                       "corpus": corpusSize, "uniqueP50ms": report.uniqueQueries.medianMilliseconds,
                       "uniqueP95ms": report.uniqueQueries.p95Milliseconds,
                       "repeatedP50ms": report.repeatedQueries.medianMilliseconds,
                       "sampledPeakMiB": report.sampledPeakFootprintMiB, "fixturesTop5": correctness])
            return report
        } catch {
            await engine.releaseModel()
            report.error = String(describing: error)
            report.finishedAt = Date()
            sampler.end()
            try? checkpoint(&report, stage: "failed", status: "Run failed: \(error)")
            throw error
        }
    }

    func search(query text: String) async throws -> (hits: [BenchmarkHit], milliseconds: Double) {
        guard let engine else { throw BenchError("Prepare a corpus first.") }
        sampler.begin()
        sampler.mark("interactive-search")
        let start = BenchmarkClock.now()
        defer { sampler.end() }
        let hits = try await engine.search(text, mode: .hybrid, limit: 5)
        let milliseconds = BenchmarkClock.milliseconds(since: start)
        latestResults = hits.map(Self.mapHit)
        Self.emit(["event": "interactive-search", "milliseconds": milliseconds, "results": hits.count])
        return (latestResults, milliseconds)
    }

    func releaseModel() async {
        sampler.begin()
        sampler.mark("release")
        await engine?.releaseModel()
        try? await Task.sleep(for: .seconds(1))
        sampler.mark("released")
        sampler.end()
    }

    private func query(_ text: String, expectedID: String?, engine: LocalSearchEngine) async throws
        -> (hits: [BenchmarkHit], measurement: QueryMeasurement) {
        let start = BenchmarkClock.now()
        let hits = try await engine.search(text, mode: .semantic, limit: 5, zGate: 0)
        let elapsed = BenchmarkClock.milliseconds(since: start)
        guard hits.allSatisfy({ $0.cosine?.isFinite == true && $0.score.isFinite }) else {
            throw BenchError("A semantic result has no finite cosine or score.")
        }
        return (hits.map(Self.mapHit), QueryMeasurement(query: text, expectedID: expectedID,
            milliseconds: elapsed, hitIDs: hits.map(\.id), topCosine: hits.first?.cosine))
    }

    private func checkpoint(_ report: inout BenchmarkReport, stage: String, status: String) throws {
        report.stage = stage
        sampler.mark(stage)
        refreshMemory(&report)
        currentReport = report
        try save(report)
        progress(BenchmarkProgress(status: status, stage: stage, documents: report.indexedDocuments,
            results: latestResults, report: report))
        Self.emit(["event": "benchmark-stage", "stage": stage, "runID": report.runID,
                   "mode": report.mode.rawValue, "documents": report.indexedDocuments,
                   "sampledPeakMiB": report.sampledPeakFootprintMiB])
    }

    private func refreshMemory(_ report: inout BenchmarkReport) {
        let evidence = sampler.evidence()
        report.memorySnapshots = evidence.snapshots
        report.sampledPeakFootprintMiB = evidence.peak
        report.sampledPeakDeltaMiB = max(0, evidence.peak - report.baselineFootprintMiB)
        report.kernelLifetimePeakFootprintMiB = evidence.snapshots.compactMap(\.kernelLifetimePeakFootprintMiB).max()
        if evidence.snapshots.allSatisfy({ $0.footprintMiB == nil }), !report.notes.contains("Memory readings unavailable.") {
            report.notes.append("Memory readings unavailable.")
        }
    }

    private func save(_ report: BenchmarkReport) throws {
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        let safeID = String(report.runID.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }.prefix(100))
        try data.write(to: reports.appendingPathComponent("benchmark-\(report.mode.rawValue)-\(safeID).json"), options: .atomic)
        try data.write(to: reports.appendingPathComponent("benchmark-latest.json"), options: .atomic)
    }

    private static func mapHit(_ hit: LocalSearchHit) -> BenchmarkHit {
        BenchmarkHit(id: hit.id, title: hit.title, excerpt: hit.excerpt ?? "", score: hit.score, cosine: hit.cosine)
    }

    private static func emit(_ value: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return }
        print("SEARCHBENCH " + text)
        fflush(nil)
    }
}

struct BenchError: Error, LocalizedError, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
