# Bible Reader

A native, private, offline Bible reader for iPhone and iPad. The current build bundles the configured **66-book KJV corpus: 1,189 chapters and 31,102 verses**. Chapters load individually from a read-only SQLite database. Exact selected-word highlights/bookmarks and reading position persist in a separate device-local database.

The reader retains the selected 2a composition, native continuous selection, margin verse numbers, floating glass controls, and wide/narrow iPad navigation. First install opens Genesis 1; subsequent launches restore the saved passage. About is available in More. The separate Books button opens a native Old/New Testament browser with brief editorial descriptions. The passage button opens chapters or a direct reference. Bottom tab labels collapse while scrolling down and return on upward scrolling; accessibility sizes retain labels. Previous/next chapter and session Undo are in More. Saved shows exact excerpts with their references and retains legacy whole-verse annotations. Native selection-menu colors and Bookmark save immediately; Undo remains in More.

Search works entirely offline with actual result counts, 50-result pages, matched excerpts, and direct references such as `Jn 3:16–18` or `Jude 5`. Ordinary words use AND; quoted phrases preserve word order. Typo suggestions require a tap. Search state stays in memory across destination changes and iPad resizing; query history is not saved to disk.

Appearance preferences persist locally: system/light/dark, serif/system sans, modest text-size adjustment, and line spacing, composed with Dynamic Type. The icon-only Apple Intelligence button opens a separate overview of the current chapter using the on-device Foundation Models model. Availability depends on device, settings, language/region, and model readiness; initial model setup may require an OS-managed download. No remote inference fallback or summary persistence is added.

**Still in development:** richer Saved filters/deletion controls, footnote presentation, summary quality and performance on eligible physical devices, and complete accessibility/device/privacy acceptance. A Debug-only native page-curl experiment is available in More; it remains isolated from normal reading and needs visual/device acceptance. See [the execution plan](Docs/Decisions/0005-thin-paper-turn.md). Final canon and distribution rights/territories require review before publishing.

Current owner priority: **refine iPhone text selection and highlights first**; further iPad refinement is deferred. Latest changes and detailed verification: [HANDOFF.md](HANDOFF.md).

The iPhone palette marks the selected color, offers removal only for highlighted text, and preserves native selection through a Saved round trip. Failed annotation writes support Retry with the original exact-word intent. Latest verification: 34 unit tests and three focused iPhone UI tests passed, plus an unsigned device build. [Selection evidence](Docs/Decisions/0006-exact-annotations-and-summary.md#iphone-selection-refinement).

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
