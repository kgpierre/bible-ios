# Bible Reader

A native, private, offline Bible reader for iPhone and iPad. The current build bundles the configured **66-book KJV corpus: 1,189 chapters and 31,102 verses**. Chapters load individually from a read-only SQLite database. Exact selected-word highlights/bookmarks and reading position persist in a separate device-local database.

The reader retains the selected 2a composition, native continuous selection, margin verse numbers, floating glass controls, and wide/narrow iPad navigation. First install opens Genesis 1; subsequent launches restore the saved passage. About is available in More. The separate Books button opens a native Old/New Testament browser with brief editorial descriptions. The passage button opens chapters or a direct reference. Bottom tab labels collapse while scrolling down and return on upward scrolling; accessibility sizes retain labels. Previous/next chapter and session Undo are in More. Saved shows exact excerpts with their references and retains legacy whole-verse annotations. Native selection-menu colors and Bookmark save immediately; Undo remains in More.

Search works entirely offline with actual result counts, 50-result pages, matched excerpts, and direct references such as `Jn 3:16–18` or `Jude 5`. Ordinary words use AND; quoted phrases preserve word order. Typo suggestions require a tap. Search state stays in memory across destination changes and iPad resizing; query history is not saved to disk.

Appearance preferences persist locally: system/light/dark, serif/system sans, modest text-size adjustment, and line spacing, composed with Dynamic Type. The icon-only Apple Intelligence button opens a separate overview of the current chapter using the on-device Foundation Models model. Availability depends on device, settings, language/region, and model readiness; initial model setup may require an OS-managed download. No remote inference fallback or summary persistence is added.

**Still in development:** richer Saved filters/deletion controls, footnote presentation, summary quality and performance on eligible physical devices, and complete accessibility/device/privacy acceptance. Native paper curls now turn chapters in the main reader; the separate experiment has been removed. Physical-device interaction/performance acceptance remains open. See [reader interaction changes](Docs/Decisions/0007-iphone-reader-interactions.md). Final canon and distribution rights/territories require review before publishing.

Current owner priority: **refine iPhone text selection and highlights first**; further iPad refinement is deferred. Latest changes and detailed verification: [HANDOFF.md](HANDOFF.md).

The iPhone palette displays color swatches with a selected checkmark, offers removal only for highlighted text, and preserves native selection through a Saved round trip. A short hold starts word selection; native handles still extend the range. The side-by-side destinations use a native UIKit tab bar within the SwiftUI layout. Failed annotation writes support Retry with the original exact-word intent. The 22 September iOS 27 pass includes 35 non-UI tests and six focused UI tests, plus an unsigned device build. [Current evidence and limitations](Docs/Decisions/0007-iphone-reader-interactions.md).

## Setup

- Tested: Xcode **27.0 (27A266a)**, Swift **6.4**, Swift 6 language mode with complete concurrency checking.
- Proposed deployment minimum: iOS/iPadOS **26.0**.
- Open `BibleReader.xcodeproj` and select the shared **BibleReader** scheme.
- GRDB **7.11.1** is pinned in the project and shared `Package.resolved`. Internet access is needed once to resolve this development dependency; the running reader does not fetch Scripture or dependencies.
- Configure your own signing team/device in Xcode for an iPhone build. No signing credentials are stored here.

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

`Application Support/ReaderData/User.sqlite` contains annotations and reading position. It is eligible for normal OS backup and uses complete file protection. Never remove it to resolve an error. The v1 migration creates the legacy schema; additive v2 adds exact annotations while retaining legacy tables/records. Unknown future migrations and corrupt stores fail without resetting data. The old prototype held annotations only in memory, so there is no earlier on-disk prototype schema to migrate.

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
