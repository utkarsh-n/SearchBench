import SwiftUI

struct SearchBenchView: View {
    @Bindable private var model: BenchmarkModel
    @State private var query = "how transformers pay attention"
    @State private var requestedCorpusSize = 128
    @State private var requestedMode: BenchmarkMode = .textOnly
    @FocusState private var queryFocused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var readoutSize = 54.0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let presets = [
        "how transformers pay attention",
        "sound from vibrating strings",
        "orbits and gravity",
        "storing energy in batteries"
    ]

    init(model: BenchmarkModel) {
        self.model = model
    }

    var body: some View {
        ZStack {
            BenchBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    liveReadout
                    configuration
                    searchControls
                    if let error = model.error {
                        errorPanel(error)
                    }
                    if !model.results.isEmpty {
                        resultsPanel
                    }
                    if let report = model.report {
                        reportPanel(report)
                    }
                    measurementNotes
                }
                .frame(maxWidth: 600)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(BenchPalette.display)
        .tint(BenchPalette.cyan)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(BenchPalette.cyan)
                    .frame(width: 52, height: 52)
                    .background(
                        LinearGradient(colors: [BenchPalette.metalLight, BenchPalette.metalDark],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 17)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 17)
                            .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("SearchBench")
                        .font(.system(.title, design: .rounded, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("LOCALSEARCHKIT · ON DEVICE")
                        .font(.system(.caption, design: .monospaced, weight: .medium))
                        .tracking(1)
                        .foregroundStyle(BenchPalette.secondary)
                }
            }
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: model.isBusy ? "hourglass" : (model.docCount > 0 ? "checkmark.circle.fill" : "circle.dotted"))
                    .foregroundStyle(model.isBusy ? BenchPalette.amber : BenchPalette.cyan)
                Text(model.stage)
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                Spacer(minLength: 8)
                Text("\(model.docCount) indexed")
                    .font(.system(.caption, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(BenchPalette.secondary)
            }
            Text(model.status)
                .font(.subheadline)
                .foregroundStyle(BenchPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    private var liveReadout: some View {
        VStack(alignment: .leading, spacing: 16) {
            BenchSectionLabel(title: "LATEST QUERY")
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) { queryReadout }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) { queryReadout }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Latest query time")
            .accessibilityValue(model.lastSearchMilliseconds.map { "\(milliseconds($0)) milliseconds" } ?? "Not measured")
            Text("Query embedding + local retrieval")
                .font(.subheadline)
                .foregroundStyle(BenchPalette.secondary)
            Divider().overlay(.white.opacity(0.08))
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 16) { memoryReadouts }
            } else {
                HStack(alignment: .top, spacing: 16) { memoryReadouts }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [BenchPalette.metalLight, BenchPalette.metalDark],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.20), .white.opacity(0.035), BenchPalette.cyan.opacity(0.13)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1
                )
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var queryReadout: some View {
        Text(milliseconds(model.lastSearchMilliseconds))
            .font(dynamicTypeSize.isAccessibilitySize
                  ? .system(.largeTitle, design: .rounded, weight: .light)
                  : .system(size: readoutSize, weight: .light, design: .rounded))
            .monospacedDigit()
        Text("ms")
            .font(.system(.headline, design: .monospaced))
            .foregroundStyle(BenchPalette.cyan)
    }

    @ViewBuilder private var memoryReadouts: some View {
        BenchMetric(label: "Latest footprint", value: memory(model.currentMemoryMiB), unit: "MiB")
        BenchMetric(label: "Sampled peak", value: memory(model.peakMemoryMiB), unit: "MiB", accent: BenchPalette.amber)
    }

    private var configuration: some View {
        BenchPanel {
            VStack(alignment: .leading, spacing: 14) {
                BenchSectionLabel(title: "PREPARE THE ENGINE")
                Text("Corpus size")
                    .font(.subheadline.weight(.medium))
                Picker("Corpus size", selection: $requestedCorpusSize) {
                    ForEach([32, 128, 512], id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(model.isBusy)
                .accessibilityHint("The next prepare or benchmark operation indexes this many text records.")

                if model.availableFullModel {
                    Picker("Loaded model", selection: $requestedMode) {
                        Text("Text only").tag(BenchmarkMode.textOnly)
                        Text("Full model").tag(BenchmarkMode.full)
                    }
                    .pickerStyle(.segmented)
                    .disabled(model.isBusy)
                    .accessibilityHint("Full model also loads image and audio encoders; the corpus remains text.")
                }
                Text(modeExplanation)
                    .font(.caption)
                    .foregroundStyle(BenchPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                BenchAction(title: "Prepare index", symbol: "square.stack.3d.up", prominent: model.docCount == 0) {
                    queryFocused = false
                    model.prepare(corpusSize: requestedCorpusSize, mode: requestedMode)
                }
                .disabled(model.isBusy)

                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 12) { engineActions }
                } else {
                    HStack(spacing: 12) { engineActions }
                }
            }
        }
    }

    @ViewBuilder private var engineActions: some View {
        BenchAction(title: "Run benchmark", symbol: "speedometer", accent: BenchPalette.amber) {
            queryFocused = false
            model.runBenchmark(corpusSize: requestedCorpusSize, mode: requestedMode)
        }
        .disabled(model.isBusy)
        .accessibilityHint("Loads a fresh model, indexes the selected corpus, and measures first query, 50 timed queries, and sampled memory.")
        BenchAction(title: "Release model", symbol: "eject") {
            queryFocused = false
            model.releaseModel()
        }
        .disabled(model.isBusy || model.docCount == 0)
        .accessibilityHint("Drops the index and model references; process memory may remain cached by the runtime.")
    }

    private var searchControls: some View {
        BenchPanel {
            VStack(alignment: .leading, spacing: 14) {
                BenchSectionLabel(title: "SEARCH BY MEANING")
                TextField("Describe what you want to find", text: $query, axis: .vertical)
                    .font(.body)
                    .lineLimit(2...4)
                    .padding(14)
                    .background(BenchPalette.canvas, in: RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(BenchPalette.cyan.opacity(queryFocused ? 0.65 : 0.18), lineWidth: 1)
                    }
                    .focused($queryFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { performSearch() }
                    .accessibilityLabel("Search query")
                BenchAction(title: "Search", symbol: "magnifyingglass", prominent: true) {
                    performSearch()
                }
                .disabled(!canSearch)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(presets, id: \.self) { preset in
                            Button {
                                query = preset
                                performSearch()
                            } label: {
                                Text(preset)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 44)
                                    .background(BenchPalette.cyan.opacity(0.045), in: Capsule())
                                    .overlay { Capsule().strokeBorder(BenchPalette.cyan.opacity(0.16), lineWidth: 1) }
                            }
                            .buttonStyle(.plain)
                            .disabled(model.isBusy || model.docCount == 0)
                            .accessibilityLabel("Search for \(preset)")
                        }
                    }
                }
            }
        }
    }

    private var resultsPanel: some View {
        BenchPanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    BenchSectionLabel(title: "RETRIEVED RECORDS")
                    Spacer()
                    Text("\(model.results.count)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(BenchPalette.secondary)
                }
                ForEach(Array(model.results.enumerated()), id: \.element.id) { offset, hit in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(String(format: "%02d", offset + 1))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(BenchPalette.cyan)
                                .accessibilityHidden(true)
                            Text(hit.title)
                                .font(.headline)
                        }
                        Text(hit.excerpt)
                            .font(.subheadline)
                            .foregroundStyle(BenchPalette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(scoreLabel(hit))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(BenchPalette.cyan)
                        if offset < model.results.count - 1 {
                            Divider().padding(.top, 8)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func reportPanel(_ report: BenchmarkReport) -> some View {
        BenchPanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    BenchSectionLabel(title: "MEASURED RUN")
                    Spacer()
                    Text(report.completed ? "Complete" : "Checkpoint")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(report.completed ? BenchPalette.cyan : BenchPalette.amber)
                }
                if !report.completed {
                    Text("Saved through \(report.stage). Unmeasured phases show a dash.")
                        .font(.caption)
                        .foregroundStyle(BenchPalette.secondary)
                }
                VStack(spacing: 10) {
                    reportRow("Verify + model load", measuredMilliseconds(report.coldLoadMilliseconds), "ms")
                    reportRow("Corpus indexing", measuredMilliseconds(report.indexingMilliseconds), "ms")
                    reportRow("First indexed query", measuredMilliseconds(report.firstSearchMilliseconds), "ms")
                }
                Divider()
                latencySummary("Unique queries", summary: report.uniqueQueries)
                latencySummary("Repeated query", summary: report.repeatedQueries)
                Divider()
                VStack(spacing: 10) {
                    reportRow("Baseline footprint", memory(report.baselineFootprintMiB), "MiB")
                    reportRow("Run sampled peak", memory(report.sampledPeakFootprintMiB), "MiB", accent: BenchPalette.amber)
                }
                Text("Benchmark queries use semantic retrieval without query caching. p50 and p95 use nearest-rank percentiles; first-query time is shown separately.")
                    .font(.caption)
                    .foregroundStyle(BenchPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func latencySummary(_ title: String, summary: LatencySummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text("\(summary.count) samples")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(BenchPalette.secondary)
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) { latencyMetrics(summary) }
            } else {
                HStack(alignment: .top, spacing: 16) { latencyMetrics(summary) }
            }
        }
        .padding(12)
        .background(BenchPalette.canvas, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder private func latencyMetrics(_ summary: LatencySummary) -> some View {
        BenchMetric(label: "p50", value: summary.count > 0 ? milliseconds(summary.medianMilliseconds) : "—", unit: "ms")
        BenchMetric(label: "p95", value: summary.count > 0 ? milliseconds(summary.p95Milliseconds) : "—", unit: "ms", accent: BenchPalette.violet)
    }

    private func reportRow(_ title: String, _ value: String, _ unit: String,
                           accent: Color = BenchPalette.cyan) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).font(.subheadline).foregroundStyle(BenchPalette.secondary)
            Spacer(minLength: 12)
            Text("\(value) \(unit)")
                .font(.system(.subheadline, design: .monospaced, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(accent)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func errorPanel(_ error: String) -> some View {
        BenchPanel {
            Label {
                Text(error).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(BenchPalette.amber)
            .accessibilityLabel("Operation failed. \(error)")
        }
    }

    private var measurementNotes: some View {
        VStack(alignment: .leading, spacing: 8) {
            BenchSectionLabel(title: "MEASUREMENT BOUNDARY")
            Text("Real model, local inference. Interactive search uses hybrid retrieval. Benchmarks use semantic retrieval. Time includes query embedding, ranking and result resolution.")
            Text("Verify + model load includes file verification, native loading, two text runtime warmups and optional media warmup. It does not establish a cold filesystem cache. The corpus is bundled sample text.")
            Text("Memory is this app’s phys_footprint, sampled every 100 ms during measured phases. Latest footprint is the last recorded sample. Sampled peaks can miss shorter spikes. iOS memory pressure and runtime caches affect later runs.")
            Text("Run benchmark starts a fresh model and index using the selected settings. It releases the model when complete; a later interactive search includes reloading it.")
            Text("Cosine similarity is a ranking measure, not a probability or confidence score.")
        }
        .font(.caption)
        .foregroundStyle(BenchPalette.secondary)
        .padding(.horizontal, 4)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var modeExplanation: String {
        if requestedMode == .full {
            return "Full model loads text, image and audio encoders. This test searches text records."
        }
        return "Text-only loads the real text encoder. Prepare and Run benchmark apply the selected size and model mode."
    }

    private var canSearch: Bool {
        !model.isBusy && model.docCount > 0 && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func performSearch() {
        guard canSearch else { return }
        queryFocused = false
        model.search(query: query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func milliseconds(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return value.formatted(.number.precision(.fractionLength(value >= 1_000 ? 0 : 1)))
    }

    private func memory(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "—" }
        return value.formatted(.number.precision(.fractionLength(1)))
    }

    private func measuredMilliseconds(_ value: Double) -> String {
        milliseconds(value > 0 ? value : nil)
    }

    private func scoreLabel(_ hit: BenchmarkHit) -> String {
        if let cosine = hit.cosine {
            return "COSINE \(cosine.formatted(.number.precision(.fractionLength(3))))"
        }
        return "RANK SCORE \(hit.score.formatted(.number.precision(.fractionLength(3))))"
    }
}
