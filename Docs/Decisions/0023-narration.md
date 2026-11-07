# 0023 — Read Aloud (narration)

Status: accepted for implementation planning, 31 October 2026. The owner answered the open questions in `Docs/Plans/narration-plan.md` §16 in a planning session that day. Phases 1–3 are implemented and simulator-tested, and the owner has confirmed them working on a device. Phase 4 is implemented and unit-tested, and its device matrix is pending. Phase 5 is implemented and tested in the simulator, and its listening review is pending (evidence below). Phase 0 S1 is partly done, S2–S5 remain, and Phases 6–8 remain.

This is an explicit owner scope change. AGENTS.md listed audio as out of scope. On-device synthesized narration of the bundled corpus is now in scope. Recorded or downloadable audio, network or cloud text-to-speech, audio export, and generated or altered Scripture remain out of scope.

## Decision

- The feature is called **Read Aloud** in the UI ("Read Chapter Aloud", "Read Aloud from Here", a "Read Aloud" settings sheet). Internal type names may keep `Narration…`.
- Speech uses `AVSpeechSynthesizer` with on-device Apple voices (system, enhanced, premium) and, if the user authorizes it, Personal Voice. Third-party synthesis-provider voices are not offered. The app hosts, downloads, and caches no audio.
- The spoken text is the corpus verse text. Only the speech-only omissions listed in `NarrationScript` are allowed, and a test checks them against every verse in the bundled corpus. The approved v1 omissions are:
  - a leading `¶` and the single space after it;
  - the Hebrew letter at the start of each Psalm 119 acrostic heading. The transliteration ("ALEPH.") is still spoken.
- Psalm superscriptions, Psalm 119 acrostic headings, and the 14 trailing colophons (for example Romans 16) are spoken as source text. Source notes, gutter numbers, and the book eyebrow are never spoken.
- Pronunciation hints use `AVSpeechSynthesisIPANotationAttribute` and never change the text. The owner approves each lexicon entry by listening to it on device with the voices it was tested on. No external pronunciation reference is required.
- App-generated announcements are metadata, not Scripture. They are spoken from catalog labels and can be turned off. Natural wording: "John, Chapter 3"; "Psalm 23" for Psalms; just the book name ("Jude", "Philemon") for single-chapter books. Verse-number announcements are off by default.
- Narration continues into the next chapter by default (users can turn this off) and stops after Revelation 22 without wrapping.
- Entry points: More menu, the selection edit menu, a VoiceOver custom action per verse, ⌘⇧L, and Magic Tap. A mini player appears while narration is active. No new toolbar icon (see 0022).
- With VoiceOver running, Read Aloud uses its own voice and speed by default. A toggle switches to the VoiceOver voice settings (`prefersAssistiveTechnologySettings`).
- Background playback adds `UIBackgroundModes = audio` to the app target only. Now Playing (Lock Screen, Control Center, Apple Watch, CarPlay, AirPlay receivers) shows the chapter reference and edition label, never verse text. The help text discloses this.
- Reading position follows narration through the existing protected `reading_position` record. No new user-store migration.
- No analytics, no logging of what is spoken, no new data collection.

## Later phases (planned, after v1 playback)

- **Siri and App Intents:** `AudioPlaybackIntent` intents ("Listen to John 3", Continue Listening) and App Shortcuts. They require unlock in the first version. Starting from the Lock Screen needs a corpus-only store split, planned as separate work.
- **CarPlay audio app:** templates for browsing and playback. This needs a CarPlay audio entitlement, which the owner must request from Apple. Until it is granted, narration plays over CarPlay as a plain audio route.

## Consequences

- AGENTS.md gets a "Read Aloud directive" entry. The §1 out-of-scope list narrows "audio" to "recorded or downloadable audio".
- App Store: the audio background mode is used only for audible, user-started narration. The privacy label stays "Data Not Collected" (re-verify with network capture). App Store copy describes synthesized device voices, not a recorded audio Bible.
- The UK storefront exclusion (0015) is unchanged.

## Implementation evidence

### Phase 1 — narration script (domain only), 31 October 2026

- `BibleReader/Domain/NarrationScript.swift`: `NarrationScript` segments (chapter announcement, headings, optional verse announcements, verses, trailing colophons), the two approved omissions (`NarrationOmission`), spoken→display range mapping that widens to composed characters, a Read Aloud from Here start point, and the announcement formatter (`NarrationAnnouncement`). No UI, AVFoundation, or user-store change.
- `BibleReaderTests/NarrationScriptTests.swift` (8 Swift Testing tests). The full-corpus test checks all 1,189 chapters. Verse speech equals the corpus text minus only a leading "¶ " (2,970 verses). The Psalm 119 Hebrew letter is omitted (22 headings). The 14 colophons are spoken verbatim. All segment ranges equal `ChapterTextMap`, and 31,102 verses are covered.
- Run: Xcode 27.1 (27A9275), iPhone 18 Pro Simulator, iOS 27.0, Debug. `NarrationScriptTests` and `ChapterTextMapTests` ran together: 20 tests passed, 0 failed. No new warnings came from these files. The full suite and the iPad simulator were not run for this phase.
- The announcement strings use `String(localized:)`. They aren't in `Localizable.xcstrings` yet, because that file has unrelated uncommitted edits. Add them when it is next synced.

### Phase 2 — foreground playback, 31 October 2026

- `Features/Narration/`:
  - `SpeechSynthesizing.swift`: the engine seam over `AVSpeechSynthesizer`. The delegate (`NS_SWIFT_SENDABLE` in the 27.x SDK) yields only `ObjectIdentifier` and `NSRange` values, which are translated to tokens on the main actor. Also a minimal `.playback`/`.spokenAudio` session, and DEBUG `ScriptedSpeechSynthesizer` and `SilentNarrationAudioSession`.
  - `NarrationPreferences.swift`: `reader.narration.v1` plus the voice catalog. It offers Apple English voices and an authorized Personal Voice only, and excludes novelty voices.
  - `NarrationController.swift`: generation tokens, a queue of the current segment plus two ahead, next-chapter prefetch, never wrapping, pause and resume, verse and chapter skips, and a restart from the last word on a rate or voice change.
  - `NarrationMiniPlayer.swift` and `NarrationSettingsView.swift`.
- Wiring:
  - **AppState:** owns the controller, starting from the first visible verse or from the chapter start with its announcement.
  - **ReaderState:** `narrationSource()` reads the corpus only.
  - **Read Chapter Aloud / Stop Reading Aloud:** in the More menu.
  - **Mini player:** above the passage capsule and tabs on compact layouts, on every destination. On regular width it floats bottom trailing above the passage capsule on Read, Saved, and Search.
  - **Read Aloud row:** at the end of Appearance.
  - **Keyboard:** ⌘⇧L, ⌥⌘[ / ⌥⌘], and Stop.
  - **Magic Tap:** works only while Read Aloud is active.
  - `BIBLE_TEST_FAKE_SPEECH=1` (DEBUG) for UI tests.
- Position: written through `ReaderState.anchor` on pause, stop, and finish, and only when the reader shows the narrated chapter. A chapter the user is browsing keeps their own position. When narration enters the next chapter, the reader follows if it was showing the previous one.
- Deliberate phase-2 limits:
  - Narration pauses when the app goes to the background, until background audio arrives in phase 4.
  - Announcement toggles apply from the next chapter started, because segment indices depend on them.
  - Tabletop poses use the bottom inset (below the division) rather than `tabletopControls`.
  - "Read Aloud from Here" and the VoiceOver per-verse action stay in phase 3 with follow-along, as planned.
  - The new UI strings aren't yet in `Localizable.xcstrings` (see Phase 1).
- Accessibility sizes: the controls move to two rows. The icons stop growing at xxxLarge, as system bar items do, and Large Content Viewer shows them enlarged. The first UI run showed uncapped glyphs overlapping inside fixed 44-point frames; that is fixed with minimum 44-point frames.
- Toolchain: Xcode 27.2 (27B52), Debug, iOS 27.0 simulator runtime. Xcode changed from 27.1 (27A9275) during this session, outside this work. Phase 1 ran on 27.1.
- Results:
  - `NarrationControllerTests` (15) and `NarrationScriptTests` (8) pass.
  - `NarrationUITests` (3: More menu start/pause/resume/next verse/Saved round trip/stop, ⌘⇧L toggle, AX XXXL reachability) pass on iPhone 18 Pro and iPad mini (A17 Pro). After the icon fix, they were rerun on iPhone, and the AX screenshot was checked.
  - Full regression suites: `xcodebuild test` with `-derivedDataPath .build/DerivedData`, result bundles `.build/Full-iPhone.xcresult` and `.build/Full-iPad.xcresult`. iPhone 18 Pro: 158 Swift Testing tests passed; XCTest unit 25 (1 skipped); UI 48 (14 skipped), 0 failures. iPad mini (A17 Pro): 158 passed; 25 (1 skipped); 48 (18 skipped), 0 failures. These builds predate the icon fix, which changes only the mini player's icon frames.
  - No new compiler warnings from Read Aloud files.
- Not verified: real audio output, voice quality, word-range granularity, and Personal Voice (Simulator and scripted speech only); VoiceOver and Magic Tap by hand; hardware-keyboard shortcuts on a device; Duo poses; iOS 26 runtime.

### Phase 3 — follow-along, 2 November 2026

- **Indicator (`ChapterTextView`):** a verse tint behind the text and a word underline (accent; stronger with Increase Contrast), drawn in two non-interactive, accessibility-hidden views in the text view's content. It never writes to `textStorage`. This is the plan's fallback overlay. The preferred TextKit 2 rendering-attribute approach (spike S4) was not tried. Rectangles come from public `selectionRects(for:)` after laying out from the chapter start through the spoken range. Laying out the range alone gave estimated positions about 570 points off in a 40-verse test chapter, and the unit test caught it. Focus changes reach the reader through `NarrationObserver` (`Observations`, iOS 26), not SwiftUI updates, so word progress never reconfigures the reader.
- **Scroll follow:** a line above the visible band, or below 70% of it, moves to about 30%, animated unless Reduce Motion is on. Following is suspended while the reader is touched or scrolling and for 5 s afterward, while text is selected, while VoiceOver focus is in the chapter text, and on other destinations. After the reader scrolls away, following resumes only when the spoken line is within about a screen. Otherwise the reference in the mini player (which navigates to the verse) resumes it. Follow scrolls record the reading anchor through the existing capture path.
- **Two Pages:** every page shows the indicator where the words fall. When they reach the next spread, the spread turns once without the VoiceOver page announcement. It never jumps back or more than one spread ahead, and a selection, navigation, or a neighbor that isn't ready defers the turn to the next update. Entering the next chapter uses Phase 2's reader follow (navigation), not a curl.
- **Entry points:** "Read Aloud from Here" in the selection menu (after Share Passage; on iPhone, behind the menu's overflow chevron) starts at the selected words and leaves the selection alone. Each verse has a "Read aloud from this verse" accessibility custom action. Both appear only on the live chapter.
- **Duo tabletop:** a Read Chapter Aloud / Pause / Resume button joins the chapter controls below the division.
- **Not done in this phase:** a separate "Return to Narration" button (the mini player reference serves), and Increase Contrast color assets (the accent is derived at runtime).
- Results (Xcode 27.2 (27B52), Debug, iOS 27.0 simulator runtime):
  - `NarrationFollowAlongTests` (8): comfort band, resume-near rule, spread turn decisions, focus location, renderer work counters, text, selection and copy unchanged across a full chapter of word updates, underline placement, scroll follow versus selection, and both Read Aloud actions.
  - `NarrationUITests` (6, using `BIBLE_TEST_FAKE_SPEECH=fast` for follow-along): Read Aloud from Here plus a highlight saved while narrating, scrolling follow reaching John 3:16–17 on screen, and Two Pages turning and following into John 4 (iPad mini). All pass on iPhone 18 Pro and iPad mini (A17 Pro); the Two Pages test is skipped on iPhone. The scrolling-follow screenshot was inspected.
  - Full regression suites (`xcodebuild test`, `-derivedDataPath .build/DerivedData`). iPhone 18 Pro, iOS 27.0: 227 passed, 0 failed, 18 skipped (`.build/P3-Full-iPhone.xcresult`). iPad mini (A17 Pro), iOS 27.0: 224 passed, 0 failed, 21 skipped (`.build/P3-Full-iPad27.xcresult`). Totals combine Swift Testing (166) and XCTest. No new compiler warnings.
  - An iPad mini run on the **iOS 26.0** runtime by mistake (`.build/P3-Full-iPad.xcresult`) had 3 UI failures: `testWideTwoPageSpreadTurnsIntoNextChapterAndRestoresScroll`, `testWidgetLinkOpensValidatedPassage`, and `NarrationUITests.testReadAloudFromHere…`. On iOS 26.0, XCUITest reports Two Pages verse elements as StaticText rather than TextView. The first failure reproduces with the committed (pre-Read Aloud) reader files, so it is not caused by this work. The other two were not bisected. They look like the iPad staying in landscape Two Pages after the first failure, and that is unconfirmed. iOS 26 UI-test compatibility is still an open check.
- Not verified: Device Hub book and tabletop poses, Reduce Motion by hand, VoiceOver focus suspension by hand, Increase Contrast appearance, real-voice word timing, and the iOS 26 runtime.

### Phase 4 — background and system integration, 7 November 2026 (code and unit tests; device matrix pending)

- **Owner device check, 6 November 2026:** the owner confirmed that Read Aloud speaks and works on their iPhone 17 Pro Max (iOS 27.2, Debug build from Xcode 27.2). That covers the Phase 2–3 foreground feature on real hardware. It is not a check of each matrix row.
- **Background audio:** `UIBackgroundModes = [audio]` added to `Configuration/Info.plist`. The app target is the only one changed. `AppRootView` no longer pauses narration when the app goes to the background, and `PauseReason.appBackgrounded` was removed.
- **Session events (`NarrationAudioSession.events`):**
  - iOS 27 uses `didBecomeInactiveNotification` (system source) and `resumptionRecommendationNotification`.
  - iOS 26 uses `interruptionNotification` through a helper marked deprecated in 27. The build showed no deprecation warning with the 26.0 minimum.
  - `.oldDeviceUnavailable` route changes pause narration, which never resumes by itself.
  - A media services reset rebuilds the `AVSpeechSynthesizer` and resumes from the last spoken word.
  - Resuming after an interruption reactivates the session. A user pause is never overridden.
  - Activation still uses `setActive(_:)` on both OS versions, because the seam is synchronous. The plan's iOS 27 `activate(options:completionHandler:)` path is not adopted.
- **Now Playing (`NarrationNowPlaying.swift`):**
  - Fields: title (chapter reference), artist (edition), album "Bible", media type audio, and playback rate. No verse text, elapsed time, or duration.
  - Remote commands: play, pause, toggle, next track (next chapter), and previous track (restarts the chapter after verse 1, otherwise goes back a chapter, never before Genesis 1).
  - Disabled commands: skip, seek, position, rate, like, dislike, bookmark, and rating.
  - Commands are disabled whenever narration is idle.
- **Sleep timer:** in the mini player menu, with Off, End of Chapter, and 15, 30, 45, or 60 minutes. It applies to the current session only.
  - A minutes timer pauses at the next segment boundary. If a verse runs more than 30 seconds past the deadline, it pauses at a word boundary.
  - End of Chapter stops before the next chapter, trimming any of it already queued. Resume starts the next chapter with its announcement.
- **Background position:**
  - While backgrounded, narration saves its verse at verse starts, at most every 5 s.
  - When narration enters another chapter in the background, `ReaderState` doesn't navigate, because navigating reads the user store, which is unavailable while locked. Instead it keeps a pending follow and saves narration's position directly. A locked store is retried after unlock and never reported.
  - The reader's own position writes yield while a follow is pending. When the scene becomes active again, the reader moves to the narrated verse.
- **Results (Xcode 27.2 (27B52), Debug):**
  - iPhone 18 Pro simulator, iOS 27.0: `NarrationControllerTests` (27, including 12 new) and the follow-along and script suites, 43 tests passed. The controller suite also passed three repeat runs.
  - `NarrationUITests`: 5 passed, and the Two Pages test is skipped on iPhone as designed.
  - The device build for the iPhone 17 Pro Max succeeded and was installed.
  - No new compiler warnings.
- **Not verified:**
  - The device matrix rows for background, Lock Screen, interruptions, and routes. Each needs manual checks on iOS 27, and an iOS 26 device is also required. None are recorded yet.
  - Corpus reads while locked (S3).
  - The pending-follow path in `ReaderState`, which has no unit test.
  - Network capture.
  - The full regression suites and iPad, which were not run for this phase.

### Phase 5 — voices and pronunciation, 7 November 2026 (code and tests; listening review pending)

- **Natural voices:** when no Enhanced or Premium voice is installed, the Read Aloud sheet opens with "Get More Natural Voices" and the steps to download one in Settings. Apps can't download voices or open that screen, so this is guidance only. New voices appear through `availableVoicesDidChangeNotification`.
- **Personal Voice:**
  - "Use My Personal Voice…" asks for permission once. The system remembers the answer.
  - When access is denied, an Open Settings button opens the app's settings page.
  - When access is granted but no Personal Voice exists, a note says where to create one.
  - Personal Voice is never the default; it's used only when chosen.
- **Pause Between Verses:** None, Short (0.35 s, the default), or Long (0.8 s). It uses each utterance's post-delay. It doesn't use SSML, because an SSML utterance ignores rate (plan §4.5). The owner asked for pauses as SSML on 6 November 2026; this delivers the pauses without losing the speed setting.
- **Pronunciation hints:**
  - `Domain/NarrationLexicon.swift` and `Resources/NarrationLexicon.json` hold the hints. They match whole words, case-sensitively, and the IPA is applied with `AVSpeechSynthesisIPANotationAttribute` on `AVSpeechUtterance(attributedString:)`.
  - Entries without IPA or a review are dropped.
  - The list ships **empty** (decision Q11), and the "Use Pronunciation Hints" toggle stays hidden until reviewed entries exist.
- **Results (Xcode 27.2 (27B52), Debug, iPhone 18 Pro simulator, iOS 27.0):**
  - `NarrationControllerTests`, `NarrationLexiconTests` (5), `NarrationScriptTests`, and `NarrationFollowAlongTests`: 54 passed.
  - The full-corpus lexicon test, with hints on six common names, found the spoken string unchanged for every segment, and every hint covered exactly its word.
  - `NarrationUITests`: 7, including the new settings test, which passed when run on its own. Its screenshot was inspected.
  - No new warnings.
- **Not verified:**
  - Whether voices honor IPA, and word ranges inside hinted words (spike S2).
  - The Personal Voice prompt and voices on a device.
  - Enhanced and Premium voice behavior.
  - The owner's listening review of the pause lengths.

## Open checks

S1 is partly done on an iPhone 17 Pro Max running iOS 27.2 (6 November 2026; [results](../Validation/narration-spike/README.md)). Default-quality voices speak `LORD` as a word. Some voices speak `¶` (Eloquence, Fred) and the Hebrew letter (Fred), which confirms the approved omissions. Every voice reports word-level ranges on the main thread. The device unit suite passed: 166 Swift Testing tests, and 25 XCTest with 1 skipped. Otherwise, the plan's Phase 0 spikes S1–S5 and the §17 "Not verified" list remain open. In particular, enhanced, premium, and Personal Voice behavior; listening checks, including how `æ` sounds; TextKit 2 rendering attributes in `UITextView`; corpus readability while locked; and the iOS 26 vs 27 interruption paths.
