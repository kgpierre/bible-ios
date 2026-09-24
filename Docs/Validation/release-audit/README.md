# Release audit validation — 22 September 2026

Xcode 27, iOS/iPadOS 27 simulators: iPhone 18 Pro and iPad mini (A17 Pro). Unsigned device Release build; no physical-device or App Store validation. Local result bundles are under `~/Library/Developer/XcodeBuildMCP/workspaces/bible-ios-05d132857d5f/result-bundles/` and are not committed.

## Passing evidence

- `test_sim_2026-09-22T21-18-33-772Z_pid15119_d9c88987.xcresult`: all **66 non-UI tests** passed, including storage/migrations, exact annotation conflict handling, privacy manifest, accessibility frame, high-contrast palette, native UndoManager, and streaming cancellation. The Saved iPad rotation flow passed. The two other UI failures in that bundle are superseded below.
- `test_sim_2026-09-22T21-00-58-374Z_pid13966_6a23b2f5.xcresult`: four iPhone UI flows passed: native selection, Saved filter/deletion/Undo, Books/collapsing labels, and picker selection/highlight indicators. A reverse-swipe failure in this bundle led to suppressing the compact split-view back gesture.
- `test_sim_2026-09-22T21-04-49-065Z_pid14510_c325d01b.xcresult`: **9/9 passed** (eight summary tests and integrated forward/reverse chapter turns, explicit navigation, and relaunch).
- `test_sim_2026-09-22T22-36-35-328Z_pid16283_501cadeb.xcresult`: Search query/navigation survives wide-to-narrow iPad rotation. The still-failing Psalm 119 first-visible check in this bundle is superseded by the next entry.
- `test_sim_2026-09-22T22-38-44-335Z_pid16789_9bb68952.xcresult`: the unchanged Psalm 119 first-visible assertion passes after retaining the settled anchor through passive resizing. This resolves the previously documented one-verse discrepancy from the Saved pass.
- `test_sim_2026-09-22T22-40-25-425Z_pid17237_64fb4aba.xcresult`: **2/2 final iPad UI checks passed**, repeating both Psalm 119 restoration and Search resizing with the final toolbar.
- Final unsigned Release rebuild succeeded (`build_device_2026-09-22T22-41-58-537Z_pid17673_dca602ce.log`); the packaged app's own privacy manifest includes UserDefaults CA92.1, tracking false, and empty collected-data/tracking-domain lists. The only build warning was skipped AppIntents metadata extraction because the app does not depend on AppIntents.

## Commands

Commands use the repository root and the available simulator names; no personal device IDs or signing settings are required.

```sh
xcodebuildmcp simulator test --project-path "$PWD/BibleReader.xcodeproj" --scheme BibleReader --simulator-name 'iPad mini (A17 Pro)' --derived-data-path "$PWD/.build/AuditSimulator" --extra-args '-only-testing:BibleReaderTests' '-only-testing:BibleReaderUITests/BibleReaderUITests/testIPadWideAndNarrowRestoration' '-only-testing:BibleReaderUITests/BibleReaderUITests/testIPadSavedUpdatesAlongsideReader' '-only-testing:BibleReaderUITests/BibleReaderUITests/testSearchSurvivesIPadResize' '-parallel-testing-enabled' 'NO'
xcodebuildmcp simulator test --project-path "$PWD/BibleReader.xcodeproj" --scheme BibleReader --simulator-name 'iPhone 18 Pro' --derived-data-path "$PWD/.build/AuditSimulator" --extra-args '-only-testing:BibleReaderTests/ChapterSummaryTests' '-only-testing:BibleReaderUITests/BibleReaderUITests/testIntegratedPaperTurnsAndRelaunch' '-parallel-testing-enabled' 'NO'
xcodebuildmcp device build --project-path "$PWD/BibleReader.xcodeproj" --scheme BibleReader --configuration Release --derived-data-path "$PWD/.build/AuditRelease" --extra-args CODE_SIGNING_ALLOWED=NO
plutil -p .build/AuditRelease/Build/Products/Release-iphoneos/BibleReader.app/PrivacyInfo.xcprivacy
```

The first command records the full suite; use just the named UI selectors for focused corrective reruns. `xcstringstool sync` ingests the compiler's app-target `.stringsdata` into `Localizable.xcstrings`, retaining existing catalog entries.

## Visual checks and limits

Reviewed exported simulator screenshots of the compact reader, native selection menu, picker, and iPad Search. `iphone-reader.png` shows the compact back button removed. `iphone-selection.png` and `iphone-picker.png` are from the earlier passing selection/picker run. `ipad-search.png` and `ipad-restored.png` capture the final passing iPad Search and reader-restoration flows.

These are static captures, not evidence of animation quality or accessibility gesture behavior. Actual VoiceOver/Switch Control/Voice Control, Reduce Motion/Transparency, hardware shortcuts/Undo gestures, protected background writes after lock, and real Apple Intelligence generation remain device acceptance checks. Performance changes are implementation improvements without measured latency/energy claims. WAL/pool and corpus/index-format work remains explicitly scoped in [decision 0012](../../Decisions/0012-release-audit.md).
