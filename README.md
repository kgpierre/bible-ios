# Bible

**Bible** (bundle ID `dev.kpierre.bible`; the Xcode project, target, and scheme are still named `BibleReader`) is a native, private, offline Bible reader for iPhone and iPad, iOS/iPadOS 26.0 and later. It bundles the **66-book King James Version: 1,189 chapters and 31,102 verses**. Chapters load individually from a read-only SQLite database. Exact selected-word highlights and bookmarks, and the reading position, persist in a separate database on the device.

The reader keeps the selected 2a composition: native continuous selection, margin verse numbers, floating glass controls, and wide and narrow iPad navigation. First install opens Genesis 1; later launches restore the saved passage. The passage button opens the chapter picker, which leads to Books (a native Old/New Testament browser with brief editorial descriptions) and direct references. There is no separate Books button; the owner removed it. Chapters turn with a finger-following page curl, or immediately with Reduce Motion, VoiceOver, and similar settings. Bottom tab labels collapse while scrolling down and return when scrolling up; they stay visible at accessibility sizes. More holds Search, previous and next chapter, session Undo (last 100 changes), Chapter notes, sharing, and About.

Native selection-menu colors and Bookmark save immediately. Saved lists exact excerpts with their references and keeps legacy whole-verse annotations. It filters with one-tap All/Highlights/Bookmarks segments, sorts by most recent or Bible order, and supports deletion with Undo. Verses with marginal notes from the source edition show a small dot beside the verse number. Tap the number to read the notes. Notes are never part of verse text, copy, or search.

Search works entirely offline, with actual result counts, 50-result pages, matched excerpts, and direct references such as `Jn 3:16–18` or `Jude 5`. Ordinary words use AND; quoted phrases keep word order. Typo suggestions require a tap. Search state stays in memory across destination changes and iPad resizing; query history is not saved to disk.

Appearance preferences persist locally and compose with Dynamic Type: system, light, or dark theme; serif or system sans; modest text-size adjustment; line spacing; and whether to show source notes. The icon-only Apple Intelligence button opens an overview of the current chapter, with follow-up questions, from the on-device Foundation Models model. Availability depends on the device, settings, language and region, and model readiness. There is no remote inference fallback, and summaries are not saved.

**Scripture rights.** The text is public domain outside the United Kingdom. In the UK, Crown rights apply, so the app is not distributed there without Cambridge University Press's permission. See [decision 0015](Docs/Decisions/0015-release-identity-and-scripture-rights.md).

**Still open before release:**

- physical-device acceptance: selection feel, page-turn feel, performance, and real-model summary quality ([locked-device protection](Docs/Validation/locked-device/README.md) passed on 27 September);
- assistive-technology passes;
- an offline network capture;
- App Store Connect setup: UK exclusion and privacy answers;
- the donation link decision.

Latest changes and verification: [HANDOFF.md](HANDOFF.md).

The iPhone palette displays color swatches with a selected checkmark, offers removal only for highlighted text, and preserves native selection through a Saved round trip. A short hold starts word selection; native handles still extend the range. The side-by-side destinations use a native UIKit tab bar within the SwiftUI layout. Failed annotation writes support Retry with the original exact-word intent. The 22 September iOS 27 pass includes 35 non-UI tests and six focused UI tests, plus an unsigned device build. [Current evidence and limitations](Docs/Decisions/0007-iphone-reader-interactions.md).

## Setup

- Tested: Xcode **27.0 (27A266a)**, Swift **6.4**, Swift 6 language mode with complete concurrency checking.
- Deployment minimum: iOS/iPadOS **26.0** (owner decision, 26 September 2026).
- Open `BibleReader.xcodeproj` and select the shared **BibleReader** scheme.
- GRDB **7.11.1** is pinned in the project and shared `Package.resolved`. Internet access is needed once to resolve this development dependency; the running reader does not fetch Scripture or dependencies.
- The app and test targets use the owner's signing team (`AVER2M3454`) with automatic signing; other developers substitute their own team. No signing credentials are stored here.

```sh
xcodebuild -resolvePackageDependencies -project BibleReader.xcodeproj -scheme BibleReader
xcodebuild -showdestinations -project BibleReader.xcodeproj -scheme BibleReader
```

If Xcode shows `missing package product 'GRDB'`, choose **File → Packages → Resolve Package Versions**. Package resolution and an unsigned generic iPhone build have been verified using Xcode's standard cache.

## Build and test

Run from the repository root. Use a fresh result-bundle name for each test run and substitute an installed simulator as necessary.

```sh
xcodebuild build -project BibleReader.xcodeproj -scheme BibleReader \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project BibleReader.xcodeproj -scheme BibleReader \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' \
  -derivedDataPath .build/DerivedData -resultBundlePath .build/Reader-iPhone.xcresult \
  -collect-test-diagnostics never
xcodebuild test -project BibleReader.xcodeproj -scheme BibleReader \
  -destination 'platform=iOS Simulator,name=iPad mini (A17 Pro),OS=26.0' \
  -derivedDataPath .build/DerivedData -resultBundlePath .build/Reader-iPad.xcresult \
  -collect-test-diagnostics never
python3 Content/Tools/validate_corpus.py
```

`CODE_SIGNING_ALLOWED=NO` verifies compilation, not installation/signing. Sandboxed automation needs access to Xcode macro plugins and CoreSimulator. See [content tooling](Content/README.md) for explicit source acquisition and deterministic import; ordinary app builds never run that pipeline.

### 22 September interaction verification

The focused iPhone command uses isolated test stores and does not reset ordinary user data:

```sh
xcodebuild test -project BibleReader.xcodeproj -scheme BibleReader \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' \
  -clonedSourcePackagesDirPath .build/SourcePackages \
  -derivedDataPath .build/ContentDerivedData \
  -resultBundlePath .build/Reader-refinement-final.xcresult \
  -only-testing:BibleReaderTests \
  -only-testing:BibleReaderUITests/BibleReaderUITests/testNativeSelectionMenu \
  -only-testing:BibleReaderUITests/BibleReaderUITests/testExactHighlightRecolorRemovalAndUndo \
  -only-testing:BibleReaderUITests/BibleReaderUITests/testIntegratedPaperTurnsAndRelaunch \
  -only-testing:BibleReaderUITests/BibleReaderUITests/testNativeTabTrackingAndCancelledTurn \
  -collect-test-diagnostics never
xcodebuild build -project BibleReader.xcodeproj -scheme BibleReader \
  -configuration Release -destination 'generic/platform=iOS' \
  -clonedSourcePackagesDirPath .build/SourcePackages \
  -derivedDataPath .build/DeviceDerivedData CODE_SIGNING_ALLOWED=NO
```

The focused command passed 35 non-UI tests and four UI tests. The iOS 26 compatibility pass includes 35 non-UI tests and six UI tests; the iPadOS 26 regression pass includes 35 non-UI tests and two UI tests. The unsigned Release build passed. Physical-device tests did not execute because test-target signing teams are unconfigured; project signing was left unchanged. See [decision 0007](Docs/Decisions/0007-iphone-reader-interactions.md) for individual result bundles and outstanding acceptance.

## Organization

| Path | Responsibility |
| --- | --- |
| `BibleReader/App/` | Composition, navigation, scene lifecycle |
| `BibleReader/Features/` | Native reader, chapter picker, annotation editor, appearance |
| `BibleReader/Domain/` | Semantic chapter documents, verse anchors, storage models |
| `BibleReader/Data/` | Actor-isolated GRDB access, migrations, store location |
| `BibleReader/Resources/` | Corpus, provenance/notices, semantic colors, localization |
| `BibleReaderTests/`, `BibleReaderUITests/` | Swift Testing and native interaction/relaunch checks |
| `Content/` | Pinned source, importer, source-derived inventory, tests/reports |
| `Design/Reference/` | Unchanged original design exports |
| `Docs/Decisions/` | Implementation decisions, evidence, limitations |

The Xcode synchronized groups include app/test files automatically. Keep source archives, tooling, and design exports outside the app target. The earlier `PrototypeChapters.json` is retained for regression tests in Debug and excluded from Release; it is not the app's content source.

## Data and contribution rules

Use four-space Swift indentation, feature-focused views, explicit state ownership, public Apple APIs, and cancellation-aware tasks. No external formatter is configured. Add tests for behavior/data risks; never weaken tests merely to pass. Keep changes focused and report actual validation.

`Application Support/ReaderData/User.sqlite` contains annotations and reading position. It is eligible for normal OS backup and uses complete file protection. Never remove it to resolve an error. The v1 migration creates the legacy schema; additive v2 adds exact annotations while retaining legacy tables and records; additive v3 indexes exact annotations by chapter. Before a pending migration, an existing store is copied to `User-before-migration.sqlite` (Complete protection, excluded from device backup, replaced by the next migration's copy). Unknown future migrations and corrupt stores fail without resetting data. The old prototype held annotations only in memory, so there is no earlier on-disk prototype schema to migrate.

Full requirements: [AGENTS.md](AGENTS.md). Previous reusable guide: [iOS development guidelines](Docs/IOS-DEVELOPMENT-GUIDELINES.md). Current engineering evidence: [offline corpus and persistence](Docs/Decisions/0003-offline-corpus-and-persistence.md). Source/asset provenance and unresolved distribution review are documented; no release, signing, physical-device, or privacy-audit approval is implied.

### Summary and book questions (22 September 2026)

The AI sheet now follows the supplied Summary/Questions reference: scalable serif text, question preview, quiet disclosure, question bubbles, source-reference chips, and native Liquid Glass input/suggestions. Follow-up questions stay within the captured book and use bounded passages from the bundled corpus. Sources open the actual reader verse. Requests and answers undergo separate scope/support checks; these reduce prompt-injection risk but do not guarantee factual accuracy or prevention. Sessions remain on-device and unpersisted. Details: [decision 0008](Docs/Decisions/0008-summary-and-book-questions.md).

Summary validation: [screenshots and results](Docs/Validation/summary-redesign/README.md). Successful final full iPhone command (use a fresh result path when rerunning):

```sh
xcodebuild test -project BibleReader.xcodeproj -scheme BibleReader \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' \
  -clonedSourcePackagesDirPath .build/SourcePackages -derivedDataPath .build/ContentDerivedData \
  -resultBundlePath .build/Summary-final-phone.xcresult \
  -only-testing:BibleReaderTests \
  -only-testing:BibleReaderUITests/BibleReaderUITests/testChapterSummaryAvailabilityAndDismissal \
  -only-testing:BibleReaderUITests/BibleReaderUITests/testBookQuestionsAndScope \
  -only-testing:BibleReaderUITests/BibleReaderUITests/testSummaryLargestTypeDark \
  -collect-test-diagnostics never
```

The vertical input alignment fix then passed the latter two UI tests in `.build/Summary-alignment-phone.xcresult`. Final unsigned device build:

```sh
xcodebuild build -project BibleReader.xcodeproj -scheme BibleReader -configuration Release \
  -destination 'generic/platform=iOS' -clonedSourcePackagesDirPath .build/SourcePackages \
  -derivedDataPath .build/DeviceDerivedData CODE_SIGNING_ALLOWED=NO
```

### Chapter picker and reader performance follow-up

The chapter picker follows the owner’s updated design using native Liquid Glass, scalable serif chapter controls, and saved-highlight rings/dots. Annotation edits now use chapter-scoped caches, immediate pending rendering with rollback, incremental Saved resolution, and revision-based renderer updates. Ordinary scrolling no longer starts a page curl. Key-verse questions can return actual bundled quotations from the current book.

Validation: [chapter picker](Docs/Validation/chapter-picker/README.md), [reader follow-ups](Docs/Validation/reader-followups/README.md), and [performance scope](Docs/Decisions/0010-reader-performance-followup.md). Final iPhone verification passed 53 non-UI tests and three UI flows; unsigned Release compilation passed. Repeat iPad rotation validation and physical-device profiling remain outstanding.

```sh
xcodebuild test -project BibleReader.xcodeproj -scheme BibleReader \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' \
  -clonedSourcePackagesDirPath .build/SourcePackages -derivedDataPath .build/ContentDerivedData \
  -resultBundlePath .build/Reader-followups-phone.xcresult \
  -only-testing:BibleReaderTests \
  -only-testing:BibleReaderUITests/BibleReaderUITests/testKeyVersesQuestionUsesCurrentBook \
  -only-testing:BibleReaderUITests/BibleReaderUITests/testBooksAtLargeTypeInDarkAppearance \
  -only-testing:BibleReaderUITests/BibleReaderUITests/testSearchAndReferenceNavigation \
  -collect-test-diagnostics never
```

Use a fresh result-bundle path when rerunning.

### Reader polish validation — 22 September 2026

Successful unsigned app and test-target compilation:

```sh
xcodebuildmcp device build --project-path /Users/kyle/Developer/bible-ios/BibleReader.xcodeproj --scheme BibleReader --derived-data-path /Users/kyle/Developer/bible-ios/.build/RefinementDerivedData --extra-args CODE_SIGNING_ALLOWED=NO --build-for-testing
```

Three `ChapterSwipeIntentTests` scenarios also passed using the production intent struct and assertions in a temporary host Swift harness. This does not exercise UIKit recognizers. XcodeBuildMCP reported zero installed simulators, so native UI execution, visual review, resizing, and actual Apple Intelligence behavior remain unverified for this pass. The regression suite now covers retained summary content, picker dismissal, the chapter-picker Books route, and model refusal handling; those native tests were compiled, not executed.

### Saved implementation validation

Saved filters, canonical/recent ordering, record-specific deletion, Retry, and session Undo are implemented. The iPhone suite passed 62 tests; the corrected iPad mini Saved rotation and page lifecycle checks passed three tests. The separate first-visible-verse restoration mismatch remains open. See [Saved validation and exact commands](Docs/Validation/saved/README.md) and [decision 0011](Docs/Decisions/0011-saved-controls-and-deletion.md).

### Release audit validation (22 September 2026)

The audit pass adds an app privacy manifest, accessibility and localization corrections, stronger highlight variants, storage/Saved optimizations, streamed summary drafts, system Undo/commands, and stable reader resizing. See [decision 0012](Docs/Decisions/0012-release-audit.md) for implemented versus deferred items and [validation](Docs/Validation/release-audit/README.md) for exact commands and passing evidence (66 non-UI tests, focused iPhone/iPad UI flows, and an unsigned Release build). This does not establish release or physical-device acceptance.

### Visual and performance audit (25 September 2026)

See [decision 0013](Docs/Decisions/0013-visual-and-performance-audit.md). Xcode's iOS 27.0 simulator runtime; Debug; derived data `.build/AuditDD`.

```sh
xcodebuild test -project BibleReader.xcodeproj -scheme BibleReader -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' -only-testing:BibleReaderTests -collect-test-diagnostics never
xcodebuild test -project BibleReader.xcodeproj -scheme BibleReader -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' -only-testing:BibleReaderUITests -collect-test-diagnostics never
xcodebuild test -project BibleReader.xcodeproj -scheme BibleReader -destination 'platform=iOS Simulator,name=iPad mini (A17 Pro),OS=27.0' -only-testing:BibleReaderUITests/BibleReaderUITests/testIPadWideAndNarrowRestoration -only-testing:BibleReaderUITests/BibleReaderUITests/testIPadSavedUpdatesAlongsideReader -only-testing:BibleReaderUITests/BibleReaderUITests/testSearchSurvivesIPadResize -collect-test-diagnostics never
```

Results: 67 unit tests passed (including the new italic-kerning regression). iPhone 18 Pro UI suite: 22 passed, 3 iPad-only tests skipped. The three iPad resize/Saved/Search tests passed on iPad mini. On iPad Pro 13-inch, two of them fail by design: portrait is already wide (1032 points, at least the 920-point breakpoint), so the compact tabs they wait for never appear. Build had no compiler warnings. Screenshots came from a temporary XCUITest tour that was not committed. No physical-device checks were run.

### Compact corpus, About, and interactive paper turn (25 September 2026)

See [decision 0013](Docs/Decisions/0013-visual-and-performance-audit.md) (compact corpus and About follow-up) and [decision 0014](Docs/Decisions/0014-interactive-paper-turn.md). The rebuilt corpus is 16 MB, down from 34 MB, with an identical logical revision. Rebuild and validate it with:

```sh
python3 Content/Tools/build_corpus.py
python3 Content/Tools/validate_corpus.py
```

Results:

- Corpus validation passed 9 of 9 checks with Python 3.13.14 and SQLite 3.53.1.
- iPhone 18 Pro (iOS 27.0): 68 unit tests passed, and the UI suite passed 23 tests with 3 iPad-only skips.
- iPad mini (A17 Pro): all four resize, Saved, Search, and turn tests passed.

No physical-device checks were run.

### Summaries, source notes, large libraries, and search paging (26 September 2026)

See [decision 0015](Docs/Decisions/0015-release-identity-and-scripture-rights.md) (bundle ID, name, OS, rights, canon, icon) and [decision 0016](Docs/Decisions/0016-continuation-summaries-notes-saved-search.md). Xcode 27.0, iPhone 18 Pro simulator on iOS 27.0, Debug:

```sh
xcodebuild test -project BibleReader.xcodeproj -scheme BibleReader \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' \
  -clonedSourcePackagesDirPath .build/SourcePackages -derivedDataPath .build/ContentDerivedData \
  -resultBundlePath .build/Continuation-0926-iphone.xcresult -collect-test-diagnostics never
```

Results:

- **Unit and UI suites.** 77 unit tests passed; the two real-model probe tests are disabled by default. The UI suite passed 24 of 27 tests with 3 iPad-only skips, including the new Chapter notes flow and the segmented Saved controls. The two performance UI benchmarks passed. There were no compiler warnings.
- **Real-model summary probe.** Run with `TEST_RUNNER_BIBLE_MODEL_PROBE=1` and `-only-testing:BibleReaderTests/SummaryRefusalProbeTests`. Before the fix, 12 of 20 difficult chapters were refused; after it, 20 of 20 succeeded. 4 of 5 questions were answered.
- **Optimized benchmark** (the `PerformanceAuditTests` command in `Docs/Validation/performance-audit/README.md`), with 10,000 saved items:
  - the reader's annotation load dropped to 2.0 ms, from a 51.5 ms whole-library decode;
  - a chapter load during a Saved rebuild took 3.3 ms;
  - a first full Saved resolution took 133 ms, now off the store queue;
  - a search page at offset 10,000 took 3.2 ms, down from 67.7 ms.
- **Corpus rebuild.** `python3 Content/Tools/build_corpus.py && python3 Content/Tools/validate_corpus.py` passed 9 of 9 checks. The database bytes are identical; only the manifest and notice changed.

No physical-device checks were run. The locked-device procedure is ready but still needs the owner's iPhone.
