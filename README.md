# Search Bench

A native iPhone harness for the sibling [LocalSearchKit](../LocalSearchKit/README.md) package. It embeds a controlled synthetic teaching corpus with the actual pinned EmbeddingGemma 2 Q8_0 weights, searches locally, and records wall time and process memory. It uses Metro Station styling with anchored latency and footprint readouts. No personal files or network service are involved.

## Current validation

The Release app, version 0.1.0 (4), was built, signed, installed, and confirmed in the app inventory on the iPhone 15 Pro Max running iOS 27.2. Sixteen source/config/native/resource files matched the staged build. Simulator commands were not used.

**Both real-model benchmarks completed on the physical iPhone:** 128 documents and 768-dimensional vectors, 25 distinct and 25 repeated timed queries per mode, and all eight correctness fixtures ranked first. Every recorded sample was active; the phone reported serious thermal state throughout both runs.

| Loaded model | Distinct query p50 | p95 | Peak app footprint | Verify + load |
| --- | ---: | ---: | ---: | ---: |
| Text only | 25.0 ms | 28.9 ms | 198.9 MiB | 1.47 s |
| Full, including image/audio encoders | 24.8 ms | 27.8 ms | 817.8 MiB | 2.10 s |

Both modes searched the same text corpus. Peak footprint includes the app, model/runtime, indexing, and search; it is not an isolated weight allocation. See [RESULTS.md](RESULTS.md) for raw reports, resident memory, release observations, and measurement boundaries.

The device runtime now loads offline-compiled Metal libraries from the Swift package resource bundle. Those libraries include BF16 kernels required by the retained `per_layer_model_proj.weight` tensor in the Q8_0 file. Earlier startup/foreground interruptions and the missing-kernel warm-up failure are retained in Evidence. Automatic benchmark launches wait for 1.5 seconds of continuous foreground activation; incomplete and backgrounded runs do not establish completed performance results.

## Build and install

The project expects these sibling directories:

```text
AI Stuff/
  LocalSearchKit/
    Package.swift
    Vendor/LlamaRuntime.xcframework
  SearchBench/
    SearchBench.xcodeproj
    SearchBench/Resources/Models/
```

The app targets iOS 26 or later and uses Swift 6 with the existing local package. Its native library contains an arm64 device slice. The bundled weights must be the pinned files accepted by `LocalSearchEngine.nativeFactory`:

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `embeddinggemma-2-Q8_0.gguf` | 309,855,456 | `2188ac1deca4b77dffefd603c2776a9d76d9d74ec01841392982ebb840b09135` |
| `mmproj-embeddinggemma-2-Q8_0.gguf` | 554,821,024 | `c4a8a52691ecef40618438928bdf9e68379b854e24166f292592353db0aab64f` |

Both files are bundled here, occupying about 865 MB decimal. Text-only activation loads the text backbone; full activation also initializes vision/audio encoders. The benchmark corpus and queries remain text in both modes. Retain the package/model provenance and license notices when distributing derived apps.

Open `SearchBench.xcodeproj`, select the SearchBench scheme and the physical iPhone, select an authorized signing team, and build/run with Release configuration. A command-line device build is:

```sh
xcodebuild -project SearchBench.xcodeproj -scheme SearchBench \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/SearchBenchDeviceDerived \
  -allowProvisioningUpdates build
```

The project can be regenerated with `xcodegen generate` using `project.yml`. If Xcode stalls on coordinated reads from the Documents checkout, stage identical sibling copies of both projects in a temporary directory and verify source parity before trusting that build.

Install the built app with Xcode or:

```sh
xcrun devicectl device install app --device DEVICE_ID \
  /tmp/SearchBenchDeviceDerived/Build/Products/Release-iphoneos/SearchBench.app
```

## Run on the iPhone

Open **Search Bench** from its Home Screen icon. Select 32, 128, or 512 synthetic records and the desired model mode, then tap **Run benchmark**. It starts directly from an empty app state, creates a fresh index, and runs the full measurement sequence: 8 correctness fixtures, 25 distinct query inputs, 25 repeated query inputs, and a model release observation. Keep the app foreground until completion.

For individual interactive searches, tap **Prepare index**, wait for the Ready status, and enter a query or use a preset. Preparation also verifies and activates the model, so it requires the app to remain foreground.

Automatic device launches accept the following arguments:

```sh
xcrun devicectl device process launch --device DEVICE_ID \
  --activate --terminate-existing --console com.utkarsh.searchbench -- \
  --benchmark --mode text --corpus 128 --run-id text-128-1
```

Use `--mode full` for full activation. A launch request is deferred until both SwiftUI scene phase and UIKit application state are active. Manual model actions also reject inactive starts. The app disables automatic idle locking while an operation runs, but deliberate switching to another app still backgrounds it. Keep the app foreground during the test.

The app remains open after completion. Its console prints compact `SEARCHBENCH` event JSON, including `native-phase`, `benchmark-stage`, and `benchmark-finished`. Native milestones distinguish verification, backend initialization, model load, context creation, optional media initialization, and text warm-up. The default LocalSearchKit factory remains silent unless a diagnostic callback is explicitly supplied.

## Reports

Reports are saved inside the app's Documents directory:

- `benchmark-latest.json`: the latest atomic phase checkpoint.
- `benchmark-{text|full}-{runID}.json`: a retained checkpoint for that run.
- `memory-latest.json` and `memory-{text|full}-{runID}.json`: activation diagnostics, atomically updated every 500 ms and at native phase boundaries with the latest 100 ms samples.

Memory journaling uses a dedicated utility queue, continues while the inference actor is occupied, and stops after activation. Its queued writes finish before measured indexing begins. It records the current native phase, application state, thermal state, footprint, RSS, sampled peak, and kernel lifetime peak. A process termination can leave partial reports behind. Any run that records an inactive/background application state fails its completion check and retains raw samples with an explicit error. Verify `completed: true`, the expected document/vector counts, and nonempty query sample arrays before treating a benchmark as complete.

Retrieve a report using the app's Files sharing surface or:

```sh
xcrun devicectl device copy from --device DEVICE_ID \
  --domain-type appDataContainer --domain-identifier com.utkarsh.searchbench \
  --source Documents/benchmark-latest.json \
  --destination Evidence/benchmark-latest.json
```

## Metric definitions

| Metric | What it measures |
| --- | --- |
| Verify + model load | Fresh provider creation: pinned size/SHA-256 verification, native model/context creation, optional media initialization, and two runtime text warm-up embeddings. OS file caches are not flushed. |
| Setup query | The empty-index activation probe, including factory creation and its query embedding. |
| Corpus indexing | Real-model passage embedding plus an atomic SQLite batch commit on a fresh UUID index. Excludes model activation. |
| Index ms/document | Total indexing wall time divided by the acknowledged document count. |
| First indexed query | The first semantic query after indexing; includes reloading the in-memory vector matrix. |
| Distinct/repeated P50/P95 | Complete `engine.search` wall time: query embedding, exhaustive vector ranking, and SQLite result resolution. Nearest-rank percentiles from 25 inputs per series. There is no query cache. |
| Interactive search | Complete hybrid-search wall time. A search after releasing the model includes its reactivation. |
| Process footprint | `TASK_VM_INFO.phys_footprint`, in MiB (1,048,576 bytes), from the latest sample. |
| Resident memory | `MACH_TASK_BASIC_INFO.resident_size`, including resident clean mapped pages; differs from app-charged footprint. |
| Sampled run peak | Largest observed footprint at phase boundaries and a 100 ms target cadence with 10 ms dispatch leeway. Shorter spikes may be missed. |
| Kernel lifetime peak | `ledger_phys_footprint_peak` since process launch. It cannot be reset for an individual run. |
| After release | Observed footprint one second after closing the model/context and releasing the vector matrix. SQLite and backend/Metal caches can remain. |

The automated query series uses semantic mode, `zGate = 0`, and a five-result limit, with one 768-dimensional real-model vector required per passage. Its correctness report records whether each expected fixture appears first and within the top five; those checks describe this controlled corpus only. Scores and cosine values are ranking measurements, not probabilities or a universal relevance threshold. Thermal and application state are included with the samples so interrupted or heated runs can be identified.

## Measurement checks

The lightweight native Mac harness checks percentile ranks and filtering, top-five correctness evaluation, and actual Mach memory reads:

```sh
xcrun swiftc -swift-version 6 \
  SearchBench/Benchmark/Measurement.swift \
  SearchBench/Benchmark/MemorySampler.swift \
  Tests/MeasurementTests/MeasurementTests.swift \
  -o /tmp/searchbench-measurement-tests
/tmp/searchbench-measurement-tests
```

Compilation and these assertions establish measurement plumbing. Completed foreground runs on the physical iPhone are required for device performance claims.


## Public snapshot

See [PUBLICATION.md](PUBLICATION.md) for publication exclusions and setup requirements.
