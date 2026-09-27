# Interactive thin-paper chapter turn — 25 September 2026

The owner asked to refine the page-turn animation. They chose all four proposals: a curl that follows the finger, a thin-paper reverse side, a quicker turn response, and a subtle haptic. This supersedes the post-lift discrete curl from decision 0007 for motion-enabled reading. The accessible fallbacks stay.

## Findings before the change

Findings from a simulator recording (iPhone 18 Pro, iOS 27):

- The curl was a canned `setViewControllers(animated:)` animation of about 0.3–0.4 s. It started only after the finger lifted, so nothing tracked the drag.
- With `isDoubleSided = false`, UIKit rendered the curling page's reverse as a pale translucent strip, including in dark mode. Decision 0005 flagged exactly this "bright reverse side".
- A suspected missed first swipe after launch did not reproduce (three of three turned).

## Implementation

- **Finger-following curl.** `PaperChapterView.Coordinator` is now the pager's data source and delegate. It adopts UIKit's public `gestureRecognizers`: the pan's delegate begins only for a clearly horizontal drag (translation ≥ 2× vertical, velocity ≥ 1.5× vertical) with no selection, save, or navigation in progress. The tap recognizer is disabled, so edge taps never turn. Each text view's scroll pan requires that curl pan to fail, so vertical or diagonal drags fail it at once into native scrolling. That preserves the owner's earlier scroll-versus-turn correction.
- **Commit only on completion.** `willTransitionTo` marks an interactive turn. `didFinishAnimating(completed:)` commits through `ReaderState.commitTurn`, which rejects stale or non-adjacent turns as before. Cancelled, stale, or rejected turns reconcile back to the canonical chapter without animation. External navigation, resizing, and theme or type changes cancel a live curl by toggling its recognizer instead of replacing pages under UIKit.
- **Canonical target.** `update` now targets `state.document`, not the representable's captured document, and animation completions reconcile with the reader. A test turn exposed a real mismatch: a one-update-stale document curled the screen back to John 3 while the reader was on John 4.
- **Thin-paper back.** `ReaderCurlController` is double-sided. `PaperBackController` is the reading canvas with the page's own print mirrored at 9% (light) or 12% (dark) opacity. It uses a render-server `snapshotView`, is removed on disappearance, and is hidden from accessibility. It is omitted with Reduce Transparency, and a page that isn't on screen shows plain paper. UIKit's contract, verified and covered by `doubleSidedCurlAcceptsPageAndThinPaperBack`, is `[page]` for an immediate change and `[page, back]` for an animated curl in either direction. The data source supplies front → back → next-front for gestures and never wraps at Genesis 1 or Revelation 22.
- **Quicker response.** The live curl responds from the first horizontal movement. The discrete swipe, used with Reduce Motion, Reduce Transparency, Increase Contrast, or VoiceOver, accepts `max(36, min(56, 10% width))` points instead of `max(44, min(64, 12% width))`. It still commits immediately without a curl.
- **Haptic.** A soft `UIImpactFeedbackGenerator` tick (intensity 0.7) fires only when a turn actually commits. It is prepared when a curl begins. The system haptics setting applies.

## Validation

In the simulator, drags turned correctly from the center, from both halves, in short and slow variants, forward and back, in light and dark, and with `swipeLeft`. Each time the live text view matched the committed chapter. See the README entry for suite results. Physical-device feel, frame pacing, memory across repeated turns, and haptic strength still need the owner's on-device check. A simulator recording is not evidence of physical fidelity.

## Follow-up: first-use stalls on device (owner report)

The owner reported that the first swipe and the first Search open were slow on a physical phone; later ones were fine.

- **First swipe.** The adjacent chapter's page, including its TextKit layout, was built synchronously inside UIKit's data-source call when the drag began. After each chapter change, the neighboring pages are now built and laid out ahead of time, one per main-actor turn (`prepareNeighbors`). The one-time cost of UIKit's own first curl render cannot be warmed with public API.
- **First Search open.** Opening the tab focused the field, forcing the first keyboard presentation of the session, a known main-thread stall on device. Opening the tab no longer focuses the field. Tapping the field, ⌘F, and More → Search still do. Search still prewarms the reference parser and FTS pages in the background.

A simulator Time Profiler trace could not reproduce either stall; the only main-thread burst was XCUITest loading accessibility bundles. Confirm on device, preferably with a Release build, because Debug builds are much slower.

## App icon

The owner-supplied Icon Composer exports (Default, Dark, and ClearDark as Tinted) populate `AppIcon` and the About `AboutIcon`. They had transparent rounded corners, which the App Store rejects, so the corners were filled with a blurred extension of the artwork and the files flattened to opaque 1024-pixel PNGs. The exports include Icon Composer's rendered glass rim. For a true Liquid Glass icon, add the `.icon` document to the project instead.
