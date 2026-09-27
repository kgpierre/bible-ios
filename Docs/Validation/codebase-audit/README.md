# Codebase audit — 27 September 2026

Audit began on the working tree based on commit `3737991cb2ddd2f2f335dfa1fbe8e5d2aa6b28e9`, including uncommitted iPad/Duo changes. During execution another workstream committed that work as `929ca71bbde5e2755b06ffcb89544ad3ec025b0d` and added a four-line chapter-endpoint gesture guard plus a 15-line UI test. That final delta was inspected separately; results below identify the later runs. The five finding locations were unchanged. This audit did not change application code. Its only repository additions are this report, source fingerprints, and an isolated regression test retained as evidence outside the test targets.

Five actionable findings remain. P1 means resolve before release; P2 means a user-visible correctness issue. Evidence levels distinguish an executed reproduction from a source-level defect or concurrency analysis.

## Findings

### 1. P1 — Missing required-reason declaration for disk-space access

**Location:** `BibleReader/Resources/PrivacyInfo.xcprivacy:6`; API call at `BibleReader/Data/BibleStore.swift:159`.

The shipping migration backup checks `volumeAvailableCapacityForImportantUsageKey`. The app manifest declares only UserDefaults, and GRDB's bundled manifest declares no accessed API categories. Apple's required-reason rules require a DiskSpace declaration for this API. This is a submission-readiness defect, not evidence that the app transmits disk information.

Declare `NSPrivacyAccessedAPICategoryDiskSpace` with the approved reason matching the actual pre-write capacity check. `E174.1` describes checking capacity before writing and reporting insufficient space. Extend the packaged manifest test, which currently checks only UserDefaults.

**Evidence:** first-party call, packaged/source manifests, and [Apple required-reason documentation](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype). No App Store submission was attempted.

### 2. P2 — Cache pruning removes the destination chapter's annotations

**Location:** `BibleReader/Features/Reader/ReaderState.swift:262`.

`navigate` loads the destination's exact annotations before changing `chapterID`. When that insertion takes the cache above 24 chapters, `pruneLoadedAnnotations` retains only the old chapter and its immediate neighbors, removing the just-loaded distant destination. Rendering reads the missing entry as an empty annotation list. The current-page caches in both pagers prevent their neighbor preloads from repairing it.

**Executed reproduction:** after loading 24 annotation-cache keys, navigate to Leviticus 11 containing one exact highlight and one exact bookmark. Navigation succeeds and SQLite still contains both records, but the reader returns zero exact annotations and no bookmark indicator. Both display assertions fail; persistence assertions pass. This is disappearing annotation display, not deletion of user data.

Retain incoming chapter IDs while pruning, or prune after committing navigation. Add the retained [regression test](AuditProbeTests.swift) to the real test target when fixing it. The test ran against byte-identical application source in an isolated project copy, using Xcode 27.1 on an iPad simulator.

### 3. P2 — Scrolling fallback discards the active fold exclusion

**Location:** `BibleReader/App/AppRootView.swift:201`; related text geometry at `BibleReader/Features/Reader/NativeChapterView.swift:364`.

Automatic book mode and tabletop mode account for the active division, but their fallbacks do not. Turning off automatic book layout, choosing accessibility text, or failing the two-page width budget sends the full content region to the continuous reader. That reader constructs one centered text column without excluding the division. Tabletop similarly loses its reader-above-division layout at accessibility sizes.

The fold is known to be internal to this exact geometry: `ReaderFoldLayout` only returns a division strictly inside its bounds. Ordinary edge safe areas therefore do not account for this discarded interior strip. Text can run through the reserved fold area precisely when continuous scrolling is required.

Constrain the scrolling reader to a usable clear pane while preserving semantic position, selection, and the stored flat-screen preference. Keep continuous scrolling and every destination available at accessibility sizes.

**Evidence:** source control flow and installed SDK reserved-region declarations. This particular fallback was not exercised through live Device Hub pose changes during this audit. The separate absence of `.occlusion` handling remains a Duo acceptance gap; no specific occlusion failure is claimed.

### 4. P2 — An older Saved rebuild can replace a newer cache

**Location:** `BibleReader/Data/BibleStore.swift:635`.

`savedItems()` captures a generation, awaits concurrent resolution, and unconditionally publishes its result. An older rebuild A can overlap an edit and newer rebuild B. If B publishes first, it clears the dirty generations; A can then publish stale rows over B with no remaining dirty marker. Subsequent cache hits can keep returning the stale list until another edit or store reopen.

GRDB serializes individual database read closures, not the complete asynchronous resolver. `ReaderState` guards its own UI response, but that does not protect this store cache. Cancellation is not checked at publication either.

Validate generation/request identity before publishing, or coalesce/serialize rebuilds. Add a deterministic overlapping-rebuild test with controlled completion order.

**Evidence:** source-level concurrency analysis. The out-of-order scheduling interleaving was not reproduced in a runtime test; this is distinct from the executed pruning reproduction above.

### 5. P2 — Saved scroll position is not retained across size-class changes

**Location:** `BibleReader/App/AppRootView.swift:54`; `BibleReader/Features/Saved/SavedView.swift:14`.

Compact and regular layouts create separate Saved Lists in mutually exclusive structural branches. Crossing the size-class boundary destroys one list and creates another. Saved stores filter and sort in `AppState`, but has no shared visible-item/scroll anchor; a reader deep in a large Saved library returns to the top after resizing or folding across the boundary. Search already has an externally retained scroll ID.

Retain the visible Saved item identity and restore it in both presentations. Cover a long list, both directions of resizing, and filter/order preservation. Ordinary compact tab switches retain the view through the existing ZStack and are not the failure scenario.

**Evidence:** view identity and state-ownership analysis. No deep-Saved-list fold interaction was executed during this audit.

## Scope and positive evidence

Reviewed 47 application Swift files (7,122 lines before the final four-line guard), four Python content tools, storage/domain contracts, reader bridges and pagers, navigation, Search, Saved, source notes, appearance, summaries/questions, project configuration, privacy manifests, dependency pinning, and relevant test and handoff records. Test inventory comprises 16 Swift unit-test files, two UI-test files, and two Python test files. Counts are inventory, not a code-coverage percentage. [Initial fingerprints](source-fingerprints.json) identify the application/tool/configuration source for the initial broad runs; [final fingerprints](final-source-fingerprints.json) record the final inspected state including test sources.

The inspected implementation uses parameterized SQL and constrained FTS input; exact annotation edits and Undo use transactional/conflict-checked operations; migrations preserve existing stores and make protected backups; the corpus is bundled and pinned; source archive/XML validation is present; Debug test stores are isolated; summaries use on-device model sessions. No concrete persisted-data loss, injected-SQL path, app-operated backend, or first-party runtime networking was found in this review. Static inspection does not replace network capture or physical-device validation.

## Validation

Toolchain: Xcode **27.1 (27A9269)** at `/Users/kyle/Downloads/Xcode.app/Contents/Developer`, selected per command without changing system Xcode; iOS Simulator **27.1 SDK (24A94403)**; minimum deployment **26.0**. GRDB **7.11.1**, revision `b83108d10f42680d78f23fe4d4d80fc88dab3212`.

- Python corpus suite: **9 passed**. Includes all-verse independent extraction, corpus integrity, exact compressed payload agreement, and deterministic rebuild. Verified 66 books, 1,189 chapters, 31,102 source verses; logical SHA-256 `221de95d272cfe6b1aa3088f2e82ba4f8589211aca296d33bedf7d6b61ed23e0`.
- Debug build and unit suite on **iPhone 16e / iOS 26.0**: **90 passed, 0 failed, 2 skipped**. Skips are explicitly gated live-model refusal probes.
- Release simulator build: **passed**. Logs contain the non-blocking App Intents metadata-extraction warning; this is not a warning-free build claim.
- Isolated pruning regression on **iPad Pro 13-inch (M5) / iOS 26.0**: **1 test failed, 2 failed expectations**, reproducing finding 2 while confirming both saved records remained in SQLite.

- Full `BibleReaderUITests` class on **iPhone 16e / iOS 26.0**: **23 passed, 3 failed, 10 skipped**. The skips are device/pose-specific cases. The suite is not green.
- Six selected UI regressions on **iPad Pro 13-inch (M5) / iOS 26.0**: **6 passed, 0 failed, 0 skipped**. Covered top tabs/rotation, Saved-to-reader navigation, page/fold setting visibility, rapid spread turns/toolbar taps, Search/tab/rotation restoration, and spread chapter turns/exact highlight/Saved/return-to-scroll.
- After the concurrent four-line endpoint guard: **Release rebuild passed** and **1 endpoint UI regression passed** on iPhone 16e / iOS 26.0 (backward from Genesis 1 and forward from Revelation 22). The earlier complete unit/iPhone UI/iPad runs were not rerun in full after this focused delta.

### UI failures, separate from the five source findings

1. `testAboutShowsIdentityCreditsAndAttributions`, `BibleReaderUITests.swift:892`: could not find the author link through the `app.links` query. The source includes the link; an application defect versus offscreen/accessibility-query behavior is not established.
2. `testKeyVersesQuestionUsesCurrentBook`, `BibleReaderUITests.swift:716`: waited for an answer, but the captured UI displayed the model's refusal message. The chapter summary also displayed a generation error. The test unconditionally requires generative success; refusal/availability behavior must be distinguished from a deterministic correctness failure. The model guardrails were not changed or bypassed.
3. `testSavedFiltersDeletionUndoAndReturnToReader`: could not find a `savedItem-` Button after changing filter/sort. XCTest reported a Button/PopUpButton accessibility type mismatch and a SwiftUI reparenting warning. This audit does not infer deleted records from that lookup failure or equate it to the source-level Saved cache race.

One targeted rerun after the concurrent endpoint change produced **1 passed / 1 failed**: Saved filter/sort passed; About again failed the author-link assertion (now at line 907 because the new test shifted line numbers). The initial UI failure remains in the record; the retry does not make the full suite green. The model-success test was not repeatedly retried to seek a passing generation.

### Local evidence paths

Results reside under `/Users/kyle/Library/Developer/XcodeBuildMCP/workspaces/bible-ios-05d132857d5f/`:

- Unit suite: `result-bundles/test_sim_2026-09-27T16-33-01-859Z_pid32861_ffb16389.xcresult`.
- Full iPhone UI suite: `result-bundles/test_sim_2026-09-27T16-34-20-561Z_pid33608_3e982642.xcresult`.
- iPad regressions: `result-bundles/test_sim_2026-09-27T16-39-24-311Z_pid35833_728828be.xcresult`.
- About/Saved retry: `result-bundles/test_sim_2026-09-27T16-47-10-157Z_pid38446_48acdcd3.xcresult`.
- Release build: `logs/build_sim_2026-09-27T16-38-13-087Z_pid34682_360d7839.log`.
- Final endpoint UI regression: `result-bundles/test_sim_2026-09-27T16-50-21-898Z_pid38990_dafe328f.xcresult`.
- Final Release rebuild: `logs/build_sim_2026-09-27T16-50-31-938Z_pid39227_45b7347c.log`.
- Isolated pruning reproduction: `/private/tmp/bible-audit-probes/Pruning271.xcresult`; tested source copy `/private/tmp/bible-audit-probes/`.

### Reproduction commands

```sh
python3 -m unittest discover -s Content/Tests -v

DEVELOPER_DIR=/Users/kyle/Downloads/Xcode.app/Contents/Developer xcodebuildmcp simulator test \
  --project-path /Users/kyle/Developer/bible-ios/BibleReader.xcodeproj \
  --scheme BibleReader --configuration Debug \
  --simulator-id 00228CE2-2A4E-4687-ADF6-A83BA5C65C17 \
  --derived-data-path /private/tmp/bible-full-audit-build \
  --extra-args '-only-testing:BibleReaderTests' '-parallel-testing-enabled' 'NO'
```

The full iPhone UI run uses the same command with `-only-testing:BibleReaderUITests/BibleReaderUITests`. The Release build uses `simulator build`, `--configuration Release`, and `/private/tmp/bible-full-audit-release`. Simulator IDs are local simulator destinations, not physical-device identifiers.

For the pruning reproduction, copy the project, app, tests and Configuration into an isolated directory, add `AuditProbeTests.swift` to that copy's `BibleReaderTests` directory, and run only `BibleReaderTests/AuditProbeTests`. No production source patch or test weakening is required. The retained probe deliberately fails until the defect is fixed.

## Remaining acceptance boundaries

- No physical-device execution or new Duo Device Hub fold/unfold transitions in this audit. Existing static-pose evidence remains historical evidence. Interrupted turns during live folding, selection/saving during transitions, occlusion clearance, and physical ergonomics remain open.
- No fresh network capture or airplane-mode acceptance run. Corpus checks prove local content consistency, not runtime network behavior.
- Existing largest-type and interaction tests provide partial accessibility evidence. Manual VoiceOver, Switch Control, keyboard/pointer, contrast, and reduced-transparency acceptance remain separate.
- Live-model success/refusal is environment-dependent; deterministic tests do not establish factual correctness of every generated answer.
- No repository CI configuration was found. Local passing suites do not establish continuous regression protection.
- Storefront exclusion, distribution rights, donation mechanism, archive/signing, and physical-device release acceptance were not approved or revalidated by this code audit.

Prioritize the privacy declaration and reproduced annotation defect, then fold-safe scrolling, Saved cache publication, and Saved restoration. No fixes were applied as part of the audit.
