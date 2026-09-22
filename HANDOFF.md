# Bible Reader — Development Handoff

Updated 22 September 2026 after the owner-requested iPhone interaction/performance pass. Repository: `/Users/kyle/Developer/bible-app`.

## Latest continuation — 22 September 2026

The owner requested quicker phone selection, visible highlight **swatches instead of color-name text**, paper curls in normal reading with the experiment removed, and native tab interaction while **keeping all bottom controls side by side**. These newer instructions supersede the old Debug-only paper-turn direction below.

Implemented: 0.3-second word-selection start with native handles/edit menus; semantic-color swatches and accessible names/checkmarks; integrated chapter curls; native `UITabBar` within the compact adjacent-control layout; retained compact destination views; cancellation-safe position flushes; a six-chapter decoded cache; SQL-only position validation; lazy Saved loading; and reduced per-frame/repeated text work. The audit's false save-error diagnosis was confirmed. Durable annotation writes, complete file protection, existing schema, and Scripture resources are preserved.

The iOS 27 performance bundle passed **35 non-UI tests and six UI tests**, including selection/recolor/Undo, Books/scrolling, turns/relaunch, and appearance. The iOS 26 compatibility bundle also passed **35 non-UI and six UI tests**, including native tab drag tracking, a short edge-drag cancellation check, Search, and largest-type dark Books. Physical-phone testing was attempted but did not run: test-target signing teams are unconfigured, and Xcode's interactive tool offered only simulators. Signing settings were not changed.

The final iOS 27 pass also passed **35 non-UI and four UI tests** after the last swatch/transition adjustments. The iPadOS 26 resize/selection regression passed **35 non-UI and two UI tests**. Unsigned Debug and Release device builds passed. Final screenshots are in `Docs/Validation/iPhone-reader-refinement/`.

Read [decision 0007](Docs/Decisions/0007-iphone-reader-interactions.md) for implementation, current evidence, and remaining device gates. The older continuation sections below are historical; this latest section and decision 0007 take precedence.

## Current owner priority

**Focus on refining the iPhone version for now, specifically text selection and highlights.** The owner gave this steering during the continuation. Do not expand into further iPad refinement without a new request. The last running iPad batch was stopped when this instruction arrived; its partial results are not a complete pass.

Read this document, `AGENTS.md`, and the relevant implementation before editing. Continue the existing native app; do not regenerate the corpus. This is development evidence, not release approval.

## Latest owner decisions

1. **Books/navigation:** separate Books button to the right of Read/Saved/Search, SF Symbols, labels collapse on downward scrolling and return upward. Keep labels at accessibility sizes. Books uses Old/New Testament selection and native subtitle rows. Keep the passage/chapter control.
2. **Annotations:** native selection → direct color or Bookmark → immediate durable save. **Exactly the selected words**, using semantic source anchors, not screen line numbers. Keep Undo/removal/recoloring and all prior annotations. The extra sheet/Done step was removed.
3. **Typography:** system Dynamic Type baseline plus locally persisted serif/system sans, modest size adjustment, and line spacing in Appearance.
4. **AI:** optional on-device **current chapter** overview using Apple Foundation Models. An **icon-only Apple Intelligence button between Appearance and More**, with an accessibility label. The Apple-provided `apple.intelligence` symbol is now used and resolves in native tests; no generic substitute/logo drawing.
5. **Paper turn:** thin Bible-paper left/right turn inspired by old iBooks. Start with the isolated native experiment specified in `Docs/Decisions/0005-thin-paper-turn.md`; integration remains subject to interaction, visual, and physical-device gates.

Ordinary reversible engineering and verification are authorized. No publishing, signing ownership changes, backend, or remote inference. Do not spawn agents unless explicitly authorized by the user or applicable instructions.

## Implemented foundation

- Swift 6/SwiftUI with a single native TextKit 2 chapter text view, cross-verse selection, margin numbers outside copied text, and semantic selection/position restoration.
- Selected compact 2a reader composition, chapter picker 2b, bounded wide reader/sidebar and narrow compact adaptation. Native bars/glass controls stay separate from opaque Scripture.
- Full pinned corpus: **66 books, 1,189 chapters, 31,102 verses**, read-only bundled SQLite/FTS5. GRDB **7.11.1** pinned. No runtime Scripture fetch, corpus rebuild, account, tracker, or backend.
- Separate local user database with file protection, ordinary OS-backup eligibility, transactions, versioned migrations, saved position and Undo. Never delete it to recover from errors.
- Genesis 1 on first launch. Debug tests generally start at John 3 with isolated stores via `BIBLE_TEST_STORE`.
- Local Search with validated references, explicit typo correction, deterministic 50-result paging, safe FTS syntax, real counts, native matched excerpts, cancellation/stale-response rejection, and in-memory state retention.
- Original six design files remain byte-identical under `Design/Reference/`; the reference-manifest checks passed during this continuation.

## Changes completed in the continuation

### Books interaction and reading anchors

The iPhone Books regression was real: `ChapterTextView.point(inside:with:)` compared content-coordinate points to viewport heights without the scroll offset. It now uses `bounds.minY/maxY`. Books opens after scrolling down/up without tap retries. The revised in-content upward drag remains in the UI test.

A second real restoration bug occurred at source headings such as Psalm 119’s BETH: capture paired the previous verse’s identity with the heading’s caret geometry. Capture now chooses the following verse and its own geometry. A dedicated renderer test and the iPad portrait→landscape/sidebar collapse→portrait check passed after this correction.

The compact top-left About control was redundant and absent from the selected 2a composition. It is removed on compact layouts; **More → About this edition** remains. Wide behavior is retained. This is an iPhone polish change, not a new navigation design.

### Exact selected-word annotations

`Domain/ExactAnnotation.swift`, `BibleStore.editExact/undoExact`, and the native menu are implemented and tested.

The iPhone refinement now includes explicit current-color checkmarks (uniform coverage only), conditional Remove Highlight, disabled annotation actions while saving, and Retry of the original exact-word intent after a failed write. Persisted edits whose display refresh fails retry only the refresh. Tests inject a failure and verify retry saves the original excerpt.

Saved → Read now explicitly restores an empty inline navigation title and native text-selection focus after the recreated view attaches and lays out. Dismantling resigns the old responder. Both corrections were needed: layout alone fixed a 52-point shift but did not restore menu interaction. The native long-press recolor/removal/Undo flow passes without gesture retries. Screenshots are preserved under `Docs/Validation/iPhone-selection/`.

- Additive `v2_exact_annotations` retains all v1 tables/records.
- Parts store verse ID, revision-scoped UTF-16 endpoints, exact quote, and surrounding context. Range creation rejects broken grapheme boundaries.
- Resolution requires a unique contextual match, even when a candidate occurs at the old offset. Ambiguous/unresolved quotes are retained, not guessed.
- Overlap edits preserve unselected fragments and independent bookmarks. Legacy highlights convert only when touched, in the same transaction.
- References are derived from actual selected/retained verses; converted per-verse records no longer inherit a misleading multi-verse reference.
- Undo tracks retained record IDs outside the removed verse, rejecting later edits instead of overwriting them.
- Full-verse exact Bookmark recognizes an equivalent legacy bookmark, avoids duplicates, and supports legacy removal/Undo.
- Saved keeps exact quotes and references, resolves offsets for navigation, and explicitly labels unresolved excerpts while offering chapter navigation.
- Obsolete `PrototypeAnnotationView`, annotation-request sheet plumbing, and legacy UI commit helpers were removed. The legacy storage APIs remain for compatibility/tests.

Tests cover a database constructed with the actual v1 schema, migration preservation, Unicode/graphemes, cross-verse quotes, overlap/recolor/removal, bookmark deduplication/independence, durable reopening, injected write rollback including legacy conversion, unresolved-record retention, and stale Undo across split fragments.

UIKit exposes compact selection actions as `menuItems`; in the expanded overflow menu they can be `buttons`. Tests use the observed native Next Page control and appropriate element type. This was an automation-selector issue, not a missing Bookmark action. Direct palette, cross-verse Saved excerpt, and bookmark/highlight relaunch tests have passed on iPhone.

### Typography

Typed UserDefaults preferences persist system/light/dark, serif/system sans, size steps -2…+4, and Compact/Standard/Relaxed spacing. Dynamic Type composes through UIFontMetrics. Reset reading style preserves theme.

Tests verify actual font/spacing changes, semantic selection across reflow, largest Dynamic Type scaling, persistence, and native controls across relaunch. In tests, apply trait overrides with `updateTraitsIfNeeded()` before checking fonts. Native stepper value is the correct persistence assertion; `+1` is grouped inside its accessibility element, not necessarily a separate static text.

### Summary redesign and scoped questions — 22 September update

Latest owner reference: 4a/4b Summary/Questions sheet supplied in the conversation. Use the paper canvas, larger scalable serif copy, question preview, quiet AI disclosure, tinted question bubbles, wrapping passage chips, and floating native Liquid Glass input. Suggestions remain accessible at large text sizes. Source chips open their verified bundled verse in the reader. The owner selected questions within the captured chapter and book, not the whole Bible.

`BookQuestionAnswerer` uses bounded JSON user input, a separate guided scope assessment, book-only local retrieval, guided answers, deterministic source-ID validation, and a fresh supporting-passage review. No tools, remote model, logging, or persisted conversation. These reduce prompt-injection risk without guaranteeing prevention or accuracy. Optional generated title/people-place metadata is bounded; displayed names must also occur in the chapter. Keep real-model refusal/availability behavior visible. See `Docs/Decisions/0008-summary-and-book-questions.md` for the contract and limitations. Validation/screenshots: `Docs/Validation/summary-redesign/README.md`. Final iPhone: 44 non-UI tests + 3 UI flows passed; subsequent input-centering fix: 2 focused UI flows + unsigned Release build passed. iPadOS 26 native-bar/refusal/large-type checks passed before the final small refinements listed in that inventory. Physical-device and broader adversarial model evaluation remain open.

### On-device chapter overview — original implementation record

`Features/Summary/` implements the icon-only entry, captured chapter identity, native sheet, loading/cancel/retry/failure/refusal/availability states, and explicit AI attribution. It uses `SystemLanguageModel.default`, default guardrails, no tools or remote fallback, no prompt/output logs, and no persistence. Only the requested chapter’s text/reference is sent to the model.

Independent bounded sessions summarize chunks, then reduce partial overviews. Character bounds are not token-count claims. Context-limit errors try smaller chunks, then fail explicitly if needed. Both iOS 26 and iOS 27 error types are handled; deployment remains 26.0. Cancellation/request identity reject late results.

The iOS 27 iPhone simulator **returned real generated output**. The iPadOS 26 simulator **declined a summary**; the refusal state worked. Neither result proves physical-device quality, latency, or accuracy. Generated content can oversimplify or misstate the chapter. Keep physical-device evaluation as release work. Initial model readiness/setup belongs to the OS and can require downloads; do not promise fresh-install offline AI when its model is absent.

Fakes test unavailable-model behavior, chunk preservation/context retry, retry after failure, and cancellation. A separate UIKit test verifies the symbol exists. The native UI test accepts either generated output or an explained terminal unavailable/failure state, then returns to the same chapter. Summary text remains selectable. The later 22 September redesign above supersedes this original presentation.

### Debug paper-curl experiment

**More → Paper turn experiment** in Debug now hosts the real chapter renderer in a horizontal `UIPageViewController(.pageCurl)`, leading spine, `isDoubleSided = false`. It is not integrated into normal chapter navigation and is excluded from Release.

It borrows read-only chapter access, holds only current/previous/next documents, and uses separate in-memory ReaderStates with no store. Annotation editing is explicitly disabled in the experiment. Completed turns update only the experimental chapter; cancelled transitions do not commit. Selected text blocks data-source gesture turns. Explicit Previous/Next controls remain outside the moving page. Reduce Motion/Transparency, increased contrast, and VoiceOver use nonanimated explicit turns.

The iPhone test passed forward/back button turns, a swipe-left chapter turn, and dismissal back to unchanged John 3 in the main reader. Experimental chapter views have `paperChapter-<chapterID>` identifiers to distinguish cached pages and the underlying normal reader.

Still unverified: partial-drag cancellation in UI, selection-handle/diagonal arbitration, interrupted transitions/resize, dark reverse-side appearance, perceived thin-paper fidelity, and physical-device frame pacing/memory. Do not describe this as production-ready animation or true screen-sized pagination.

## Verification ledger

All bundles below are under `.build/`; commands used Xcode 27.0 (27A266a), Swift 6.4, iPhone 18 Pro/iOS 27.0 and, before the iPhone-only steering, iPad mini A17 Pro/iPadOS 26.0.

| Evidence | Actual result and limitation |
| --- | --- |
| `Handoff-safety-native.xcresult` | 21 non-UI tests passed; Books still failed before scroll-coordinate fix. |
| `Handoff-interactions-run.xcresult` | Books, direct palette, cross-verse excerpt passed. Test-trait update and Bookmark overflow selectors needed correction. |
| `Handoff-phone-recheck.xcresult` | 24 non-UI tests passed; largest-type dark Books passed; Bookmark selector still needed button type. |
| `Handoff-summary-phone.xcresult` | Initial summary service tests and corrected annotation relaunch passed. |
| `Handoff-phone-features.xcresult` | 30 non-UI tests passed. UI assertions incorrectly assumed model unavailable and separate stepper label; corrected afterward. |
| `Handoff-ipad.xcresult` | 31 non-UI tests; annotation relaunch, Books/scroll, largest-type dark Books, direct palette, and summary terminal state passed. Source-heading restoration bug and stepper assertion subsequently fixed. |
| `Handoff-ipad-reflow.xcresult` | **Passed:** 32 non-UI tests, resize restoration, typography control relaunch. |
| `Handoff-phone-complete.xcresult` | 32 non-UI tests, Books, summary, cross-verse selection, typography relaunch passed. Paper swipe selector matched multiple cached/underlying views; corrected afterward. |
| `Handoff-iphone-focus.xcresult` | **Passed:** 32 non-UI tests including latest legacy bookmark compatibility, annotation relaunch, and paper forward/back/swipe/dismissal. |
| `Handoff-ipad-final.xcresult` | Interrupted at the owner’s “focus on iPhone” instruction. Do not treat as a completed pass. |
| `Handoff-iphone-polish.xcresult` | Largest-type dark Books and chapter/appearance passed; summary terminal-state check failed with the paper experiment visible in the failure hierarchy. Cause not established; summary polish deferred. |
| `iPhone-selection-focused-layout.xcresult` | Exact-word recolor, Saved round trip, removal, and Undo passed after inline-title and native-focus corrections. Screenshots visually inspected. |
| `iPhone-selection-acceptance.xcresult` | **Passed: 34 non-UI tests and three UI tests**: cross-verse drag, annotation relaunch, exact recolor/removal/Undo. |

The intermediate `iPhone-selection-refinement/final/focus/inspect/layout/roundtrip/responder` bundles retain failed menu-restoration checks, not passing evidence. The final acceptance bundle supersedes them. Final unsigned device compilation passed using `.build/DeviceDerivedData`; log `/tmp/bible-iphone-device-verified.log`. No full physical-device acceptance or network privacy audit was performed.

`python3 Content/Tools/validate_corpus.py`: **8 tests passed**; logical SHA-256 remains `221de95d272cfe6b1aa3088f2e82ba4f8589211aca296d33bedf7d6b61ed23e0`. All six `Design/REFERENCE-MANIFEST.json` checksums matched. No source reacquisition/corpus replacement occurred.

## Recommended next sequence — iPhone only for now

1. The focused iPhone selection/highlight pass is complete. Preserve owner-selected 2a and the icon-only summary button. Review `Docs/Validation/iPhone-selection/` with the owner; summary alignment polish is secondary.
2. Continue **Text selection and highlights** on a physical iPhone: handle/magnifier feel, long selections in Psalm 119, exact native Copy/Share, dark fills, and larger Dynamic Type. Current automated coverage establishes current-color checkmarks, exact fills/excerpts, recolor/removal/Undo, Bookmark independence, source-range copy formatting, and persistence; it does not replace physical-device validation.
3. Evaluate native curl visually in light/dark, cancellation, diagonal gestures, selection handles, Reduce Motion/Transparency, and first/last chapter boundaries. Keep it Debug-only until the plan’s integration gates pass.
4. Review chapter-overview accuracy, concision, refusals, long chapters (Psalm 119), cancellation, and latency on an eligible physical iPhone. Never replace Scripture or add a cloud fallback.
5. Broader v1 work remains: Saved filters/deletion controls, source footnote presentation, complete VoiceOver/keyboard/pointer coverage, physical-device protection/performance, offline/network privacy audit, rights/canon/territories, minimum OS approval, app name/signing owner, and release materials.

## Environment and commands

- Project/shared scheme: `BibleReader.xcodeproj` / `BibleReader`.
- Xcode 27.0 (27A266a), Swift 6.4, strict Swift 6; deployment iOS/iPadOS 26.0.
- iPhone simulator: `iPhone 18 Pro`, iOS 27.0.
- Dependency checkout `.build/SourcePackages`; phone derived data `.build/ContentDerivedData`.
- Xcode synchronized groups include new Swift files automatically. Preserve owner signing/project edits. Git is initialized on `main`; the owner requested committing and pushing to `https://github.com/kgpierre/bible-ios.git` (`origin`).
- XcodeBuildMCP tools are unavailable. Xcode/simctl/xcresulttool CLI calls require sandbox escalation for cache and simulator access. No running process should be assumed from old documentation.

```sh
xcodebuild test -project BibleReader.xcodeproj -scheme BibleReader \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' \
  -clonedSourcePackagesDirPath .build/SourcePackages \
  -derivedDataPath .build/ContentDerivedData \
  -resultBundlePath .build/Next-unique-name.xcresult \
  -collect-test-diagnostics never

xcodebuild build -project BibleReader.xcodeproj -scheme BibleReader \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO

xcrun xcresulttool export attachments --path .build/Next-unique-name.xcresult \
  --output-path .build/Next-attachments
```

Use fresh result paths; select `-only-testing:` cases as appropriate. Run simulator batches sequentially. Screenshots use `XCUIScreen.main.screenshot()` and have exported manifests mapping IDs to names. UI tests use isolated stores; never reset real user data. More details: `Docs/Decisions/0004-search-and-books.md`, `0005-thin-paper-turn.md`, and `0006-exact-annotations-and-summary.md`.

### Follow-up fixes: scrolling and key-verse questions

Owner reported ordinary scrolling triggering page curls and a valid whole-book key-verse question being rejected. The pager's built-in navigation gestures are now disabled; a discrete horizontal-intent recognizer defers the native curl until finger lift and releases vertical/diagonal drags to UITextView. Edge taps/short drags cannot turn. See the correction in decision 0007.

Exact bounded key-verse questions are recognized as in scope; appended overrides are not. Whole-book retrieval may nominate up to six verse locations, but the repository resolves them only within the captured book and uses actual bundled text. Invalid locators are discarded. The exact key-verse requests show verified bundled verse quotations with a fixed introduction; other generated answers retain independent support review. See decision 0008. Neither this change nor model tests establish injection-proof behavior or eliminate Apple's possible model refusals.


### Chapter picker and second performance audit — 22 September 2026

The owner’s newer chapter-picker frame supersedes the earlier plain-number 2b treatment. The picker now uses scalable 60-point circular native glass controls, serif book/chapter type, a same-baseline count with large-text fallback, actual saved-highlight rings/dots, a raised dark canvas, Books/Done system toolbar items, and a native glass reference field. See decision 0009 and its screenshot inventory.

The second audit’s main interaction costs are addressed: cached decoded exact annotations grouped by chapter, shared edit reducer for immediate pending highlights and transactional persistence, revision-based renderer invalidation, changed-verse attribute/accessibility updates, cached viewport gutters, indexed catalog navigation, combined startup metadata, and incremental Saved chapter resolution without evicting the reader cache. Rollback and stale Undo retain data. No annotation migration or corpus replacement was needed. See decision 0010 for scope, tests, and intentionally deferred profiling-dependent work.

Current evidence is in `Docs/Validation/reader-followups/README.md` and `Docs/Validation/chapter-picker/README.md`. Physical iPhone gesture/selection feel and a Release Instruments trace on the slowest supported device remain open; simulator tests are not device latency evidence. Static signposts contain no reading references, questions, annotation contents, or database paths.


Final pre-commit evidence: 53 non-UI tests and three iPhone UI flows passed in `Reader-followups-phone.xcresult`; unsigned Release build passed. iPad live-Saved editing and large-text picker dismissal passed in separate runs. Later attempts to rotate into the wide sidebar did not change the app’s portrait layout, so repeat iPad rotation validation remains unresolved. See the follow-up validation inventory for exact passing and failing runs. The newer integrated reader work supersedes the earlier Debug-only paper-turn recommendation above.
