# Thin-paper chapter turn: hypothesis and execution plan

21 September 2026. Owner-requested experiment; visual fidelity and device performance are not yet established.

## Sequence and scope

Finish and verify offline Search, direct references, the segmented Books browser, and adaptive navigation first. Then build an isolated, reversible paper-turn experiment. Integrate it into the main reader only after the interaction gates below pass. Remaining Saved actions, durable appearance preferences, accessibility, and data-resilience work remain release priorities.

The first experiment turns **chapters** left/right while retaining vertical scrolling inside a chapter. This preserves the current continuous, selectable chapter and verse-per-line reader. True screen-sized pages would require a separate pagination design, including selection across page boundaries; a chapter-turn prototype is not evidence that pagination works.

## Hypothesis

Thin Bible paper is suggested by a narrow curling edge, soft self-shadow, a pale reverse surface, and faint reversed print showing through during the turn. At rest, Scripture stays sharp and fully legible on the existing opaque canvas. Navigation glass stays outside the moving sheet.

Start with `UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal)` and a leading spine. Apple documents that `isDoubleSided = false` partially shows the front content through the back during a turn. This gives us a supported baseline for the most distinctive visual cue without manufacturing or rewriting Scripture. UIKit controls the curl geometry and lighting; it does not expose a general paper-thickness, stiffness, or transmission shader. Exact physical fidelity is a hypothesis, not an API promise.

Sources: [Apple page-view controllers](https://developer.apple.com/library/archive/documentation/WindowsViews/Conceptual/ViewControllerCatalog/Chapters/PageViewControllers.html), [double-sided behavior](https://developer.apple.com/documentation/uikit/uipageviewcontroller/isdoublesided).

## Ordered implementation

1. **Record the baseline.** Capture current chapter scrolling, long-press selection, cross-verse drag, rotation, and navigation restoration on iPhone/iPad. Keep the existing reader available for comparison.
2. **Isolate the experiment.** Add a development-only presentation with actual bundled chapters and independent presentation state. Browsing the experiment must not change annotations or the main reader's saved place.
3. **Prove native geometry.** Host the existing native chapter renderer inside a horizontal page-curl controller. Use a single-page leading spine, standard one-sided rendering, and at most current/previous/next chapters. Verify both directions and partial-drag cancellation before adding materials.
4. **Evaluate the paper.** Record slow drags in light and dark appearance. Inspect the reverse-side show-through, edge thickness, fold shadow, and whether system rendering flashes a bright reverse side in dark mode. Keep contrast high when settled. Do not add grunge, noisy grain, yellow aging, or decorative fake print.
5. **Resolve input ownership.** Vertical drags scroll; intentional horizontal drags turn. Selection handles and long presses retain native priority. Disable turning while selection/menu interaction is active if necessary using public recognizers. Test diagonal drags, fast reversals, repeated swipes, and touches beginning near the gutter or controls. Never inspect or change private UIKit subviews.
6. **Define a turn transaction.** Prepare the adjacent chapter before a gesture can commit. Commit canonical chapter/anchor only after a completed transition. Cancellation preserves the original chapter, scroll anchor, and annotation state. At corpus boundaries, return no adjacent page; never wrap or display fabricated content.
7. **Handle interrupted layouts.** Rotation, resizing, Dynamic Type, backgrounding, or an external Search/Saved navigation cancels or completes the active transition deterministically, then restores semantic anchors. Build rendered content only after valid layout dimensions exist.
8. **Add accessible alternatives.** Reduce Motion uses a non-curl transition or immediate replacement. VoiceOver and keyboard users retain explicit Previous/Next actions. Reduce Transparency/Increase Contrast use opaque paper without show-through. Curl is never the only route to a passage.
9. **Measure before expanding.** Profile on the slowest supported physical device, including Psalm 119. Measure frame pacing, render preparation, peak memory, and allocations across repeated turns. Keep no more than a bounded neighboring cache and release temporary render surfaces after completion/cancellation.
10. **Decide from evidence.** If the native curl meets the feel and interaction gates, integrate the smallest version behind an appearance setting. If it cannot represent the desired paper, document the missing capability and compare a custom renderer before replacing it.

## Custom-renderer contingency

Only pursue this if the native prototype proves insufficient. During an active turn, render the visible Scripture viewport into a full-resolution texture from the existing layout; hide it from accessibility while the underlying native content retains the semantic model. Never persist screenshots or regenerate Scripture. Keep controls stationary.

Use a Metal mesh bent around a moving cylindrical fold axis: vertices before the axis stay flat; vertices on the bend follow the cylinder; vertices beyond it rotate onto the reverse face. Drag position determines the axis and radius. Surface normals drive a restrained diffuse highlight and soft cast shadow. Reverse-face UVs mirror the real front texture, with low ink transmission and a warm/dark paper base. A slight procedural normal variation could suggest flexibility; any grain must be nearly invisible at reading size. A physical cloth solver is unnecessary for the first approximation.

Make drag progress reversible and settle from velocity/progress to the original or next page. Freeze the snapshot only for the turn, then restore live selectable text and its semantic anchor. Do not commit navigation until completion. Benchmark texture memory at actual device scale; a visually convincing simulator clip alone is insufficient.

This renderer is materially more work: gesture arbitration, animation cancellation, shadows, text sharpness, accessibility, and rotation all become application responsibilities. Do not choose it merely to tune a cosmetic detail before testing UIKit.

## Acceptance gates

- Real corpus text remains exact; no skipped/duplicated passage on completed, canceled, or interrupted turns.
- Vertical scrolling, native cross-verse selection, copy, highlights, and bookmarks retain their behavior.
- Both directions work across book boundaries and stop at Genesis 1/the final chapter.
- Search/Saved opens the requested verse; reflow and relaunch preserve semantic reading position.
- Dark mode and accessibility alternatives remain legible; no compulsory motion or transparent resting page.
- Physical-device frame pacing/memory measurements and slow-motion captures accompany the visual review.

The initial experiment may be shown before these integration gates pass, but must be labeled as an experiment and remain separate from normal reading.

## First native experiment (continuation)

A Debug-only **More → Paper turn experiment** now hosts the existing continuous TextKit reader in a public `UIPageViewController` using horizontal `.pageCurl`, a leading spine, and `isDoubleSided = false`. This is a geometry/interaction probe, not integrated chapter navigation. The main reader remains the production path.

The experiment borrows read-only chapter access and creates separate in-memory reader states with no persistence store. Annotation menu actions are disabled and the screen says so; the main reader’s annotations/position are not edited. Only current/previous/next documents are retained. Completed native delegate transitions update the experiment chapter; cancelled transitions do not. Previous/Next controls stay outside the moving page. Reduce Motion, Reduce Transparency, increased contrast, and VoiceOver use explicit nonanimated turns instead of gesture curl. Active text selection prevents data-source gesture turns.

Still required before integration: visual judgement of thin-paper fidelity in both themes; partial-drag cancellation, selection-handle arbitration and interruption/resize matrices; annotation-preserving integration; physical-device frame pacing/memory and reverse-side captures. No custom paper physics, Metal shader, or screen-sized pagination has been added. Test results and screenshots are recorded in the updated handoff, including any unsuccessful gestures.
