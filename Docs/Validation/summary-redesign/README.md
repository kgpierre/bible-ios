# Summary redesign evidence — 22 September 2026

Native app screenshots, not mockups. Xcode 27.0 (27A266a), iPhone 18 Pro / iOS 27.0 and iPad mini (A17 Pro) / iPadOS 26.0 simulators. Actual Foundation Models responses vary and can be inaccurate; these images do not establish theological accuracy or physical-device performance.

- `input-alignment.png`: populated input and send circle share a vertical center. The summary is real generated output; the optional heading still uses its fallback at capture time.
- `book-answer.png`: real answer, tinted question, wrapping corpus-backed reference chips, native glass input. The answer is not Scripture.
- `scope-rejection.png`: unrelated rule-override/recipe request rejected; editable multiline input remains centered.
- `largest-type-dark.png`: largest accessibility type, native suggestions menu, dark semantic canvas and glass bar.
- `ipad-refusal.png`: actual iPadOS 26 model refusal with retained input. Captured before the final vertical-centering-only fix.
- `source-opened.png`: verified reference chip opens the actual reader verse.

Validation results:

| Result bundle in `.build/` | Outcome |
| --- | --- |
| `Summary-final-phone.xcresult` | 44 non-UI tests and three UI tests passed: real summary, valid/rejected question flow with source navigation, and dark largest type. |
| `Summary-alignment-phone.xcresult` | Final alignment: two focused UI tests passed, including real model answer, refusal of unrelated input, source navigation, and dark largest type. |
| `Summary-glass-ipad.xcresult` | 43 non-UI tests and two UI checks passed for the native safe-area glass bar, editable questions/refusal handling, and dark largest type. Later additions: presentation metadata unit test, neutral overview wording, current-chapter evidence narrowing, and vertical centering. |

The initial iPad keyboard-focus test failed with `safeAreaInset`; it passed after moving the custom input to native `safeAreaBar`. The first scope classifier also falsely rejected a valid Nicodemus question; guided assessment with explicit positive scope examples resolved that observed case on iOS 27. Neither result establishes universal scope-classifier correctness. Earlier iOS 26 iPhone summary and large-type checks passed before the owner's new reference was applied.

The final unsigned Release generic iOS device build passed. Only the toolchain's existing App Intents metadata-extraction notice appeared; no Swift compiler errors/warnings were introduced. No physical-device validation, full VoiceOver audit, network-capture audit, or adversarial-injection guarantee is claimed.
