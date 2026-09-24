# Saved validation — 22 September 2026

Implemented filters, ordering, record-specific deletion, session Undo, and explicit refresh. Details: [decision 0011](../../Decisions/0011-saved-controls-and-deletion.md).

## Passing evidence

- iPhone 18 Pro / iOS 27: **62 tests passed** (61 non-UI, one Saved UI flow). Includes all newly added deletion/order tests: independent bookmark preservation, stale row/Undo rejection, atomic legacy-group deletion with injected write failure, unavailable legacy/exact recovery, failure Retry, and reading-position preservation. Result: `test_sim_2026-09-22T19-05-26-538Z_pid7782_66cce531.xcresult`.
- iPad Pro 13-inch M5 / iOS 27: live Saved recoloring and selected-item navigation passed. Its accompanying rotation test stopped at an ambiguous test selector (sidebar and popover both contained Old Testament). Scoped the helper to the popover.
- iPad mini A17 Pro / iOS 27: **three tests passed** after the hidden-reader lifecycle correction: initial-page invariant, existing page-transition persistence, and live Saved editing/navigation plus rotation back to compact Saved. Result: `test_sim_2026-09-22T20-12-22-488Z_pid10964_0f83b9b6.xcresult`.
- Unsigned device app and test-target builds passed before simulator validation. Later simulator runs compiled the final lifecycle correction.

Screenshots were exported from passing XCTest cases and visually inspected:

- [iPhone filter/sort and restored deletion](iphone-saved-undo.png)
- [iPad Saved beside the selected reader passage](ipad-saved-reader.png)

Final iPhone verification passed **two UI tests** after the lifecycle correction: Saved filtering/deletion/Undo and largest Dynamic Type in dark appearance. Result: `test_sim_2026-09-22T20-14-11-960Z_pid11431_0e568f7b.xcresult`. [Large-type controls](iphone-saved-large-dark.png) were visually inspected; native picker rows wrap and remain operable.

```sh
xcodebuildmcp simulator test --project-path /Users/kyle/Developer/bible-ios/BibleReader.xcodeproj --scheme BibleReader --simulator-name 'iPhone 18 Pro' --derived-data-path /Users/kyle/Developer/bible-ios/.build/SavedSimulator --extra-args '-only-testing:BibleReaderUITests/BibleReaderUITests/testSavedFiltersDeletionUndoAndReturnToReader' '-only-testing:BibleReaderUITests/BibleReaderUITests/testSavedFiltersAtLargestTypeInDarkAppearance' '-parallel-testing-enabled' 'NO'
```

## Remaining issue

The broader iPad mini `testIPadWideAndNarrowRestoration` reported a first-visible-verse mismatch after rotation (Psalm 119:9 versus 119:10). This is separate from the corrected crash when compact Saved mounts an inactive reader. The test was not relaxed. Physical-device behavior, complete VoiceOver/pointer evaluation, and release acceptance remain open.

The failed iPad mini run is retained as `test_sim_2026-09-22T20-03-07-021Z_pid10236_90440cdd.xcresult`; it includes the now-corrected page-controller crash and the outstanding restoration mismatch. Do not treat that run as passing.

## Commands

```sh
xcodebuildmcp simulator test --project-path /Users/kyle/Developer/bible-ios/BibleReader.xcodeproj --scheme BibleReader --simulator-name 'iPhone 18 Pro' --derived-data-path /Users/kyle/Developer/bible-ios/.build/SavedSimulator --extra-args '-only-testing:BibleReaderTests' '-only-testing:BibleReaderUITests/BibleReaderUITests/testSavedFiltersDeletionUndoAndReturnToReader' '-parallel-testing-enabled' 'NO'

xcodebuildmcp simulator test --project-path /Users/kyle/Developer/bible-ios/BibleReader.xcodeproj --scheme BibleReader --simulator-name 'iPad mini (A17 Pro)' --derived-data-path /Users/kyle/Developer/bible-ios/.build/SavedSimulator --extra-args '-only-testing:BibleReaderTests/PaperTurnTests' '-only-testing:BibleReaderUITests/BibleReaderUITests/testIPadSavedUpdatesAlongsideReader' '-parallel-testing-enabled' 'NO'
```

Result bundles and full logs are under `~/Library/Developer/XcodeBuildMCP/workspaces/bible-ios-05d132857d5f/`. Tests use isolated temporary stores; no real user database was reset.
