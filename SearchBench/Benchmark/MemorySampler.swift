import Darwin
import Foundation

/// A dedicated queue samples while a search actor is occupied by native inference.
final class MemorySampler: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "SearchBench.memory", qos: .utility)
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let update: @Sendable (MemorySnapshot, Double) -> Void
    private var timer: DispatchSourceTimer?
    private var start = BenchmarkClock.now()
    private var currentStage = "idle"
    private var appState = "unknown"
    private var values: [MemorySnapshot] = []
    private var peak = 0.0
    private var journalConfiguration: JournalConfiguration?
    private var lastJournalNanoseconds: UInt64 = 0
    private var journalFailureReported = false
    private var nativePhase = "not-started"

    private struct JournalConfiguration: Sendable {
        let directory: URL
        let runID: String
        let mode: BenchmarkMode
    }

    private struct MemoryJournal: Codable, Sendable {
        let schemaVersion: Int
        let runID: String
        let mode: BenchmarkMode
        let recordedAt: Date
        let stage: String
        let sampledPeakFootprintMiB: Double
        let sampleIntervalTargetMilliseconds: Int
        let journalIntervalTargetMilliseconds: Int
        let recentSamples: [MemorySnapshot]
        let loadingComplete: Bool
        let nativePhase: String
    }

    init(update: @escaping @Sendable (MemorySnapshot, Double) -> Void) {
        self.update = update
        queue.setSpecific(key: queueKey, value: 1)
    }

    /// Waits until activation journal writes finish before measured indexing begins.
    func flushJournal() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { continuation.resume() }
        }
    }

    /// Journaling is enabled only for activation; measured indexing and search perform no journal disk writes.
    func configureActivationJournal(directory: URL, runID: String, mode: BenchmarkMode) {
        lock.withLock {
            journalConfiguration = JournalConfiguration(directory: directory, runID: runID, mode: mode)
            lastJournalNanoseconds = 0
            journalFailureReported = false
            nativePhase = "not-started"
        }
    }

    /// A phase transition prompts a fresh journal packet; it does not change the benchmark's timed stage.
    func recordNativePhase(_ phase: String) {
        lock.withLock {
            nativePhase = phase
            lastJournalNanoseconds = 0
        }
        _ = capture()
    }

    func begin() {
        lock.withLock {
            start = BenchmarkClock.now()
            values.removeAll(keepingCapacity: true)
            peak = 0
            currentStage = "baseline"
        }
        _ = capture()
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: .milliseconds(100), leeway: .milliseconds(10))
        source.setEventHandler { [weak self] in _ = self?.capture() }
        timer = source
        source.resume()
    }

    func end() {
        timer?.cancel()
        timer = nil
        _ = capture()
    }

    func setApplicationState(_ state: String) { lock.withLock { appState = state } }

    @discardableResult
    func mark(_ stage: String) -> MemorySnapshot {
        lock.withLock { currentStage = stage }
        return capture()
    }

    func evidence() -> (snapshots: [MemorySnapshot], peak: Double) {
        lock.withLock { (values, peak) }
    }

    @discardableResult
    private func capture() -> MemorySnapshot {
        let memory = Self.readMemory()
        let thermal = Self.thermalState()
        let (snapshot, sampledPeak): (MemorySnapshot, Double) = lock.withLock {
            let value = MemorySnapshot(id: values.count,
                secondsFromStart: Double(BenchmarkClock.now() - start) / 1_000_000_000,
                stage: currentStage, footprintMiB: memory.footprint,
                residentMiB: memory.resident, kernelLifetimePeakFootprintMiB: memory.kernelPeak,
                thermalState: thermal, applicationState: appState)
            values.append(value)
            peak = max(peak, memory.footprint ?? 0)
            return (value, peak)
        }
        update(snapshot, sampledPeak)
        journalIfNeeded(snapshot: snapshot, peak: sampledPeak)
        return snapshot
    }

    private func journalIfNeeded(snapshot: MemorySnapshot, peak: Double) {
        let packet: (JournalConfiguration, MemoryJournal)? = lock.withLock {
            guard let configuration = journalConfiguration,
                  snapshot.stage == "loading" || snapshot.stage == "loaded" else { return nil }
            let now = BenchmarkClock.now()
            guard snapshot.stage == "loaded" || lastJournalNanoseconds == 0 ||
                    now - lastJournalNanoseconds >= 500_000_000 else { return nil }
            lastJournalNanoseconds = now
            let journal = MemoryJournal(schemaVersion: 1, runID: configuration.runID, mode: configuration.mode,
                recordedAt: Date(), stage: snapshot.stage, sampledPeakFootprintMiB: peak,
                sampleIntervalTargetMilliseconds: 100, journalIntervalTargetMilliseconds: 500,
                recentSamples: Array(values.suffix(10)), loadingComplete: snapshot.stage == "loaded",
                nativePhase: nativePhase)
            if snapshot.stage == "loaded" { journalConfiguration = nil }
            return (configuration, journal)
        }
        guard let (configuration, journal) = packet else { return }
        // This queue is independent of both the inference actor and MainActor. A fatal native assertion can leave
        // the latest completed atomic write behind even though the benchmark phase checkpoint never completes.
        // A sampler event already on this serial queue writes directly, so it cannot enqueue an older packet
        // after flushJournal's continuation. Actor-originated phase packets are queued in order.
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            writeJournal(configuration: configuration, journal: journal)
        } else {
            queue.async { [weak self] in self?.writeJournal(configuration: configuration, journal: journal) }
        }
    }

    private func writeJournal(configuration: JournalConfiguration, journal: MemoryJournal) {
        do {
                try FileManager.default.createDirectory(at: configuration.directory, withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(journal)
                let safeID = String(configuration.runID.filter {
                    $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_")
                }.prefix(100))
                try data.write(to: configuration.directory.appendingPathComponent("memory-latest.json"), options: .atomic)
                try data.write(to: configuration.directory.appendingPathComponent("memory-\(configuration.mode.rawValue)-\(safeID).json"), options: .atomic)
        } catch {
                let shouldReport = lock.withLock {
                    guard !journalFailureReported else { return false }
                    journalFailureReported = true
                    return true
                }
                if shouldReport { print("SEARCHBENCH memory-journal-error: \(error)"); fflush(nil) }
        }
    }

    static func thermalState() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    static func readMemory() -> (footprint: Double?, resident: Double?, kernelPeak: Double?) {
        var vm = task_vm_info_data_t()
        let vmCapacity = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        var vmCount = vmCapacity
        let vmResult = withUnsafeMutablePointer(to: &vm) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(vmCapacity)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &vmCount)
            }
        }
        var basic = mach_task_basic_info_data_t()
        let basicCapacity = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        var basicCount = basicCapacity
        let basicResult = withUnsafeMutablePointer(to: &basic) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(basicCapacity)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &basicCount)
            }
        }
        let mib = 1_048_576.0
        // These revision-count C macros are not imported into Swift; derive the required words from each field.
        let footprintWords = MemoryLayout<task_vm_info_data_t>.offset(of: \.phys_footprint)
            .map { ($0 + MemoryLayout<UInt64>.size) / MemoryLayout<integer_t>.size } ?? Int.max
        let peakWords = MemoryLayout<task_vm_info_data_t>.offset(of: \.ledger_phys_footprint_peak)
            .map { ($0 + MemoryLayout<UInt64>.size) / MemoryLayout<integer_t>.size } ?? Int.max
        let footprintAvailable = vmResult == KERN_SUCCESS && Int(vmCount) >= footprintWords
        let kernelPeakAvailable = vmResult == KERN_SUCCESS && Int(vmCount) >= peakWords
        return (footprintAvailable ? Double(vm.phys_footprint) / mib : nil,
                basicResult == KERN_SUCCESS ? Double(basic.resident_size) / mib : nil,
                kernelPeakAvailable ? Double(vm.ledger_phys_footprint_peak) / mib : nil)
    }

    deinit { timer?.cancel() }
}
