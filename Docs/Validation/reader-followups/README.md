# Reader follow-up validation

22 September 2026 · Xcode 27.0 (27A266a), Swift 6.4 · bundled corpus unchanged.

## Confirmed evidence

| Result bundle | Environment | Outcome |
| --- | --- | --- |
| `Scroll-turn-fix-phone` | iPhone 18 Pro / iOS 27.0 | Passed 46 non-UI tests and four UI flows: vertical/diagonal scrolling and edge taps, deliberate turns/relaunch, native selection, tab tracking/short-drag cancellation. |
| `Picker-scroll-ios26` | iPhone 17 Pro / iOS 26.0 | Passed five UI flows: picker, dark large text, direct-reference Search, scrolling/edge taps, deliberate turns/relaunch. |
| `Audit-core-phone2` | iPhone 18 Pro / iOS 27.0 | Passed 47 non-UI tests and the real-model exact key-verse question. References included chapters beyond John 3; displayed quotations came from the bundled corpus. |
| `Audit-regressions-ios26` | iPhone 17 Pro / iOS 26.0 | Passed 51 non-UI tests, picker, scrolling/edge taps, and turns/relaunch. Selection test stopped at the OS menu-paging label: iOS 26 exposes “Forward,” not iOS 27’s “Next Page.” |
| `Audit-final-ios26` | iPhone 17 Pro / iOS 26.0 | Passed 51 non-UI tests and three UI flows: picker, dark largest type, exact recolor/removal/Undo using the observed OS paging label. |
| `Audit-picker-ipad` | iPad mini (A17 Pro) / iPadOS 26.0 | Picker, dark largest type, and portrait/landscape restoration passed. Live-Saved check exposed decorative reader-background interception of sidebar taps. |
| `Audit-ipad-saved-verified` | iPad mini (A17 Pro) / iPadOS 26.0 | Live-Saved recolor and same-chapter navigation passed after the background fix. The separate large-type case inherited landscape and could not find compact Books; it was rerun with explicit portrait setup. |
| `Reader-followups-ipad` | iPad mini (A17 Pro) / iPadOS 26.0 | Largest-type picker and its Done dismissal passed. The Saved case skipped because the app did not rotate into its required wide layout. |

The subsequent `Reader-followups-ipad-saved` attempt requested landscape after launch, but the simulator still exposed a 744×1133 portrait app and no sidebar. That attempt failed at the wide-layout precondition; it did not exercise Saved editing. It is retained as an environment/rotation limitation, not counted as a pass.

Earlier failed runs are retained locally for diagnosis, not passing evidence. The first key-verse attempt was corrected after returning sources only from the current chapter. Picker composition was corrected after screenshots showed native glass obscuring separately composited labels/markers. Subsequent passing screenshots show labels, rings, and dots as glass content. The pushed chapter picker also received its own Done toolbar item, preserving dismissal at large text sizes.

## Behavioral checks

New storage tests exercise warm-cache decoding, incremental Saved equivalence to a fresh rebuild, preservation of current/neighbor chapter cache entries, cross-connection invalidation/stale Undo, and rollback after an optimistic highlight appears while an injected failing transaction is pending. Renderer tests verify unchanged documents survive state flickers and same-chapter navigation, changed-verse highlight updates, and VoiceOver geometry reuse. Existing exact-range, legacy migration/rollback, bookmark independence, source-grounding, and cancellation tests remain enabled.

- [Scrolling preserves the chapter](scrolling.png).
- [Exact Blue excerpt restored by Undo](undo.png).
- [Chapter-picker screenshots](../chapter-picker/README.md).

Static Points of Interest intervals are available for Reader bootstrap, Annotation transaction, Saved resolution, Local search, and Book source retrieval. They contain no passages, questions, annotation contents, or paths. Debug counters measure eliminated repeated work; no physical-device latency/frame-rate claim is made.

Physical gesture feel, slowest-device Release profiling, locked-device writes, broader accessibility/AI evaluation, privacy capture, and release rights acceptance remain outstanding. Search ranking/paging and storage-format/journal changes await that evidence; see [decision 0010](../../Decisions/0010-reader-performance-followup.md).

## Final pre-commit checks

`Reader-followups-phone.xcresult` passed **53 non-UI tests and three UI tests** on iPhone 18 Pro / iOS 27.0: the real-model key-verses request, large-text chapter-picker dismissal, and Search/direct-reference navigation. The unsigned generic-device Release build passed (`/tmp/Reader-followups-release.log`). `git diff --check` passed.

[Final key-verses answer](key-verses.png) and [passing iPad live-Saved flow](ipad-saved.png) were visually inspected. The latter came from `Audit-ipad-saved-verified`, not the subsequent rotation attempts. `Reader-followups-ipad-rotation` also failed to expose the wide sidebar after requesting the opposite landscape orientation. The cause of the reported device/app orientation mismatch remains unconfirmed. Repeat iPad rotation validation is outstanding; these failed attempts are not counted as passes.
