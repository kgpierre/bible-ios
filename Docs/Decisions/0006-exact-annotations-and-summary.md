# Exact annotations, typography, and on-device chapter overview

21 September 2026. Latest owner decisions in HANDOFF.md supersede the earlier whole-verse/annotation-sheet and no-summary requirements.

## Exact annotations and preservation

The additive `v2_exact_annotations` migration leaves the v1 highlights, bookmarks, and reading position intact. Selected words store stable verse identity, revision, UTF-16 start/end, exact quote, and nearby context. These are source anchors, never screen line numbers. Native menu colors and Bookmark commit immediately; the obsolete annotation sheet and its request/commit plumbing were removed.

Range edits run in a transaction. They subtract only overlapping words, preserve fragments, keep bookmarks independent, and convert only touched legacy highlights. References are derived from the actual remaining verses, including converted legacy fragments. Undo compares the before/after record scope, including fragments no longer intersecting the removed verse, so later edits cannot be overwritten. Injected insertion failures roll back legacy conversion and exact records together.

Resolution verifies quote and context even at the previous offset. Contextual recovery is conservative; unresolved quotes are retained and identified in Saved. Saved navigation uses resolved offsets, or offers the chapter when the exact words cannot be located. Corpus and original design bytes are unchanged.

Tests cover actual v1-schema migration, Unicode/grapheme boundaries, cross-verse excerpts, overlap splitting/removal, exact bookmark deduplication, independent edits, reopening, injected rollback, and stale Undo across retained fragments.

### iPhone selection refinement

The native palette shows an explicit checkmark beside the current color when the entire selection has that color. Mixed or partial coverage has no checkmark. UIKit's compact palette did not visibly render `UIAction.state` alone in the tested runtime, so the title includes the checkmark as well. Remove Highlight appears only when selected text intersects a highlight. Annotation actions are disabled during a pending save.

Failed writes retain the exact passage and action for Retry. A successful write followed by a display-refresh failure retries only the refresh, preventing duplicate operations or misleading unsaved-change messages. Injected failure/retry is covered by a storage-backed ReaderState test.

Returning from Saved exposed two issues: the reader inherited a blank large-title area, and restoring selection offsets alone did not restore native interaction focus. Compact Read now explicitly uses an empty inline title. The text view resigns focus on dismantling and restores it after attachment/layout when restoring a semantic selection. No custom selection gestures or private UIKit APIs are used.

Verification on iPhone 18 Pro / iOS 27.0, Xcode 27.0 (27A266a): `.build/iPhone-selection-acceptance.xcresult` passed 34 non-UI tests and three UI tests covering cross-verse drag, highlight/bookmark persistence across relaunch, and exact-word recolor → Saved → Read → removal → Undo. The latter also checks unchanged verse position after the destination round trip. Final unsigned generic iOS build passed; this does not establish physical-device acceptance. Screenshots: [current color](../Validation/iPhone-selection/current-color.png), [restored selection](../Validation/iPhone-selection/restored-selection.png), [Undo excerpt](../Validation/iPhone-selection/undo-excerpt.png).

## Typography

Typed local preferences persist theme, serif/system sans, size adjustment, and spacing. Font size and spacing compose with UIFontMetrics/Dynamic Type. Renderer tests assert actual font/spacing changes and semantic selection retention through reflow, plus accessibility-size scaling. Control and relaunch checks run separately on the simulators.

## Chapter overview

Entry: icon-only `apple.intelligence` button between Appearance and More, with “Summarize current chapter” accessibility label. The native sheet captures the chapter at entry, then shows loading, generated overview, cancelled, unavailable, or retryable failure states. It uses the reading canvas, standard system text styles, 20-point content margins, and a bounded 640-point column. Generated material is explicitly identified and kept separate from Scripture. Dismissal cancels work and discards the in-memory output.

`SystemLanguageModel.default` is selected explicitly, with default guardrails and no tools or remote fallback. Only the current chapter text/reference enters prompts. Availability checks explain device eligibility, settings, model readiness, and language support. Initial OS model setup can require a download; the app does not promise fresh-install offline AI. No prompt/output logging or persistence is added.

Each bounded chunk uses an independent session, with at most 300 output tokens. Long chapters use partial overviews and reduction. The 5,000-character workload bound is not a token-count guarantee; context-limit errors trigger smaller chunks and ultimately an explicit retryable failure. New iOS 27 errors and legacy iOS 26 GenerationError cases are handled without raising the deployment target. Cancellation and request identity reject late results. Fakes test availability, context-limit retry, lossless input partitioning, and cancellation; they are not generation-quality evidence.

The Apple-provided SF Symbols catalog at `/Applications/SF Symbols.app/Contents/Resources/Metadata/name_availability.plist` identifies `apple.intelligence` as a 2024 symbol. Native tests verify UIImage resolves it on supported runtimes. No substitute icon, custom logo, or extracted Apple font is bundled.

The iPhone iOS 27 simulator did return a real Foundation Models result during verification. This establishes integration in that environment only. Generated text can misstate or oversimplify the chapter; no theological accuracy, physical-device latency, or model-quality acceptance is claimed. Physical-device evaluation and final rights/distribution checks remain release work.

## Primary API references checked

- [Apple Foundation Models generation](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models)
- [Context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window)
- [Generative AI design guidance](https://developer.apple.com/design/human-interface-guidelines/generative-ai)
- [SF Symbols guidance](https://developer.apple.com/design/human-interface-guidelines/sf-symbols)

The installed Xcode 27 FoundationModels Swift interface was checked for iOS 26 availability. No signing ownership, cloud entitlement, publication, corpus approval, or privacy-audit approval is implied.

Additional compatibility checks: exact Bookmark recognizes an equivalent v1 whole-verse bookmark, prevents duplication, and supports removal/Undo. Source headings such as Psalm 119’s BETH now anchor the following verse using its own caret geometry; they no longer combine the previous verse identity with the heading’s position. A dedicated renderer test and iPad resize round trip cover this correction.
