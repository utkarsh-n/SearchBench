import Foundation

enum BenchmarkMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case textOnly = "text"
    case full
    var id: String { rawValue }
    var title: String { self == .textOnly ? "Text only" : "Full model" }
    var modelFileBytes: Int64 { self == .textOnly ? 309_855_456 : 864_676_480 }
}

struct BenchmarkHit: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let excerpt: String
    let score: Double
    let cosine: Double?
}

/// Nearest-rank percentiles; each value is complete engine.search wall time.
struct LatencySummary: Codable, Sendable {
    let count: Int
    let medianMilliseconds: Double
    let p95Milliseconds: Double
    let minMilliseconds: Double
    let maxMilliseconds: Double
    let meanMilliseconds: Double

    init(_ milliseconds: [Double] = []) {
        let values = milliseconds.filter { $0.isFinite && $0 >= 0 }.sorted()
        count = values.count
        guard !values.isEmpty else {
            medianMilliseconds = 0; p95Milliseconds = 0
            minMilliseconds = 0; maxMilliseconds = 0; meanMilliseconds = 0
            return
        }
        medianMilliseconds = values[max(0, Int(ceil(Double(values.count) * 0.5)) - 1)]
        p95Milliseconds = values[max(0, Int(ceil(Double(values.count) * 0.95)) - 1)]
        minMilliseconds = values[0]
        maxMilliseconds = values[values.count - 1]
        meanMilliseconds = values.reduce(0, +) / Double(values.count)
    }
}

struct MemorySnapshot: Codable, Identifiable, Sendable {
    let id: Int
    let secondsFromStart: Double
    let stage: String
    /// TASK_VM_INFO.phys_footprint, the ledger used for device memory accounting.
    let footprintMiB: Double?
    /// MACH_TASK_BASIC_INFO.resident_size; differs from phys_footprint.
    let residentMiB: Double?
    /// Kernel ledger high-water since process launch; cannot be reset for a run.
    let kernelLifetimePeakFootprintMiB: Double?
    let thermalState: String
    let applicationState: String
}

struct QueryMeasurement: Codable, Sendable {
    let query: String
    let expectedID: String?
    let milliseconds: Double
    let hitIDs: [String]
    let topCosine: Double?
    var expectedInTopFive: Bool? { expectedID.map { hitIDs.prefix(5).contains($0) } }
    var expectedAtRankOne: Bool? { expectedID.map { hitIDs.first == $0 } }
}

struct DeviceEvidence: Codable, Sendable {
    var deviceName: String
    var hardwareModel: String
    var systemVersion: String
    var appVersion: String
    var physicalMemoryBytes: UInt64
    var processorCount: Int
    var initialThermalState: String
    var initialApplicationState: String
}

/// Checkpoints are saved before each expensive phase, so interrupted runs stay inspectable.
struct BenchmarkReport: Codable, Sendable {
    var schemaVersion = 1
    var runID: String
    var startedAt: Date
    var finishedAt: Date?
    var completed = false
    var stage = "baseline"
    var error: String?
    var mode: BenchmarkMode
    var corpusSize: Int
    var indexedDocuments = 0
    var indexedVectors = 0
    var modelIdentity: [String: String] = [:]
    var modelFiles = ["embeddinggemma-2-Q8_0.gguf"]
    var modelFilesVerified = false
    var device: DeviceEvidence
    var coldLoadMilliseconds = 0.0
    var setupQueryMilliseconds = 0.0
    var indexingMilliseconds = 0.0
    var indexMillisecondsPerDocument = 0.0
    var firstSearchMilliseconds = 0.0
    var uniqueQueries = LatencySummary()
    var repeatedQueries = LatencySummary()
    var correctnessChecks: [QueryMeasurement] = []
    var uniqueQuerySamples: [QueryMeasurement] = []
    var repeatedQuerySamples: [QueryMeasurement] = []
    var baselineFootprintMiB = 0.0
    var sampledPeakFootprintMiB = 0.0
    var sampledPeakDeltaMiB = 0.0
    var kernelLifetimePeakFootprintMiB: Double?
    var footprintAfterReleaseMiB: Double?
    var memorySnapshots: [MemorySnapshot] = []
    var sampleIntervalMilliseconds = 100
    var notes = [
        "Cold load is a fresh provider in this process: pinned file size/SHA-256 validation, native model/context allocation, optional media encoder initialization/warm-up, and two runtime text warm-up embeddings. OS file caches are not flushed.",
        "Fresh UUID index per run. Index timing embeds app-supplied synthetic passages and commits SQLite rows; it excludes model load.",
        "Search timing includes query embedding, exhaustive vector ranking, and SQLite result mapping. No query cache. Semantic mode, zGate=0, limit=5.",
        "Peak is the largest observed phys_footprint sample at 100 ms and phase boundaries, not the kernel lifetime high-water mark; briefer spikes can be missed.",
        "The corpus is a controlled teaching fixture, not a production-corpus performance estimate. Full mode loads vision/audio encoders but this benchmark searches text only."
    ]
}

enum BenchmarkClock {
    static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
    static func milliseconds(since start: UInt64) -> Double {
        Double(now() - start) / 1_000_000
    }
}
