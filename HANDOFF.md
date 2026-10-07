## Latest continuation — 7 October 2026, saved chapters and Scripture widgets

Owner requested saving whole chapters and turning saved verses/chapters into widgets, with Apple Intelligence for backgrounds. Plan and boundaries: [0019](Docs/Decisions/0019-saved-chapters-and-widgets.md).

- **Saved chapters:** More → Save Chapter / Remove Saved Chapter, and Command-D. Additive user-store migration `v4_saved_chapters` (pre-migration backup runs automatically). Saved shows "Saved chapter · N verses" rows under All and Bookmarks; Bible order puts a chapter before its verses. Delete requires the displayed record; session/system Undo covers save, remove, and delete.
- **Widgets:** a new `BibleWidgets` WidgetKit extension (`dev.kpierre.bible.widgets`) and App Group `group.dev.kpierre.bible` on the app and extension. Shared card code lives in `BibleShared/` (compiled into both targets). In Saved, Make Widget (context menu, leading swipe, VoiceOver action) opens a card editor with six presets, Image Playground (shown only where it's supported), Photos, ink, and typeface. Saved → Widgets lists, edits, and deletes cards. The widget supports small, medium, large, extra large, and the Lock Screen rectangular/inline families; it shows a chosen card or rotates daily, and tapping opens `dev.kpierre.bible://open?...`, validated against the catalog.
- **Signing:** device builds need the App Group capability registered under the owner's team; automatic signing should do this on the first device build. Simulator builds sign locally with the group.
- **Evidence (7 October 2026):** Xcode 27.1 (27A9269) through a per-process `DEVELOPER_DIR`, iPhone 18 Pro simulator on iOS 27.0, Debug. The full scheme run `.build/Widgets-full-phone.xcresult` passed 142 tests with 0 failures; 13 skipped are the iPad/Duo-only cases. That includes the new SavedChapterTests and ScriptureCardTests (with a rendered gallery in the attachments) and the UI tests `testSaveChapterAndMakeWidget` and `testWidgetLinkOpensValidatedPassage`. The unsigned simulator build embeds `BibleWidgets.appex`, and the simulated entitlements include the App Group.
- **Not verified:** widgets placed on an actual Home or Lock Screen (there's no CLI to add widgets; check manually in the simulator and on a device); real Image Playground generation (needs an Apple Intelligence device; the simulator shows the disabled state and explanation); photo import end-to-end; iPad/Duo layouts of the editor; tinted/clear Home Screen rendering.

## Latest continuation — 27 September 2026, initial Duo adaptation

Owner requested iPhone Duo feature hypotheses, existing-feature parity with iPad-like inner-display reading/page swiping, tests, and AGENTS.md directives. The page preference is no longer iPad-only. Facing pages use regular width plus a scaled readable-page budget, with scrolling at narrow/accessibility sizes. The subsequent owner refinement adds automatic facing pages in a partially folded book pose (with an Appearance opt-out), and reading above chapter controls in tabletop pose. These use public active division regions on iOS 27.1 without overwriting flat-screen preferences. Build with the owner's Xcode 27.1 per-process; keep minimum iOS 26. See [0018](Docs/Decisions/0018-iphone-duo-adaptive-reader.md) and [validation](Docs/Validation/duo/README.md) for actual test results and remaining acceptance. A Scripture/source-notes companion remains a proposal.

Actual Duo UI checks passed for automatic book paging/opt-out, horizontal-fold reader/control placement and chapter navigation, and the flat wide-display spread with exact-word highlighting, Saved, chapter turns, and restoration to Scroll. iPhone/iPad regressions also passed. The flat Duo test uses an operator-selected Device Hub pose because XCTest rotation/window queries were unreliable. Inner-display screenshot capture returns black images; visual review, live close/reopen transitions, broader accessibility, and physical-device checks remain open.

## Latest continuation — 27 September 2026, iPad top tab bar

On regular width, the iPad now uses the system top tab bar (`.tabBarOnly`: Read, Saved, Search) instead of the custom sidebar. The owner reviewed a sidebar-adaptable version and chose no sidebar. The glass passage capsule floats at the bottom right. Chapter picker numbers are Liquid Glass on every device, with the current chapter in accent-tinted glass. Compact width, including iPhone and narrow iPad windows, keeps 2a. ⌘⇧S is removed. See [0017](Docs/Decisions/0017-ipad-top-tab-bar.md). iPad UI tests were rewritten for the tab model and pass on the iPad Pro 13-inch simulator.

In the same session:

- **Two Pages:** an iPad landscape option (Appearance → Pages). It shows facing pages at verse boundaries that curl like a book, and crossing the last page opens the next chapter. The reading anchor is the first verse of the left page. A selection stays within one page, which the owner accepted.
- **Text size** is a slider on both devices.

Two Pages still needs on-device checks: curl feel, Psalm 119 pagination time, and accessibility text sizes.

## Latest continuation — 26 September 2026, release decisions, summaries, notes, Saved, search

**Owner decisions** (recorded in [0015](Docs/Decisions/0015-release-identity-and-scripture-rights.md)):

- minimum iOS/iPadOS 26.0;
- app name "Bible";
- bundle ID `dev.kpierre.bible`, with test targets `.tests` and `.uitests` on the owner's team;
- a delegated rights and canon review. The KJV is public domain outside the UK and Crown-restricted in the UK, so the release excludes the United Kingdom storefront unless Cambridge University Press grants permission. The 66-book canon is adopted.

About's edition notice no longer shows the internal "Unresolved" line. The corpus database is byte-identical.

**Summary refusals fixed** ([0016](Docs/Decisions/0016-continuation-summaries-notes-saved-search.md)). A real-model probe showed that the *post-generation refusal check*, not the summary itself, caused 12 of 20 failures on difficult chapters. The check was a second model pass under default guardrails. It is replaced by a wording check, and the probe now passes 20 of 20. Question review is unchanged; 4 of 5 difficult questions were answered.

**Implemented:**

- **Source notes (6,959):** a dot marker by the verse number, tap to read; More → Chapter notes; a VoiceOver action; an Appearance toggle. Notes are never in copy or search.
- **Large libraries:** additive migration v3 (chapter-indexed annotations, with a protected pre-migration backup); the reader decodes only nearby chapters; Saved resolves off the store queue.
- **Search:** ranked once per query, so deep pages dropped from about 68 ms to 3 ms.
- **Session Undo:** capped at 100.
- **Saved controls:** segmented filters and an icon sort button, pending owner review.
- **Lock probe:** a Debug-only locked-device probe.

**Validation.** The iPhone 18 Pro (iOS 27) simulator passed 77 unit tests and 24 UI tests (3 iPad-only skips), with no warnings. The corpus rebuild passed 9 of 9 checks. See the README entry for the commands.

**Needs the owner's device:**

- the probe on the phone's own model;
- page-turn and selection feel.

**Locked-device test passed** on the owner's iPhone 17 Pro Max on 27 September ([results](Docs/Validation/locked-device/README.md)). **Notes sheet** now fits its content.

**App icon:** `Bible.icon` (Icon Composer, layered) is now the app icon; the flattened PNG set was removed.

**Owner to-dos:**

- choose the donation mechanism (guideline 3.1.1);
- in App Store Connect, exclude the United Kingdom.

The earlier "iPhone only" focus below is historical; iPad was out of scope again for this pass by the owner's instruction.

Earlier development installs used `org.example.BibleReader`. The new bundle ID starts with an empty local store; old installs keep their data separately.

## Latest continuation — 25 September 2026, corpus, About, page turn

Performance-audit follow-ups are listed in `Docs/Validation/performance-audit/README.md`: signposts, off-main sorting for large Saved libraries, a real search prewarm, Release-compilable tests, and the launch tab-bar alignment fix. The shared scheme's Run action is currently set to Release by the owner.

The app icon comes from the owner's exports, flattened to opaque. Fixed the first-swipe stall by building neighboring pages ahead of time. Opening the Search tab no longer auto-focuses the field, which forced the first keyboard presentation (a known device stall). Both still need confirmation on the physical device.

Owner requests, all implemented:

- **Smaller corpus:** 34 → 16 MB. Chapter payloads are compressed, search uses an external-content index, and a redundant index is gone. The Bible text is unchanged: the logical revision is identical and the verse and document comparisons match.
- **About screen:** name "Bible", Kyle Pierre with kpierre.dev, a donation button, attributions, and an icon slot. The donation URL is still pending: set `AppInfo.donationURL`.
- **Page turn:** the curl follows your finger, the back is thin paper with faint mirrored print, response is quicker, and a soft haptic plays on commit.

Also fixed a turn state mismatch that could leave the screen on the previous chapter. See decisions [0013](Docs/Decisions/0013-visual-and-performance-audit.md) and [0014](Docs/Decisions/0014-interactive-paper-turn.md). On-device feel and haptic checks are still needed.

## Latest continuation — 25 September 2026, visual and performance audit

Fixed the compact passage capsule, which showed an abbreviation beside empty space ("Jhn 3") and stacked unnecessarily for long book names. Other fixes: italic overhang spacing (presentation-only kerning), the native top scroll edge effect behind the floating toolbar, Saved restyled to match Search, consistent close-role sheets on the reading canvas, the duplicate "Theme" label, a checkmark instead of a bookmark for the current book, the wide sidebar following the current testament, grouped More menu, and removal of the dead Books sheet. Performance measured fine except the first search of a session; Search now prewarms the parser and FTS pages once when opened. 67 unit tests, the iPhone UI suite, and the iPad mini resize tests pass. See [decision 0013](Docs/Decisions/0013-visual-and-performance-audit.md). No Scripture, corpus, schema, or signing changes.

## Latest continuation — 22 September 2026, release audit

Implemented the privacy manifest, accessible chapter-turn fallback, full wrapped-verse accessibility geometry/actions, localization extraction, stronger/high-contrast highlights, plain chapter cells/native Close, storage scheduling and Saved-query improvements, cached annotation/Saved work, streaming overview drafts, semantic selection-menu colors, native UndoManager/scene commands, finite background position-write allowance, adaptive passage labels, and a stable split-view reader across resizing. The separate Books button remains removed. Removed duplicate wide About; retained owner-selected sidebar controls.

66 non-UI tests pass. Focused iPhone selection/Saved/picker/Books/turn-and-relaunch checks pass. iPad Saved and Search resize flows pass. The prior Psalm 119 one-verse restoration mismatch is now fixed and its existing assertion passes: passive resizing must not recapture the semantic reading anchor. Unsigned Release compilation and bundled app privacy-manifest inspection pass. See [audit decision and remaining work](Docs/Decisions/0012-release-audit.md) and [validation evidence](Docs/Validation/release-audit/README.md).

Outstanding audit proposals: measured WAL/pool migration, binary chapter payloads/external-content FTS/index cleanup, and useful retained-session model prewarming. Native sidebar tabs/multiwindow/searchable remain advisory product changes. Physical-device accessibility, keyboard/Undo, protected background timing, real-model quality, profiling, privacy/network capture, rights/canon, and release acceptance remain open. No Scripture, corpus schema, or user database migration changed.

# Bible Reader — Development Handoff

Updated 22 September 2026 after the owner-requested iPhone interaction/performance pass. Repository: `/Users/kyle/Developer/bible-ios`.

## Latest implementation — Saved controls

Saved now supports All/Highlights/Bookmarks, Most recent/Bible order, native swipe/context-menu deletion, accessible deletion, and session Undo. Filter/sort choices stay in AppState across destinations and compact/wide presentations. Deletion targets the original records represented by a row, including grouped legacy highlights and unresolved excerpts; failures retain the row and Retry intent. Existing exact/legacy Undo checks reject conflicting later edits. No schema or corpus changes. Pull-to-refresh explicitly reloads Saved.

The iPhone suite passed 61 non-UI tests and the Saved UI flow. Final verification also passed the Saved flow and largest-type dark controls after the lifecycle fix. iPad live Saved testing uncovered a crash when returning to compact Saved: an inactive reader lacked the initial page UIKit requires. Fixed and covered by a new unit regression plus a passing iPad mini Saved/rotation flow. A separate broad rotation check still reports a one-verse first-visible mismatch in Psalm 119; retain it as follow-up, not passing evidence. See [Saved validation](Docs/Validation/saved/README.md) and [decision 0011](Docs/Decisions/0011-saved-controls-and-deletion.md).

Simulator discovery now finds iOS 27 devices; the zero-simulator result in the earlier polish entry is historical. Next unfinished implementation includes source footnote presentation; device, accessibility, privacy, and release gates remain open. Saved filters/deletion are no longer pending.

## Latest owner refinements — 22 September 2026, reader polish

The owner explicitly removed the separate compact Books button. Books remains reachable through the passage/chapter picker; this supersedes earlier instructions to retain the separate button. Compact native tab titles now crossfade when collapsing/expanding (immediate with Reduce Motion). Reader heading top spacing is reduced by 12 points and trailing text margin increased by 8 points on compact layouts.

Summary and follow-up questions now share one scrollable history. Follow-up copy uses Dynamic Type body sizing; Retry is a prominent labeled button; the redundant leading Intelligence symbol is removed. Chapter overview generation uses Apple's on-device `permissiveContentTransformations` setting specifically for supplied-text summaries. A default-guardrail classification checks for prose refusals before accepting the overview. Questions, retrieval, and answer review retain default guardrails. Refusals remain possible; this change has not been evaluated against a real model here.

Chapter numbers distribute across the picker width. Removed the visual reading-status/highlight legend; semantic highlight indicators remain. Close is an accessible X, with the passage popover dismissal explicitly wired to its presentation binding. Horizontal turns accept shorter/slower gestures and moderate drift; vertically dominant movement permanently rejects a turn.

Validation: unsigned app and test-target compilation succeeded with XcodeBuildMCP. Three pure Swift swipe-intent checks passed on the host. No simulator UI tests, screenshots, iPad resizing checks, or real-model evaluation were performed: `xcodebuildmcp simulator list` reported zero simulators after obtaining Simulator access. No signing settings or Scripture changed. See the README validation entry for the exact build command.

## Latest continuation — 22 September 2026

The owner requested quicker phone selection, visible highlight **swatches instead of color-name text**, paper curls in normal reading with the experiment removed, and native tab interaction while **keeping all bottom controls side by side**. These newer instructions supersede the old Debug-only paper-turn direction below.

Implemented: 0.3-second word-selection start with native handles/edit menus; semantic-color swatches and accessible names/checkmarks; integrated chapter curls; native `UITabBar` within the compact adjacent-control layout; retained compact destination views; cancellation-safe position flushes; a six-chapter decoded cache; SQL-only position validation; lazy Saved loading; and reduced per-frame/repeated text work. The audit's false save-error diagnosis was confirmed. Durable annotation writes, complete file protection, existing schema, and Scripture resources are preserved.

The iOS 27 performance bundle passed **35 non-UI tests and six UI tests**, including selection/recolor/Undo, Books/scrolling, turns/relaunch, and appearance. The iOS 26 compatibility bundle also passed **35 non-UI and six UI tests**, including native tab drag tracking, a short edge-drag cancellation check, Search, and largest-type dark Books. Physical-phone testing was attempted but did not run: test-target signing teams are unconfigured, and Xcode's interactive tool offered only simulators. Signing settings were not changed.

The final iOS 27 pass also passed **35 non-UI and four UI tests** after the last swatch/transition adjustments. The iPadOS 26 resize/selection regression passed **35 non-UI and two UI tests**. Unsigned Debug and Release device builds passed. Final screenshots are in `Docs/Validation/iPhone-reader-refinement/`.

Read [decision 0007](Docs/Decisions/0007-iphone-reader-interactions.md) for implementation, current evidence, and remaining device gates. The older continuation sections below are historical; this latest section and decision 0007 take precedence.

## Current owner priority (historical, 22 September)

**Focus on refining the iPhone version for now, specifically text selection and highlights.** The owner gave this steering during the continuation. Do not expand into further iPad refinement without a new request. The last running iPad batch was stopped when this instruction arrived; its partial results are not a complete pass.

Read this document, `AGENTS.md`, and the relevant implementation before editing. Continue the existing native app; do not regenerate the corpus. This is development evidence, not release approval.

## Latest owner decisions

1. **Books/navigation:** Books is reached through the chapter picker; the separate compact Books button was removed at the owner’s request. Native tab labels collapse on downward scrolling and return upward. Keep labels at accessibility sizes. Books uses Old/New Testament selection and native subtitle rows. Keep the passage/chapter control.
2. **Annotations:** native selection → direct color or Bookmark → immediate durable save. **Exactly the selected words**, using semantic source anchors, not screen line numbers. Keep Undo/removal/recoloring and all prior annotations. The extra sheet/Done step was removed.
3. **Typography:** system Dynamic Type baseline plus locally persisted serif/system sans, modest size adjustment, and line spacing in Appearance.
4. **AI:** optional on-device **current chapter** overview using Apple Foundation Models. An **icon-only Apple Intelligence button between Appearance and More**, with an accessibility label. The Apple-provided `apple.intelligence` symbol is now used and resolves in native tests; no generic substitute/logo drawing.
5. **Paper turn:** integrated native chapter curls now use explicit horizontal intent. The earlier Debug experiment is historical; physical-device feel and broader resize checks remain open.

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
3. Evaluate native curl visually in light/dark, cancellation, diagonal gestures, selection handles, Reduce Motion/Transparency, and first/last chapter boundaries. The curl is already integrated; the Debug-only recommendation is superseded.
4. Review chapter-overview accuracy, concision, refusals, long chapters (Psalm 119), cancellation, and latency on an eligible physical iPhone. Never replace Scripture or add a cloud fallback.
5. Broader v1 work remains: source footnote presentation, complete VoiceOver/keyboard/pointer coverage, physical-device protection/performance, offline/network privacy audit, rights/canon/territories, minimum OS approval, app name/signing owner, and release materials.

## Environment and commands

- Project/shared scheme: `BibleReader.xcodeproj` / `BibleReader`.
- Xcode 27.0 (27A266a), Swift 6.4, strict Swift 6; deployment iOS/iPadOS 26.0.
- iPhone simulator: `iPhone 18 Pro`, iOS 27.0.
- Dependency checkout `.build/SourcePackages`; phone derived data `.build/ContentDerivedData`.
- Xcode synchronized groups include new Swift files automatically. Preserve owner signing/project edits. Git is initialized on `main`; the owner requested committing and pushing to `https://github.com/kgpierre/bible-ios.git` (`origin`).
- XcodeBuildMCP CLI is available; use it for builds, tests, and simulator control with the required sandbox permissions. No running process should be assumed from old documentation.

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
