# Performance audit — 25 September 2026

The ordinary reader/storage/search paths are fast in the measured simulator workloads. Prioritize launch responsiveness and large-library scheduling; do not replace TextKit or migrate storage solely on these results. This audit adds diagnostic tests and evidence only, with no production implementation changes by this audit.

## Scope and method

Reviewed startup/composition, Observation dependencies, native TextKit rendering, gutters/accessibility, page caches and curl snapshots, selection/annotations/Undo, restoration writes, SQLite and compressed corpus access, search pagination/cancellation, Saved sorting/resolution, and optional on-device overview/questions.

Xcode 27.0 (27A266a), iOS/iPadOS 27.0 simulator, macOS 27.0 (26A428). Runs use **Release optimization with DEBUG test hooks and ENABLE_TESTABILITY enabled**, not a shipping Release binary. Existing tests reference counters compiled only with DEBUG, so a plain Release test build failed. New harness compiler errors in that first attempt were corrected. The successful builds retain one pre-existing deprecated `UIWindow(frame:)` warning in PaperTurnTests.

Initial iPhone 18 Pro run: three diagnostic tests passed. iPad mini (A17 Pro) run: two diagnostic tests passed. Final iPhone run: two diagnostic tests passed, adding the renderer stress test and requesting explicit hitch capture. These are seven selected benchmark executions, not seven distinct tests or a rerun of the entire functional suite.

The shared working tree already contained substantial edits, and further scheme/page-preloading edits arrived during the audit. Runs are independent observations, not controlled before/after measurements. `source-fingerprints.json` records a late audit snapshot, not a claim that all earlier runs used those exact bytes. Original Xcode result bundles and logs remain under the local XcodeBuildMCP workspace.

The microbenchmarks use fresh temporary user databases and genuine excerpts from the bundled corpus. The 10,000-entry fixture contains one whole-verse exact highlight per verse across chapters. It does not model every possible fragment distribution or legacy bookmark load. The benchmark fixture operations do not access the normal reader database; UI benchmarks explicitly select isolated stores. “First” means a first operation on a new store/session; OS disk caches were not flushed. Store calls include actor scheduling. Bare-view layout benchmarks exclude compositor/GPU presentation and are not FPS measurements. Small sample counts do not support p95 claims. Simulator models are not their physical device CPUs; do not compare the two runs as device rankings.

## Findings, in priority order

### 1. Launch responsiveness merits profiling — measured, medium priority

XCTest's first-frame-and-responsive metric averaged **2.380 seconds** across five measured iPhone launches (2.336–2.485 seconds). This exceeds the approximate 2-second usable-reader goal, but the metric is not identical to Scripture-ready time. Repeated process launches used the same isolated store; this is not five fresh installs. XCTest discards its warm-up iteration.

The component timings are much smaller: fresh store opening 4.35 ms, bootstrap 13.65 ms, first Psalm 119 decode 5.86 ms. These do not explain the launch result by themselves. Do not label SQLite as the root cause. Capture first frame, first usable Scripture, and responsive time separately on the slowest supported physical device, with Time Profiler/SwiftUI instruments and a pristine Release build. Add static-name intervals around document configuration/initial presentation and chapter turns; existing `ReaderPerformance` intervals cover storage operations only. Effort: small instrumentation change plus a focused device profile.

### 2. Large Saved libraries can delay navigation and incur main-thread sorting — measured cost, code-supported contention risk

`BibleStore.cachedExact` loads and decodes all edition annotations (`BibleStore.swift:36`). Loading 10,000 records took **53.9 ms** on the iPhone run and **113.9 ms** on the iPad run. `ReaderState.load` refreshes this full collection during startup. Initial `savedItems()` resolution took **98.1 / 283.4 ms**; cached reads were much cheaper. Both annotation decoding and Saved resolution run synchronously on the same serial store actor used for chapter and position work. A navigation request arriving during that work must wait. The queueing impact was inferred from isolation, not measured with a concurrent-navigation workload.

`SavedView.swift:58` sorts/filters on the main actor. At 10,000 rows the iPhone median was 2.71 ms; the iPad median was 12.55 ms with a **51.24 ms** maximum. The benchmark includes rebuilding the 1,189-entry chapter lookup, so it slightly overstates the production sorting call. This is a hitch risk at large collections, not evidence that ordinary Saved lists are slow.

Recommended next change: compute visible ordering off the main actor with cancellation/revision checks, then measure again. For growing libraries, load current-chapter annotation payloads independently of lightweight global metadata and paginate Saved. This likely needs indexed chapter metadata in an additive migration. Preserve unresolved annotations and existing transactional behavior. Do not add WAL/a pool without a measured concurrency comparison. Effort: small for sorting; medium for storage changes.

### 3. Common-term deep search gets progressively more expensive — measured, medium/low priority

The first “the” query took **41.4 / 73.2 ms** (iPhone/iPad); five-query medians including the first query were **18.0 / 30.1 ms**. Phrase and uncommon-word queries were substantially cheaper. Ordinary first-page search met the 100 ms post-debounce goal in these samples.

For “the”, offsets 50 / 1,000 / 10,000 took **18.8 / 28.9 / 67.7 ms** in the iPhone run and **31.7 / 45.4 / 126.1 ms** in the iPad run. `BibleStore.swift:191` orders by `bm25` then canonical ordinal with OFFSET; the host query plan uses a temporary B-tree. A page deep in a common query still scores/sorts many matches. The exact plan was checked on host SQLite 3.53.1, not claimed as on-device bytecode.

Retained search hits also grow with each explicit Load more. This is bounded by corpus size, but array copies and retained snippets increase. Profile realistic long search sessions before introducing rank/keyset pagination; preserve deterministic relevance/canonical ordering. Effort: medium. Cancellation/stale-response handling and a separate async search connection are already present; no arbitrary SQL search or main-thread query issue was found.

### 4. Search prewarming does not guarantee full index-page reads — verified implementation issue, low priority

`BibleStore.swift:208` uses `sum(length(block))` on `verse_search_data`. SQLite can compute BLOB length from metadata without loading its full content. Host EXPLAIN confirms the length-only Column flag (P5=64). It still touches table pages and initializes the parser, so this does not mean it has zero benefit; it does mean the comment claiming a full FTS read is too strong.

Benchmark opening Search with/without prewarming on genuinely cold device runs. Remove the scan if parser caching suffices, or use a bounded representative index read if it demonstrably helps. Do not allocate the entire index just to “warm” it. Effort: small. [SQLite length semantics](https://www.sqlite.org/lang_corefunc.html#length) and [opcode documentation](https://www.sqlite.org/opcode.html#Column) explain the optimization.

### 5. Pure Release performance testing is not currently supported by the test target — reproduced, medium priority for validation

`ChapterTextMapTests` and `ExactAnnotationTests` unconditionally use Debug-only renderer/storage counters. Selecting a single new benchmark does not avoid compiling those files. Plain Release + ENABLE_TESTABILITY therefore fails to compile the test target. This is a test configuration issue, not an app Release compile failure.

Gate counter-specific assertions/tests or isolate the performance harness in a target that can test the shipping compilation conditions. Do not remove functional coverage. Until then these optimized diagnostic results are useful baselines with explicit limitations. Effort: small.

## Renderer, memory, and optional model review

- Psalm 119 configuration at 390 points: iPhone median 1.46 ms, first sample 13.32 ms; initial layout median 4.44 ms. At 640 points: 1.53 / 4.70 ms. iPad-run medians were 3.06 / 8.24 ms and 3.28 / 8.32 ms. One hundred unchanged configurations took approximately 0.02–0.04 ms total, supporting the existing invalidation guards.
- Fifty programmatic scroll/layout steps took 20.95 ms median at 390 points on iPhone, 47.54 ms on iPad. These are batched CPU-side operations, not rendered frame times. The UI scrolling workload is two fast upward and two fast downward swipes, five measured repetitions after warm-up.
- iPad renderer stress: creating/configuring/laying out a Psalm 119 adjacent page median 8.99 ms, max 16.17 ms; largest Dynamic Type + dark reflow median 8.48 ms, max 24.23 ms; highlighting all 176 verses median 7.52 ms, max 9.52 ms. This justifies keeping preparation outside gesture onset. The latest shared-tree code now prepares neighboring page layouts; it was not changed by this audit. Per-sample iPhone stress values are in `iphone-renderer-stress.json`.
- Bounded caches are present: six decoded chapters, current/adjacent page-controller retention, six bookmark indicator entries. Paper reverse snapshots release on disappearance. Accessibility geometry is requested lazily; annotations update affected text ranges instead of replacing the whole document. Session Undo has no explicit count/byte cap and retains before/after payloads; this is a long-session memory-growth risk, not a demonstrated leak. Measure sustained editing before setting a policy.
- Initial iPhone scrolling metrics: physical memory ~57.6–58.2 MB at measurement boundaries; peak ~60.4–67.0 MB. Net-allocation metrics varied considerably and must not be called a leak rate. CPU time averaged 2.45 seconds over the complete four-swipe XCTest interaction; this includes more than pure scroll rendering and is not battery or utilization data.
- Final iPhone scrolling run: physical memory ~57.7–58.2 MB, peaks ~67.3–67.9 MB, CPU time average 2.45 seconds. `XCTHitchMetric` was requested but returned **no metric** in stdout or `xcresulttool get test-results metrics`; this is not a zero-hitch result. Frame drops, hitch count, and GPU smoothness remain unverified. Final iPhone renderer medians: adjacent page 5.86 ms, largest-type dark reflow 5.29 ms, all-verse highlighting 5.02 ms, local Psalms retrieval 16.64 ms.
- A separate fresh isolated Psalm 119 launch, settled for about 37 seconds, produced a 3.14 MB memgraph. `leaks` reported **one unidentified 32-byte allocation**, no app-owned type/retaining path, and a physical footprint of 33.2 MB. This narrow snapshot does not prove leak freedom during repeated turns, editing, sheet dismissal, or AI generation. The raw graph is at `/tmp/bible-performance-memgraph/`; it is not committed. No leak fix is claimed.
- Optional model generation remains serial and bounded: independent chunk sessions, reduction, refusal classification, then optional presentation metadata; questions add scope/retrieval/review stages. Long chapters do not stream the initial per-chunk drafts. Generation latency, first-token delay, model memory, and energy were **not measured** with a real model. Do not remove safety/review stages to improve timing without separate design review. Local Psalms source retrieval took 27.9 ms median / 45.2 ms max in the iPad run; it scans/tokenizes the whole book on the store actor. Cache tokenized book data or use bounded indexed retrieval only if it becomes a measured source of contention.
- The corpus is 15,896,576 bytes. Runtime decoding is per chapter; no startup full-Bible rebuild or runtime network fetch was found in the audited paths. Network capture was not performed and no privacy certification is implied.

## Reproduction

Read the CLI help and use an installed simulator. The tested benchmark configuration is intentionally explicit:

```sh
xcodebuildmcp simulator test --project-path BibleReader.xcodeproj --scheme BibleReader --simulator-name 'iPhone 18 Pro' --configuration Release --derived-data-path .build/PerformanceAudit --extra-args '-only-testing:BibleReaderTests/PerformanceAuditTests' '-only-testing:BibleReaderUITests/PerformanceAuditUITests' '-parallel-testing-enabled' 'NO' '-collect-test-diagnostics' 'never' 'ENABLE_TESTABILITY=YES' 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG'
```

The initial iPhone run preceded adding `testRendererStress` and `XCTHitchMetric`; the final focused run selects that method and `testPsalmScrollingPerformance`. The iPad run uses `--simulator-name 'iPad mini (A17 Pro)'` and only `BibleReaderTests/PerformanceAuditTests`. Benchmarks emit retained JSON test attachments; microbenchmark stdout prefixes are `PERFORMANCE_AUDIT` and `RENDERER_STRESS`. UI metrics are recorded by XCTest. No numerical acceptance threshold is enforced by these diagnostic tests.

Checked-in JSON files retain all samples in milliseconds for microbenchmarks and explicit native units for UI metrics. Do not compare simulator milliseconds directly to physical-device acceptance. [Apple's launch metric](https://developer.apple.com/documentation/xctest/xctapplicationlaunchmetric) measures first-frame/launch completion or responsiveness; [scroll metrics](https://developer.apple.com/documentation/xctest/xctossignpostmetric) measure specific animation intervals, not automatically the entire user interaction.

## Remaining validation limits

No physical-device/thermal/battery profile, iOS 26 performance run, GPU/Metal profile, symbolicated CPU trace, first-install disk-cold launch study, heavy cross-verse selection latency study, 10,000 legacy-bookmark test, long-session Undo stress, or model inference benchmark was completed. These gaps limit release acceptance; they do not prevent using the measured results to prioritize the next performance changes. This audit does not certify the release performance targets.

## Follow-up changes (same day, after this audit)

These changes were made in response to the findings above and have not been re-measured with the audit harness.

- **Finding 1 (launch).** Added static-name signposts for profiling launch on device: `Reader load` (ReaderState.load), `Document build` (ChapterTextView), `Chapter turn` (interactive curl), and a one-time `First Scripture laid out` event. No launch optimization is claimed until a device trace identifies the cost.
- **Finding 2 (Saved).** Libraries over 1,000 items are now filtered and sorted in a detached task, with stale results discarded by `.task(id:)` cancellation. Smaller libraries still sort inline to avoid an empty-state flash. Loading every annotation on the store actor and non-paginated Saved remain open. They need an additive chapter-indexed metadata migration and a measured concurrent-navigation workload.
- **Finding 3 (deep search).** Unchanged, as the audit recommends: profile long sessions before keyset pagination.
- **Finding 4 (prewarm).** Replaced `sum(length(block))` with one ranked `MATCH 'the' … ORDER BY bm25 LIMIT 1` on the search connection. This reads the largest posting list and the document-size table and exercises the real statement shape, all bounded. Cold-device benefit is still to be measured.
- **Finding 5 (Release testing).** Debug-only counter assertions in `ChapterTextMapTests` and `ExactAnnotationTests` are now inside `#if DEBUG`, and their functional assertions still run. `build-for-testing -configuration Release ENABLE_TESTABILITY=YES` now succeeds. The deprecated `UIWindow(frame:)` in `PaperTurnTests` now uses the host window scene and hides its window afterward.
- **Also fixed.** At launch, the selected tab item was laid out with provisional geometry (Read rode higher than Saved/Search). The tab container re-applies titles and selection once it joins a window.
