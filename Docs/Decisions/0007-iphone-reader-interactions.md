# iPhone selection, native compact tabs, and integrated chapter turns

22 September 2026. Engineering implementation; physical-device acceptance remains open.

## Owner direction

The owner requested faster selection on the actual phone, visible highlight swatches instead of color-name text, the paper turn in normal reading with the separate experiment removed, and more native iOS 26+ tab behavior. When offered the standard SwiftUI accessory arrangement, the owner explicitly kept chapter, Read/Saved/Search, and Books **side by side**. This request supersedes the earlier Debug-only integration restriction in decision 0005. It does not establish physical fidelity, performance, rights, or release approval.

## Selection and highlights

The continuous TextKit 2 `ChapterTextView` remains the renderer. An app-owned 0.3-second long press starts a word selection through the public tokenizer and `selectedTextRange` APIs. Movement cancels this initial gesture; existing selections, native handles, dragging, magnification, and VoiceOver keep their native interaction. A `UIEditMenuInteraction` presents the same durable annotation actions. Its target rectangle includes clearance for selection handles; a changed range dismisses its obsolete menu.

The color actions have empty visible titles and rasterized SF Symbol circles using the actual semantic highlight colors. A contrasting ring and selected checkmark keep the state legible. Image accessibility labels retain the color names. There is no confirmation sheet. Native selection/copy/share formatting and transactional annotation storage remain authoritative.

Touch delivery no longer waits for the scroll-view delay. Chapter-map construction tracks UTF-16 length incrementally; verse text is materialized once when decoding without changing the serialized corpus format. Header measurement is cached until typography/width changes, gutter lookup is indexed by text offset, highlight parts are grouped by verse, and navigation-cue text edits are batched.

## Compact tabs

A public `UITabBar` bridge supplies native item selection/tracking and system glass while SwiftUI owns the surrounding layout and destinations. The chapter control stays on the left and Books stays on the right. The native bar is measured inside its own container so its floating margins do not squeeze the three destinations. Scroll-driven label collapse remains app-managed because the owner retained the adjacent-control composition; this is not a standard full-screen `TabView` container. Accessibility sizes keep labels and the narrow two-row fallback remains.

Compact Read, Saved, and Search remain mounted across destination changes. Hidden destinations do not receive touches or accessibility focus; Search explicitly relinquishes keyboard focus when hidden. The reader preserves its existing text view, layout, scroll position, and selection rather than decoding/reconstructing three chapters on each return.

## Chapter turns

`PaperChapterView` embeds the native horizontal, single-sided `UIPageViewController(.pageCurl)` in normal reading. The separate experiment model, screen, and More action were removed. Turns are **whole chapters with vertical scrolling**, not screen-sized pagination.

Only current/previous/next documents/pages are retained by the coordinator. Neighbor documents load asynchronously; their text views are constructed on demand. Preview pages cannot edit annotations or persist positions. A completed gesture commits to the shared reader only if its source/navigation revision is still current and its target is adjacent. Cancellation retains the previous chapter. Search/Saved navigation, resizing, theme/type changes, and background transitions invalidate an in-flight turn. Selection and in-progress annotation writes suppress gesture turns. More and keyboard Previous/Next remain available; Reduce Motion, Reduce Transparency, increased contrast, and VoiceOver use immediate explicit navigation.

### Scroll-versus-turn correction

The owner's physical-use report found that ordinary scrolling could start a curl. UIKit's built-in gesture navigation is now disabled with a nil page-controller data source. A separate discrete, single-touch recognizer accepts a deliberate horizontal swipe only after finger lift: 80–120 points of travel (scaled by width), at least 3:1 horizontal dominance, no more than 24 points of vertical travel, and at most 0.8 seconds. Vertical/diagonal intent at 8 points permanently rejects that touch sequence and releases it to the native text-view scroll recognizer. Later horizontal drift cannot change that decision. Edge taps, held selection gestures, deceleration, short drags, and cancelled gestures cannot turn pages.

The native paper-curl animation runs only after an accepted swipe; there is no interactive curl preview competing with scrolling. Explicit navigation and accessibility fallbacks remain available. iPhone 18 Pro / iOS 27 tests passed for actual vertical scrolling near both edges and in the center, ordinary downward scrolling, edge taps, deliberate forward/reverse turns, native selection, short-drag cancellation, and relaunch restoration (`Scroll-turn-fix-phone.xcresult`, 46 non-UI + four UI tests). Physical-device feel still needs owner verification.

The outer pager touch region, as well as the text view, excludes floating chrome. Without this outer guard, the page controller background intercepted Books after scrolling even though the text view correctly rejected the touch.

## Confirmed performance-audit fixes

- `flushPosition` ignores cancellation, matching the debounced save path. Superseded writes no longer produce false save-error alerts. Completed chapter navigation explicitly persists even when both old and new intra-chapter anchors are nil.
- `BibleStore` caches up to six decoded chapters by recency. Position validation uses indexed chapter/verse SQL existence checks rather than decoding a chapter.
- Reader annotation refresh uses one store read for legacy and exact snapshots. Saved excerpts load only when Saved is visible and stale, with loading/error/retry states and stale-response rejection. Annotation saves do not rebuild every annotated chapter's Saved excerpts.
- Position capture occurs at scroll completion, navigation/reflow, and before backgrounding, rather than scheduling a save task on every scroll frame. Equal anchors do not schedule redundant writes.
- Compact reader identity survives tab changes. Verse text, grouped highlight lookup, and batched cue edits reduce repeated main-thread work.

Success still follows a durable database transaction; no optimistic-success indication was added. Complete file protection, OS-backup eligibility, schema/migrations, and source resources are unchanged. The proposed indexed exact-annotation schema migration and broader VoiceOver/performance profiling were not added in this pass. Locked-file access, suspension timing, and physical frame pacing still need device validation.

## Validation

Toolchain: Xcode 27.0 (27A266a), Swift 6.4; deployment remains iOS/iPadOS 26.0.

- `.build/Reader-refinement-final.xcresult`: final 35 non-UI tests and four iPhone 18 Pro / iOS 27 UI tests passed after the final swatch contrast and transition guards: short-press selection, recolor/removal/Undo, turns/relaunch, and native tab tracking/short edge-drag cancellation. Final screenshots were visually inspected and are preserved in [iPhone reader evidence](../Validation/iPhone-reader-refinement/README.md).
- `.build/Reader-refinement-performance.xcresult`: 35 non-UI tests and six iPhone 18 Pro / iOS 27 UI tests passed: Books/collapse, cross-verse drag, exact recolor/removal/Undo, integrated turns/relaunch, short-press selection, and chapter/appearance round trip.
- `.build/Reader-refinement-acceptance.xcresult`: native tab press/drag tracking and a partial edge-drag cancellation check passed; an earlier Books failure in that bundle was corrected by the outer touch-region guard and superseded by the performance bundle.
- `.build/Reader-refinement-ios26.xcresult`: 35 non-UI tests and six iPhone 17 Pro / iOS 26 UI tests passed: largest-type dark Books, cross-verse drag, turns/relaunch, short-press selection, native tab tracking/short edge-drag cancellation, and Search/reference navigation.
- `.build/Reader-refinement-ipad-regression.xcresult`: 35 non-UI tests and two iPad mini (A17 Pro) / iPadOS 26 UI tests passed: wide/narrow rotation with reading-anchor restoration, and short-press selection/save. This is regression coverage, not a new iPad design pass.
- New `PaperTurnTests` checks preparation/cancellation, stale and nonadjacent commits, annotation preservation, repeated cancelled flushes, and reopened reading position.
- Debug and Release device compilation without signing passed (`/tmp/bible-reader-refinement-device-build.log` and `/tmp/bible-reader-refinement-release.log`).
- A physical iPhone test attempt stopped before execution because the two test targets lack a development team. No signing settings were changed. The Xcode device-interaction tool offered only simulators for this workspace session.

Simulator evidence does not prove physical-phone latency, magnifier feel, curl frame pacing/memory, or thin-paper visual fidelity. Full locked-device/background protection testing and release acceptance remain open.
