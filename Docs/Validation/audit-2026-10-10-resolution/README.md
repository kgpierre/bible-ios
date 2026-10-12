# Audit resolution · 10–11 October 2026 audit

11 October 2026 · Xcode 27.1 (27A9269) through per-command `DEVELOPER_DIR` · iOS 26.0 minimum · bundled corpus unchanged.

Responds to the findings and recommendations in [`../audit-2026-10-10/`](../audit-2026-10-10/reproduce.txt) (audited commit `57e5eff`). The audit's evidence directory is left unchanged.

## Findings

| ID | Change | Regression test (`BibleReaderTests/AuditRegressionTests.swift`) |
| --- | --- | --- |
| F1 | A spread turn adopts its pages only if the navigation revision is unchanged since it began (including during the pan, before UIKit reports the transition) and no navigation is pending. Stale or cancelled turns reconcile the pager with the reader. The animated completion Boolean is honored. | `testLateSpreadCompletionPreservesNewSameChapterNavigation`, `testCancelledSpreadTurnKeepsTheAnchor` |
| F2 | Source headings and trailing blocks get accessibility elements with TextKit geometry, ordered with verses by document location. They carry no annotation actions. | `testSourceHeadingsAreAccessibleInReadingOrder` (Psalm 23) |
| F3 | Background cleanup runs after a committed `upsert`/`delete`, best effort and across every file. It is retried when the library loads. Failures before commit still throw. | `testCommittedCardSaveAndDeleteSurviveCleanupFailure` |
| F4 | Widget links resolve the verse in the loaded chapter before navigating; links that repeat a parameter are rejected; links received before initial restoration wait for `isLoading` to finish. A newer link supersedes an older one still validating. | `testWidgetLinkRejectsNonexistentVerse`, `testWidgetLinkOpensAValidVerse`, `testWidgetLinkWaitsForRestoration`, `testWidgetLinksRejectRepeatedParameters` |
| F5 | The editor tracks its preparation task and a background generation. Presets, new images, and dismissal cancel older work; only the latest request commits, clears loading, or reports failure. | Not unit-tested; the logic is view state. Delayed-loader UI injection remains open. |
| F7 | "Background: Image Playground" appears beneath the card in the editor and Widgets list whenever the stored source is Image Playground, including after reopening. It is outside the card, so it never covers Scripture or attribution. | `testOnlyImagePlaygroundBackgroundsAreLabeledGenerated` |
| F6 | The Debug-only Saved-ordering test is gated by `#if DEBUG`; the performance test measures first Saved resolution only in Debug. | Release `build-for-testing` (below) |
| F8 | `SavedItem.shareText(editionLabel:)` uses the underlying exact reference and adds "(excerpt)" once. | `testSavedExcerptShareTextMarksExcerptOnce` |

## Recommendations implemented

- **Card file I/O off the main actor.** `CardLibraryWorker` (an actor) serializes library reads, writes, background storage, and cleanup. `CardsModel` publishes results on the main actor, rejecting an older result that finishes after a newer one. Save is disabled while saving. Latency at 100–1,000 image cards was not measured.
- **Lazy, bounded thumbnails.** Each Widgets row loads its own background while visible, downsampled to the preview's pixel size, through an `NSCache` limited to 24 images / 48 MB. Rows cancel loading when they scroll away.
- **Widget read errors.** `CardSelection` separates an unreadable library from no cards and a deleted card. Unreadable shows a neutral message and retries after 15 minutes; entity queries throw rather than report a configured card missing. Post-unlock WidgetKit recovery on a device is not yet verified.
- **Note markers.** `ReadingTypography.layout` excludes `showsNotes`. Toggling markers re-places gutter markers without rebuilding text or repaginating, and keeps the selection (`testNoteMarkerToggleKeepsTextAndSelection`).
- **Strict-concurrency warnings.** The Saved geometry transform reads a `Mutex`-backed height box instead of main-actor state. Release builds emit no Swift warnings.

## Deferred: measure first

These recommendations depend on device measurements the audit did not make; each is deliberately left unchanged.

- **Bound `BibleStore.exactByChapter`.** Requires a device stress run across all 1,189 chapters with a large annotation library to choose a budget.
- **Prune spread page controllers.** Requires profiling a full Psalm 119 traversal at the largest two-page size before choosing a cap.
- **Index current-book source retrieval.** The audit measured ~34 ms median in Debug on simulator, off the main actor; act only if device traces show contention on the store's executor.
- **CI matrix.** No provider is chosen. Needs an owner decision on host and how runners obtain Xcode 27.1.

## Test changes

- `testAboutShowsIdentityCreditsAndAttributions` looks up the credit by label across element types, as the audit's minimum-OS probe did.
- `testKeyVersesQuestionUsesCurrentBook` skips, rather than fails, when the live model declines and the app shows its refusal message. When an answer arrives, it still requires sources from John beyond chapter 3.

## Validation

| Run | Environment | Outcome |
| --- | --- | --- |
| Unit tests (`-only-testing:BibleReaderTests`) | iPad Pro 13-inch (M5) · iPadOS 27.0 simulator · Debug | 109 Swift Testing tests in 21 suites and 15 XCTest cases passed. |
| UI tests (`-only-testing:BibleReaderUITests`) | iPhone 18 Pro · iOS 27.0 (24A434) simulator · Debug | 31 passed, 0 failed, 11 skipped (iPad- and Duo-only cases). |
| iPad UI cases (10 selected) | iPad Pro 13-inch (M5) · iPadOS 27.0 simulator · Debug | 9 passed, including rapid spread turns, two-page chapter turn/restore, top tabs/rotation, Save Chapter → Make Widget, and widget links. `testSavedScrollSurvivesSizeClassChanges` skipped (its size-class precondition was not met). |
| Full scheme | iPhone 17 Pro · iOS 26.0 simulator · Debug | 109 Swift Testing tests and 15 XCTest unit cases passed. UI: 29 passed, 11 skipped (iPad/Duo-only), 2 failed, the same two the audit recorded on iOS 26 at `57e5eff`: the About credit selector (iOS 26 exposes it as a different element type) and the key-verses question (the live on-device model declined; the app showed its refusal message). |
| Those two tests after the test fix | iPhone 17 Pro · iOS 26.0, and iPhone 18 Pro · iOS 27.0 | iOS 26: About passed; key verses skipped (model declined again). iOS 27: both passed, including a real answer with sources beyond John 3. |
| Unit tests plus the 10 iPad UI cases | iPad Pro 13-inch (M5) · iPadOS 26.0 simulator · Debug | All unit tests passed. UI: 9 passed, `testSavedScrollSurvivesSizeClassChanges` skipped as on iPadOS 27. |
| Release `build-for-testing` with `ENABLE_TESTABILITY=YES` | iPad Pro 13-inch (M5) simulator | Succeeded; no Swift warnings. |

Not verified: actual Duo poses, physical VoiceOver reading of headings, live Image Playground output, widget behavior on a locked or newly unlocked device, Home/Lock Screen placement, and the delayed-photo ordering through the live picker.
