# Narration (Read Aloud) — Implementation Plan

Date: 30 October 2026
Status: **Phases 1–3 implemented**, simulator-tested, and confirmed by the owner on a device. **Phases 4 and 5 implemented and tested** in the simulator (7 November 2026). Phase 4's device matrix and Phase 5's listening review are pending. Phase 0 S1 is partly done. Phases 6–8 remain. The owner accepted the scope change and answered every §16 question on 31 October 2026. Implementation evidence and limits are recorded in [0023](../Decisions/0023-narration.md); this plan does not itself show that any behavior works.

UI name: **Read Aloud**. Type names keep the `Narration…` prefix.

This plan describes how narration would work and in what order to build it. It does not show that any behavior works. Section 17 lists the API details checked against the installed SDK and the ones still unverified.

---

## 1. Summary

Add optional narration that reads the current chapter aloud with Apple's on-device speech synthesizer (`AVSpeechSynthesizer`). The current verse is highlighted as it is spoken, and the current word too when the voice reports word ranges. In Scroll mode the reader keeps the spoken line in view. In Two Pages mode it turns the page. Narration continues into the next chapter and stops at the end of the Bible without wrapping. It keeps playing in the background and from the Lock Screen, with Now Playing, remote commands, interruption and route-change handling, and an optional sleep timer.

The spoken text is the corpus text exactly. The only changes are a short, documented, tested list of speech-only omissions (for example the `¶` paragraph sign). Pronunciation hints change only how a word sounds, through an attribute. They never change the characters. There is no network speech, no hosted or downloaded audio, no audio cache, and no analytics.

---

## 2. Scope and owner decision (draft decision record)

**Accepted 31 October 2026.** The scope change is filed as [`Docs/Decisions/0023-narration.md`](../Decisions/0023-narration.md). AGENTS.md has a Read Aloud directive, and its out-of-scope list now says "recorded or downloadable audio". The draft below is kept for history. 0023 is authoritative where they differ.

```markdown
# 0023 — Narration (read aloud)

Status: proposed, awaiting owner decision. Owner request: <quote the owner's words>.

This is an explicit owner scope change. AGENTS.md listed audio as out of scope. On-device
synthesized narration of the bundled corpus is now in scope. Recorded or downloadable audio,
network or cloud text-to-speech, audio export, and generated or altered Scripture remain out of scope.

## Decision
- Speech uses AVSpeechSynthesizer with voices installed on the device (system, enhanced, premium,
  and, if the user authorizes it, Personal Voice). The app hosts, downloads, and caches no audio.
- The spoken text is the corpus verse text. Only the speech-only omissions listed in
  `NarrationScript` are allowed, and a test checks them against every verse in the bundled corpus.
  Pronunciation hints use AVSpeechSynthesisIPANotationAttribute and never change the text.
- App-generated announcements ("John, Chapter 3", and verse numbers when turned on) are
  metadata, not Scripture. They are spoken from catalog labels and can be turned off.
- Background playback adds `UIBackgroundModes = audio`. Now Playing shows the chapter reference
  and the edition label only.
- Reading position follows narration and uses the existing protected `reading_position` record.
  No new user-store migration.
- No analytics, no logging of what is spoken, no new data collection.

## Consequences
- AGENTS.md scope list and HANDOFF.md get a "Narration directive" entry.
- App Store: the audio background mode is used only for audible user-started narration.
  The privacy label stays "Data Not Collected" (re-verify with network capture).
- Lock Screen and Control Center show the chapter being read (see Open questions).

## Open checks
<carried from the plan's acceptance gates>
```

Done on acceptance: the AGENTS.md "Read Aloud directive — 31 October 2026" block and the narrowed out-of-scope entry.

### Goals

1. Read any chapter aloud, offline, on first launch, in airplane mode.
2. Speak the Scripture exactly. Make every speech-only difference explicit and test it.
3. Follow along (verse and word highlight, scrolling, page turns) without changing the selection, annotations, or the attributed document.
4. Continue across chapters and books. Never wrap at Genesis 1 or Revelation 22.
5. Play in the background and on the Lock Screen, with system media controls and correct interruption and route behavior.
6. Remember where narration stopped, using the existing reading-position contract.
7. Work with VoiceOver, Dynamic Type, Reduce Motion, keyboards, and every current layout (compact 2a, regular-width iPad top tab bar, Duo postures).

### Non-goals

- Recorded human narration, downloadable audio packs, or streaming.
- Cloud or third-party network speech engines, including server-backed synthesis provider extensions (see §11).
- Exporting or sharing audio files. `writeUtterance(_:toBufferCallback:)` is not used.
- Reading Saved lists, search results, summaries, or source notes aloud in v1. Summaries are not Scripture and must never be read in the Scripture voice stream.
- Playlists, reading plans, streaks, or listening statistics.
- CarPlay templates in v1. They are a later phase (§14, phase 7) that needs a CarPlay audio entitlement. Until then, audio still plays over CarPlay as a plain audio output.
- Third-party synthesis-provider voices (owner decision, §16 Q5).
- Replacing the system's Speak Screen and Speak Selection features. They stay available.

---

## 3. Existing code this builds on

| Area | Existing type or file | Relevance |
| --- | --- | --- |
| Chapter model | `Domain/ChapterDocument.swift` (`ChapterDocument`, `Verse`, `Run`, `SourceBlock`, `VerseAnchor`, `ReadingAnchor`) | Verse text = joined runs. `headings` holds source `s`/`d` blocks. `trailingBlocks` holds colophons. `Run.italic` marks KJV supplied words (`<add>`). |
| Rendered text map | `Domain/ChapterTextMap.swift` | Chapter text = `heading\n…verse\n…trailing\n`. `entries[i].range` is the UTF-16 verse range. `sourceHeadingRanges` lists headings in order. Narration ranges must match this map exactly. |
| Pagination | `Domain/ChapterPagination.swift` | `page(containing:)` maps a UTF-16 offset to a page index for Two Pages turns. |
| Reader state | `Features/Reader/ReaderState.swift` (`@MainActor @Observable`) | `navigate(to:verseID:…)`, `moveChapter(by:)`, `hasAdjacentChapter`, `catalog`/`catalogIndex`, `anchor` (debounced `schedulePositionSave`), `flushPosition(protectInBackground:)`, `waitForProtectedData`, `summaryState(for:)` (the pattern for handing a store-backed closure to a feature). |
| Store | `Data/BibleStore.swift` (`actor BibleStore`) | `chapter(_:)` reads the read-only bundled corpus with an LRU cache. `savePosition` writes the user DB, which has **complete** file protection. |
| Renderer | `Features/Reader/NativeChapterView.swift` (`ChapterTextView`, TextKit 2 only, never `layoutManager`) | `configure(…)`, `applyHighlights` (persistent fills in `textStorage`), `navigationCue` underline, `capturePosition`, `restorePosition`, `prepareVerseAccessibility`, `textView(_:editMenuForTextIn:suggestedActions:)`. |
| Scroll reader / curls | `Features/Reader/PaperChapterView.swift` (`PaperChapterView.Coordinator`, `ChapterPageController`) | Chapter curls in Scroll mode. Neighbor preparation. |
| Two Pages | `Features/Reader/SpreadChapterView.swift` (`Coordinator.turn(by:)`, `spread(_:)`, `didShow`, `finishTurn`, `curling`, `announcePage`) | Programmatic page turns cross chapter boundaries through `key(after:)` and `commitTurn`. |
| Layout | `App/AppRootView.swift` (`compactLayout`, `regularLayout`, `chapter(wide:active:)`, `foldLayout`, `tabletopControls`, `readerToolbar`) | Placement of entry points and the mini player. |
| Compact chrome | `Features/Reader/CompactReaderNavigation.swift` (`CompactReaderNavigation`, `ReaderNavigationLayout`, `PassageButton`) | 2a bottom row. The mini player row goes here. |
| Commands | `App/ReaderCommands.swift` (`acceptsReaderShortcuts`) | Keyboard shortcuts. |
| Preferences | `Features/Settings/ReaderPreferences.swift` (key `reader.appearance.v1`), `AppearanceView.swift` | Pattern for typed, versioned `UserDefaults` payloads. |
| Availability pattern | `Features/Summary/ChapterSummary.swift` (`ChapterSummaryModel.unavailableReason()`, `ChapterSummaryState.Status.unavailable`) | Template for voice availability states and a protocol-injected engine. |
| Background writes | `App/BackgroundWriteLease.swift`, `AppRootView.onChange(of: scenePhase)` | Flush narration position on lifecycle changes. |
| Privacy | `Resources/PrivacyInfo.xcprivacy` (UserDefaults, DiskSpace reasons) | Narration adds no new required-reason API categories, as planned. |
| Plist | `Configuration/Info.plist` plus `INFOPLIST_KEY_*` in `project.pbxproj` | Add `UIBackgroundModes`. |

### Corpus facts that shape speech (measured from the bundled `BibleCorpus.sqlite`)

- 31,102 verses. No bridged verses: `Content/Tools/build_corpus.py` rejects nonsequential or bridged labels. Labels are sequential integers per chapter. The script must still handle bridges generically (§4.4) for future editions.
- `¶` (pilcrow) begins **2,970** verses, for example `JHN:3:16` "¶ For God so loved…". Synthesizers may say "pilcrow" or "paragraph". Spike S1 checks this.
- Other non-ASCII characters in verse text: `’` (1,996), `æ` (93, for example "Cæsar"), `Æ` (3), `—` (1).
- 138 verses carry headings: Psalm superscriptions (`d`, for example PSA 3 "A Psalm of David, when he fled from Absalom his son.") and Psalm 119's acrostic headings (`s`, for example "א ALEPH."), which include a **Hebrew letter**.
- 14 chapters have `trailingBlocks` (Pauline colophons, for example ROM 16 "Written to the Romans from Corinthus…").
- Structure values are `p` (28,641) and `q1` (2,461).
- `LORD` is stored in capitals (from `<nd>`). Whether voices say "Lord" or spell it out is unverified (S1).

---

## 4. Scripture fidelity

### 4.1 Rule

The speech string for a verse is `verse.text` with only the omissions in the allow-list below. Nothing is added inside the verse string, and nothing is reordered, modernized, expanded, or corrected. Any text that is not Scripture (announcements, verse numbers) is a **separate segment** with its own kind. It is never mixed into a verse segment's range map. This mirrors how gutter numbers stay outside selectable text.

### 4.2 Speech-only omission allow-list (v1, owner-approved 31 October 2026)

| Omission | Why | Mapping |
| --- | --- | --- |
| A leading `¶` and the single space after it | Typographic paragraph mark, not a word | The removed range is recorded. Spoken offsets map back to display offsets past the mark. |
| The Hebrew letter at the start of a Psalm 119 acrostic heading (owner-approved, Q4) | "ALEPH." follows, so the letter's name is still heard | As above. Applied regardless of S1 results. |

Everything else is spoken as stored, including `æ`, `’`, `LORD`, and punctuation. A full-corpus test (§13) checks that removing the allow-list items from `verse.text` gives exactly the speech string for all 31,102 verses. It also checks that the attributed speech string's `.string` equals the plain speech string, so pronunciation attributes never change text.

### 4.3 Element policy

| Element | Default | Notes |
| --- | --- | --- |
| Verse text | Spoken | One verse segment per verse. |
| Italic runs (`Run.italic`, KJV supplied words) | Spoken plainly, **without emphasis** | KJV italics mark words the translators supplied, not stress. The speech string is built from plain text, never from the display `NSAttributedString`, so font traits cannot leak in. |
| Psalm superscriptions (`d`) and Psalm 119 acrostic headings (`s`) | Spoken before their verse as a `heading` segment | They are source text shown in the reader and are selectable (`ChapterTextMap.sourceHeadingRanges`). |
| Trailing colophons (`trailingBlocks`) | Spoken after the last verse (owner-approved, Q3) | Source text from the 1769 edition, shown in the reader. |
| Verse numbers | **Not spoken** by default. Optional "Announce Verse Numbers". | When on, a separate `announcement` segment such as "Verse 16" (localized, from `Verse.label`) plays before the verse. It is never part of the verse range map. |
| Chapter announcement | "John, Chapter 3" before verse 1 (setting "Announce Chapters", default on) | Built from catalog labels. Natural wording (Q6): "John, Chapter 3"; "Psalm 23" for Psalms; just the book name ("Jude") for single-chapter books. A small, tested formatter owns these rules. It is metadata, not Scripture. |
| Book eyebrow ("THE GOSPEL ACCORDING TO") | Not spoken | Display furniture. |
| Source notes (`Verse.notes`) | Never spoken | They are never in copy or search either. Keep that boundary. |
| Gutter, bookmark, and note markers | Never spoken | They are not in the text map. |

### 4.4 Bridged verses (future editions)

If a future edition has a bridge label such as `3-4`, it is one verse record. It is spoken as one segment and announced (when verse numbers are on) as "Verses 3 to 4", built from the label string by a small, tested label formatter that never makes up two verses. The current corpus has none. Cover this with a synthetic `ChapterDocument` fixture test.

### 4.5 Pronunciation without altering text

- Mechanism: `NSAttributedString` with `AVSpeechSynthesisIPANotationAttribute` (verified in the SDK header: "NSString, containing International Phonetic Alphabet (IPA) symbols. Controls pronunciation of a certain word or phrase, e.g. a proper name.") on the exact UTF-16 range of a name, passed to `AVSpeechUtterance(attributedString:)`.
- Source: a reviewed, bundled lexicon `BibleReader/Resources/NarrationLexicon.json` (`{ "word": "Cenchrea", "ipa": "…", "scope": "whole-word", "reviewed": "<date/initials>" }`), matched by whole token and case. It is applied in the script builder (§5.1). Never generate it with AI at runtime. Never fetch it.
- Limits, all unverified until spike S2:
  - Voices may ignore the IPA attribute, especially premium (neural) and Personal Voice.
  - `willSpeakRangeOfSpeechString` may report a different granularity inside an IPA range.
  - IPA inventories differ by voice language (en-US and en-GB).
  - Wrong IPA can sound worse than the default.
- Policy: phase 5 only. The lexicon starts empty. The owner approves each entry by listening on device with the voices it was tested on (Q11); no external pronunciation reference is required. Record the voices and the approval date in the entry's `reviewed` field. Turning pronunciation hints off falls back to the voice's default.
- Rejected alternative: SSML (`AVSpeechUtterance(ssmlRepresentation:)`, iOS 16+). The header says rate, pitch, and volume "will not apply to an utterance that uses an SSML representation". SSML would also add markup to the speech string and complicate the offset map.

---

## 5. Architecture

### 5.1 New and changed files

New folder `BibleReader/Features/Narration/`. AGENTS.md §4 lists feature folders by responsibility, so this follows the convention.

| File | Kind | Responsibility |
| --- | --- | --- |
| `Domain/NarrationScript.swift` | Pure value types, `Sendable` | Builds the ordered segments of a `ChapterDocument`. Each holds a speech string, an attributed speech string (IPA), a display range in `ChapterTextMap.text`, and a speech→display offset map. No UIKit or AVFoundation. |
| `Domain/NarrationLexicon.swift` + `Resources/NarrationLexicon.json` | Pure | Optional pronunciation entries (phase 5). |
| `Features/Narration/SpeechSynthesizing.swift` | Protocol + `SystemSpeechSynthesizer` | A thin seam over `AVSpeechSynthesizer` that emits typed events. The fake for tests lives in the test target. |
| `Features/Narration/NarrationAudioSession.swift` | Protocol + system implementation | Category, activation, and deactivation. Interruption and route events, with an iOS 26 path and an iOS 27 path (§9.2). |
| `Features/Narration/NowPlayingCoordinator.swift` | `@MainActor` | `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` registration and teardown. |
| `Features/Narration/NarrationController.swift` | `@MainActor @Observable final class` | State machine, queueing, chapter continuation, sleep timer, position persistence, follow-along focus. |
| `Features/Narration/NarrationPreferences.swift` | `@MainActor @Observable` | Voice ID, rate, announcements, follow-along, continue to next chapter. `UserDefaults` key `reader.narration.v1`, using the `ReaderPreferences` payload/version pattern. |
| `Features/Narration/NarrationVoiceCatalog.swift` | `@MainActor` | Lists usable voices, quality labels, Personal Voice authorization, availability-change refresh. |
| `Features/Narration/NarrationMiniPlayer.swift` | SwiftUI | Glass capsule with play/pause, previous/next verse, the reference (tap to go to it), and a Read Aloud menu. |
| `Features/Narration/NarrationSettingsView.swift` | SwiftUI | Voice, speed, announcements, follow-along, continuation, sleep timer. |
| `Features/Narration/NarrationIntents.swift` | App Intents (phase 6, optional) | `AudioPlaybackIntent` intents. |

Changed files (in later phases, not now):

- `App/AppState.swift`: owns `let narration: NarrationController`. `init(reader:narration:)` gets a default argument so tests can inject one.
- `Features/Reader/ReaderState.swift`: add `narrationSource()`, which returns `Sendable` closures over the private `store` for chapter loading and position saving, like `summaryState(for:)`. Add an observable `narrationFocus: NarrationFocus?` that views read. Add `followNarration(to:)`, which navigates without blocking on annotation loads while the device is locked (§9.4).
- `Features/Reader/NativeChapterView.swift`: render the narration indicator without touching `textStorage` (§6.2). Add "Read Aloud from Here" to the edit menu. Add a "Read aloud from this verse" VoiceOver custom action in `prepareVerseAccessibility`. Add follow-along scrolling.
- `Features/Reader/SpreadChapterView.swift`: `Coordinator.followNarration(_:)` turns pages. Don't post `announcePage` when a turn was caused by narration.
- `Features/Reader/PaperChapterView.swift`: pass the focus through to the live `ChapterTextView`.
- `Features/Reader/CompactReaderNavigation.swift`: an optional mini-player row inside `ReaderNavigationLayout`.
- `App/AppRootView.swift`: a "Read Chapter Aloud" item in the More menu, mini-player placement in the regular layout and Duo layouts, lifecycle hooks, and Magic Tap.
- `App/ReaderCommands.swift`: narration commands (§8.4).
- `Configuration/Info.plist`: `UIBackgroundModes` → `audio`.
- `Resources/Localizable.xcstrings`: new strings.
- `README.md`, `HANDOFF.md`, `AGENTS.md`, `Docs/Decisions/0023-narration.md`, `Docs/Validation/narration/README.md`.

### 5.2 Domain: `NarrationScript`

```swift
struct NarrationScript: Sendable, Equatable {
    struct Segment: Sendable, Equatable, Identifiable {
        enum Kind: Sendable, Equatable { case chapterAnnouncement, verseAnnouncement, heading, verse, trailing }
        let id: Int                       // order within the chapter
        let kind: Kind
        let verseID: String?              // verse, verseAnnouncement, and the heading's following verse
        let displayRange: NSRange?        // range in ChapterTextMap.text; nil for announcements
        let speech: String                // exact speech string
        let omissions: [NSRange]          // removed display sub-ranges, relative to displayRange
        func displayRange(forSpoken range: NSRange) -> NSRange?   // clamps to composed-character boundaries
    }
    let chapterID: String
    let segments: [Segment]
    init(document: ChapterDocument, options: NarrationScriptOptions, lexicon: NarrationLexicon = .empty)
    func segmentIndex(startingAt anchor: VerseAnchor) -> (index: Int, speechOffset: Int)?
}
```

- It iterates `document.verses` and `trailingBlocks` in the **same order and with the same UTF-16 arithmetic** as `ChapterTextMap.init`. A test checks that every `verse` segment's `displayRange` equals the matching `ChapterTextMap.entries[i].range`, and that `heading` and `trailing` ranges equal `sourceHeadingRanges` in order. Changing one without the other then fails tests. A later cleanup could have `ChapterTextMap` expose heading→verse association so both share one walk.
- The attributed string (`NSAttributedString` is not `Sendable`) is made on demand on the main actor by `SystemSpeechSynthesizer` from `speech` plus lexicon ranges, so the script itself stays `Sendable`.
- Building is O(chapter) and cheap (Psalm 119 is 176 verses). It can run on the main actor. Measure with the existing `ReaderPerformance.signposter` before moving it.

### 5.3 Engine seam: `SpeechSynthesizing`

```swift
@MainActor protocol SpeechSynthesizing: AnyObject {
    var events: AsyncStream<SpeechEvent> { get }
    func enqueue(_ request: SpeechRequest)        // segment text, IPA ranges, voice ID, rate, token
    func pause() -> Bool                          // pauseSpeaking(at: .word)
    func resume() -> Bool                         // continueSpeaking()
    func stop()                                   // stopSpeaking(at: .immediate)
}
enum SpeechEvent: Sendable { case started(token: SpeechToken), willSpeak(token: SpeechToken, range: NSRange),
                              finished(token: SpeechToken), cancelled(token: SpeechToken), paused, resumed }
struct SpeechToken: Hashable, Sendable { let generation: Int; let segment: Int; let chapterID: String }
```

- `SystemSpeechSynthesizer` keeps a strong reference to one `AVSpeechSynthesizer`. A synthesizer that is deallocated mid-speech goes silent. It maps each `AVSpeechUtterance` to a `SpeechToken` through `ObjectIdentifier`.
- **Swift 6 isolation.** The SDK header does not document which thread delegate callbacks arrive on, and `AVSpeechSynthesizer` and `AVSpeechUtterance` are not marked Sendable (only `AVSpeechSynthesisVoice` and the marker types carry `NS_SWIFT_SENDABLE`). So the delegate is a separate `nonisolated final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate`. Each callback reads only `ObjectIdentifier(utterance)` and the `NSRange`, both Sendable, and yields into an `AsyncStream.Continuation`, which is Sendable. No `MainActor.assumeIsolated`, because the callback thread is undocumented. The controller consumes the stream in a main-actor `Task` started on first play and cancelled on teardown.
- **Stale-event rejection.** Every stop, seek, chapter change, or rate restart increments `generation`. Events with an older generation are dropped. This mirrors `navigationRequest` and `linkRequest`.
- **Queue depth.** Keep the current segment plus up to 2 ahead queued in the synthesizer, so verse boundaries have minimal gaps without a long queue that would have to be cancelled on every seek. Tune in spike S3.

### 5.4 `NarrationController`

```swift
@MainActor @Observable final class NarrationController {
    enum Status: Equatable { case idle, preparing, playing, paused(PauseReason), finished(EndReason), unavailable(String), failed(String) }
    enum PauseReason: Equatable { case user, interruption, routeLost, sleepTimer }
    enum EndReason: Equatable { case endOfChapter, endOfBible, sleepTimer }
    private(set) var status: Status
    private(set) var focus: NarrationFocus?      // chapterID, segment kind, verseID, display verse range, word range, revision
    private(set) var sleepTimer: SleepTimer?
    var followsAlong: Bool                         // session-level; suspends while the user browses (§6.3)
    init(source: NarrationSource, synthesizer: any SpeechSynthesizing, audio: any NarrationAudioSession,
         nowPlaying: NowPlayingCoordinating, preferences: NarrationPreferences, voices: NarrationVoiceCatalog,
         clock: any Clock<Duration> = ContinuousClock())
    func play(from anchor: VerseAnchor?, in chapterID: String)  // nil = start of chapter
    func togglePlayPause(); func pause(_ reason: PauseReason); func resume(); func stop()
    func skipVerse(by delta: Int); func skipChapter(by delta: Int)
    func setRate(_ preset: NarrationRate)  // restarts the current segment from the last spoken word
    func setSleepTimer(_ option: SleepTimerOption?)
}
struct NarrationSource: Sendable {
    let chapter: @Sendable (String) async throws -> ChapterDocument          // BibleStore.chapter (corpus only)
    let adjacentChapterID: @MainActor (String, Int) -> String?               // catalog order, never wraps
    let reference: @MainActor (String) -> String?                            // catalog display reference
    let savePosition: @MainActor (String, VerseAnchor) -> Void               // routed through ReaderState (§9.4)
}
```

- `AppState` builds the controller from `reader.narrationSource()` and the system implementations. Unit tests inject fakes and a test clock (constructor injection, no service locator, per AGENTS.md §4).
- The controller owns **a narration cursor separate from the reader's chapter**. Narration can continue while the user browses Saved, Search, or another chapter, and while the app is backgrounded and SwiftUI does not update views. The reader *follows* the cursor only when follow-along is active and the app is in the foreground.
- All mutable state is `@MainActor`. Corpus decoding stays on the `BibleStore` actor. The controller doesn't touch GRDB or SQLite directly.

---

## 6. Follow-along: mapping, highlight, scrolling, page turns

### 6.1 Mapping spoken ranges to verse IDs and UTF-16 ranges

1. `willSpeak(token, range)` → segment `token.segment` of the script for `token.chapterID`.
2. `segment.displayRange(forSpoken: range)` → the chapter UTF-16 range. It adds back omitted characters before the offset and clamps to composed-character boundaries, using `rangeOfComposedCharacterSequence` like `ChapterTextMap.offset(for:)`.
3. `focus = NarrationFocus(chapterID, verseID: segment.verseID, verseRange: segment.displayRange, wordRange: mapped, revision += 1)`.
4. For announcements, `wordRange` is nil and `verseRange` points at the verse being announced, so the highlight leads slightly.
5. When a voice reports no word ranges, or ranges as coarse as the whole utterance (to be verified per voice class in S1), the UI shows only the verse-level indicator. It never interpolates word positions from time.

Ranges are offsets into the rendered chapter text, never pixels or row numbers, and are recomputed per chapter build (AGENTS.md §6).

### 6.2 Rendering the indicator without disturbing selection or annotations

- **Do not modify `textStorage`.** Persistent highlights (`applyHighlights`) and the navigation cue already write `.backgroundColor` and `.underlineStyle` into `textStorage`. A per-word narration update there would invalidate layout, change `annotationsRevision`-dependent work, risk resetting `selectedRange` and `contentOffset`, and could leak into `copy(_:)`.
- **Preferred:** TextKit 2 rendering attributes on `textLayoutManager`: `addRenderingAttribute(_:value:for:)`, `removeRenderingAttribute(_:for:)`, `invalidateRenderingAttributes(for:)` (verified in `UIKit/NSTextLayoutManager.h`). These are drawing-time overlays that don't change content. Apply a verse-level tint (new semantic color asset `NarrationVerse`, light and dark) plus a word underline (`NarrationWord` accent), so the indicator doesn't rely on color alone. **Unverified:** which rendering attribute keys a `UITextView` honors in TextKit 2 (background vs underline), and whether rendering attributes survive `attributedText` replacement. They are expected to be cleared, and `configure` must re-apply `focus` after any document rebuild. Spike S4.
- **Fallback:** a non-interactive overlay layer under the glyphs, built from `textLayoutManager.enumerateTextSegments` in the same way `layoutGutters` positions gutter numbers. Set `isUserInteractionEnabled = false` and exclude it from accessibility.
- The indicator must stay visually distinct from the four highlight fills and the native selection. Validate contrast in both themes and with Increase Contrast (AGENTS.md §11).
- `ChapterTextView.configure` gets a cheap path: when only `focus` changed, update the overlay and return before any document, highlight, or gutter work. The existing `#if DEBUG` counters (`documentBuildCount`, `highlightVerseUpdateCount`) make this testable: narrating a chapter must not increase them.

### 6.3 Scroll mode follow-along

- When `focus.revision` changes, the reader is in the foreground, and the reader shows `focus.chapterID`: if the word or verse rect is outside a comfort band (below the top chrome inset, above ~70% of the visible height above the bottom chrome), call `setContentOffset` to put the line at about 30%. Animate unless Reduce Motion is on.
- **Suspend following** while the scroll view `isTracking`, `isDragging`, or `isDecelerating`; while `selectedRange.length > 0` or the edit menu is visible; for about 5 s after the last user scroll; and while VoiceOver focus is inside the text. In those cases the mini player shows "Return to Narration", which resumes following and scrolls once.
- A follow scroll calls `capturePosition()` through the existing `scrollViewDidEndScrollingAnimation` path, so the reading anchor follows narration through the existing 400 ms-debounced `schedulePositionSave`. No new persistence path is needed in the foreground.
- At chapter end in the foreground, with "Continue to Next Chapter" on and following active: `ReaderState.followNarration(to:)` → `navigate(to:verseID:)` with no cue. With following suspended, the narration cursor advances and the reader stays where the user is.

### 6.4 Two Pages follow-along (SpreadChapterView)

- `Coordinator.followNarration(_ focus:)`, called from `update(_:)` when `focus.revision` changed:
  - `target = pagination(for: document).page(containing: focus.wordRange?.location ?? focus.verseRange.location)`.
  - If `target` is the displayed right page + 1, and `turnsAllowed`, `!curling`, `!turning`, no selection, and `!state.isNavigating`: call `turn(by: 1)`. It is animated unless Reduce Motion is on. Set `configuration.animated` from `accessibilityReduceMotion`.
  - Crossing into the next chapter uses the existing `key(after:)` → `commitTurn` path. Narration has already loaded the next chapter; prepared neighbors make it ready. If the neighbor isn't ready, `spread(1)` returns nil and the coordinator retries on the next focus update. It never forces pages.
  - If the target is behind or more than one spread ahead (the user flipped away), don't jump. Show "Return to Narration".
- Suppress `announcePage()` for narration-caused turns. VoiceOver users hear narration, and a page announcement would talk over it. Keep announcements for user-initiated turns.
- A selection stays within one page (owner-accepted in 0018). Auto-turning would clear it, so turns wait until the selection ends.

### 6.5 iPhone Duo postures

- **Book pose and flat spread:** same as Two Pages. The indicator and mini player stay clear of the active division region (`ReaderFoldLayout`). Never place the mini player across `fold.division`.
- **Tabletop:** add narration controls to `tabletopControls` below the division, next to Previous and Next Chapter. Reading above and controls below match the owner's Duo directive.
- **Outer display (compact):** same as compact 2a.
- **Fold or unfold while narrating** is a live resize. Narration keeps playing. `focus` is semantic (verse ID plus UTF-16), so it re-renders on the new layout. Pagination is rebuilt (`LayoutKey` change) and the first follow update moves to the right spread. Test this with Device Hub pose transitions (AGENTS.md Duo directive).

---

## 7. Chapter continuation and endpoints

- At the end of a chapter's last segment: if "Continue to Next Chapter" is on (default: on; owner-approved, Q2), load `source.adjacentChapterID(current, +1)` with `source.chapter(id)` and enqueue its segments. Prefetch the next chapter's document when the last 3 segments are queued, to avoid a gap.
- Order is catalog order across books (Malachi 4 → Matthew 1). The chapter announcement marks book changes ("Matthew, Chapter 1").
- **Revelation 22:** after the last segment, or the colophon if trailing blocks are spoken, status becomes `.finished(.endOfBible)`. Now Playing shows paused. It never wraps to Genesis. **Genesis 1:** "Previous Chapter" is disabled. "Previous Verse" at Genesis 1:1 restarts that verse.
- Single-chapter books (Obadiah, Philemon, 2 and 3 John, Jude) need no special playback handling. Their announcement is just the book name (Q6).
- A chapter that fails to load (`StorageIssue.incompatibleCorpus` or `.invalidPassage`) gives `.failed` with a local-content message. Never use placeholder speech (AGENTS.md §12).

---

## 8. UI

All controls use the system or Liquid Glass (`.glass` button style, `GlassEffectContainer`) and have 44-point minimum targets, accessibility labels, and identifiers for UI tests.

### 8.1 Entry points (no fifth toolbar icon)

0022 already flags the four trailing icons (Appearance, Summary, Save Chapter, More) as a risk on the narrowest iPhone at the largest non-accessibility size. Narration therefore **does not add a toolbar icon** in v1 (owner-approved, Q1):

1. **More menu → "Read Chapter Aloud"** (`play.circle` or `headphones`), in the chapter section with Previous and Next Chapter. Starts at the reading anchor's verse if it is on screen, otherwise at verse 1. It becomes "Stop Reading Aloud" while active.
2. **Selection edit menu → "Read Aloud from Here"** in `textView(_:editMenuForTextIn:…)`. Starts at `map.selection(for: range).start`. It does not change or clear the selection.
3. **VoiceOver custom action** on each verse element → "Read aloud from this verse" (in `prepareVerseAccessibility`), next to the existing "Highlight verse …" actions.
4. **Keyboard:** §8.4.
5. **Magic Tap** (two-finger double tap) toggles play/pause while narration is active or paused, through `.accessibilityAction(.magicTap)` on the root view.

### 8.2 Mini player

`NarrationMiniPlayer`: a glass capsule shown only while narration is preparing, playing, or paused. It has:

- play/pause
- previous and next verse
- the current reference ("John 3:16"); tapping it navigates the reader to the narrated verse and resumes following
- a Read Aloud menu: speed, sleep timer, voice and settings, stop

When the reader isn't showing the narrated chapter, the reference reads "Reading Aloud: Matthew 1". "Return to Narration" appears as an inline button when following is suspended.

| Layout | Placement |
| --- | --- |
| Compact 2a (iPhone, narrow iPad, Duo outer) | An extra top row inside `CompactReaderNavigation`'s `ReaderNavigationLayout`, above the passage capsule and tabs, on **all three destinations**, because audio continues across tabs. It collapses to an icon-and-reference pill when `navigationCollapsed` is set, like tab labels. Content insets grow automatically because the row is inside the bottom `safeAreaInset`, so final verses and chapter controls stay clear (AGENTS.md §3). |
| Regular iPad (top tab bar, 0017) | Bottom trailing, stacked above `PassageButton` inside the Read tab's existing `safeAreaInset`. Saved and Search get the same bottom-trailing inset while narration is active. `tabViewBottomAccessory` is **not** proposed: whether it suits a `.tabBarOnly` top tab bar is unverified, and the owner chose that bar deliberately. |
| Duo book or flat spread | Bottom trailing of the right page area, outside the division. |
| Duo tabletop | Inside `tabletopControls`, below the division. |
| Accessibility text sizes | Two rows: controls, then the full reference with no truncation. Icon buttons support Large Content Viewer (`.accessibilityShowsLargeContentViewer`). |

### 8.3 Settings (composing with Appearance)

Appearance (`AppearanceView`) controls how text looks, and the popover is already tall. Narration settings go in a **separate "Read Aloud" sheet** (`NarrationSettingsView`), opened from the mini player menu and from a "Read Aloud…" row at the bottom of Appearance, so they are discoverable without making Appearance longer.

- **Voice:** grouped by language (English only in v1, matching the UI and text) and quality ("Premium", "Enhanced", "Default", and "Personal Voice" if authorized). Each row has a short sample. The sample is the app-generated phrase "In the beginning God created the heaven and the earth." from Genesis 1:1, quoted verbatim. The default is the best installed `en` voice for the current locale. Guidance text: "Download higher-quality voices in Settings → Accessibility → Spoken Content → Voices." There is no public deep link to that screen (unverified; don't use private URLs).
- **Speed:** presets 0.75×, 1×, 1.25×, 1.5×, 2×, mapped multiplicatively around `AVSpeechUtteranceDefaultSpeechRate` and clamped to `AVSpeechUtterance{Minimum,Maximum}SpeechRate` (constants verified in the header; perceived mapping to be calibrated in S3). `rate` "will have no effect" once an utterance is enqueued (header), so a change restarts the current segment from the last reported word.
- **Toggles:** Announce Chapters (on), Announce Verse Numbers (off), Continue to Next Chapter (on), Follow Along (on), Use Pronunciation Hints (phase 5, on once the lexicon is reviewed).
- **Use VoiceOver voice settings:** when VoiceOver is running, sets `prefersAssistiveTechnologySettings`. Default off, so the chosen Read Aloud voice is used (owner-approved, Q8).
- **Sleep timer:** Off, End of Chapter, 15, 30, 45, 60 minutes. It runs on the injected clock. When it expires, narration pauses at the end of the current verse (or at a word boundary if a verse runs long) and shows `.paused(.sleepTimer)`. There's no fade, because the synthesizer volume is per utterance. A sleep timer is warranted: listening in bed is a common use, and without it background narration could continue for hours.

Storage is `NarrationPreferences` under `reader.narration.v1`, with a `version` field and decode-if-present defaults like `ReaderPreferences`. Store voice *identifiers* only. If a stored identifier is missing (voice deleted, Personal Voice revoked), fall back to the default voice and show a notice once. Don't overwrite the stored ID until the user picks another, so reinstalling the voice restores the choice.

### 8.4 Keyboard shortcuts (no collisions)

Existing shortcuts: ⌘1/2/3, ⌘F, ⌘⇧A, ⌘⇧Y, ⌘D, ⌘[ / ⌘], plus standard ⌘C and ⌘Z. Add a "Narration" section to `ReaderCommands`:

| Command | Shortcut | Enabled when |
| --- | --- | --- |
| Read Aloud / Pause | ⌘⇧L | A chapter is loaded. Works from any destination while active, because audio is global. Starting requires `acceptsReaderShortcuts`. |
| Previous Verse / Next Verse | ⌥⌘[ / ⌥⌘] | Narration is active. They never act as chapter turns, so they don't collide with ⌘[ / ⌘]. |
| Stop Reading Aloud | ⌥⌘. is **not** used | ⌘. is the system cancel shortcut. Stop goes in the menu without a shortcut. |

Check these against iPadOS system and Globe-key shortcuts and the Mac Catalyst/"Designed for iPad" key bindings (unverified). Space is not used, because it scrolls and activates focused controls.

---

## 9. Audio session, background, and system integration

### 9.1 Session configuration

- Category `.playback`, mode `.spokenAudio` (header: mode for "audio books"), no mixing options. A non-mixable playback session is what the system shows in Now Playing. `.spokenAudio` lets other spoken-audio apps that set `InterruptSpokenAudioAndMixWithOthers` pause narration instead of talking over it.
- Leave `AVSpeechSynthesizer.usesApplicationAudioSession` at its default (YES: "will use the AVAudioSession sharedInstance") so the synthesizer uses the configured session.
- Activate on play. Deactivate with `.notifyOthersOnDeactivation` on stop or finish (not on pause), so music the user paused can resume. On iOS 27 use `activate(options:completionHandler:)` and `deactivate(options:completionHandler:)` (new in 27, verified). On iOS 26 use `setActive(_:options:)`. Gate with `if #available(iOS 27, *)`, per the Duo directive to gate newer APIs and keep the 26.0 minimum.
- **Ring/Silent switch:** `.playback` plays even when the device is silenced. That is standard for user-started media and for this feature. Document it in the help text. Narration never starts by itself.

### 9.2 Interruptions (iOS 26 and 27 differ)

The iOS 27.1 SDK **deprecates** `AVAudioSession.interruptionNotification`, `InterruptionTypeKey`, `InterruptionOptionKey`, and `InterruptionReasonKey` in favor of `didBecomeInactiveNotification` (with `DeactivationContext`: `source`, `interruptionContext.reason`) and `resumptionRecommendationNotification` (with `ResumptionContext.recommendation`: `.shouldResume` / `.shouldNotResume`). The Swift overlay offers `AVAudioSession.DidBecomeInactiveMessage` and `ResumptionRecommendationMessage` as `NotificationCenter.MainActorMessage` (iOS 27+). `NarrationAudioSession` hides the difference:

- iOS 27+: observe the two messages on the main actor. Inactive with source `.system` → pause(.interruption). Resumption `.shouldResume` → resume only if the pause reason is still `.interruption`.
- iOS 26: observe `interruptionNotification`. `.began` → pause(.interruption). `.ended` with `.shouldResume` → resume under the same condition. This sits in an availability-gated branch, so the deprecation warning stays out of the iOS 27 path. AGENTS.md requires fixing introduced warnings: isolate it in one `@available(iOS, deprecated: 27)` helper, or confirm the warning doesn't appear when the call is reachable only under `#unavailable(iOS 27)`. Verify this at build time.
- Siri, phone and FaceTime calls, alarms, and other media apps: all go through the paths above. Navigation prompts (Maps) duck or interrupt spoken audio by system policy. Test each on a device.
- `mediaServicesWereResetNotification`: rebuild the synthesizer and session, keep the cursor, and show the paused state.

### 9.3 Route changes

- `routeChangeNotification` with `.oldDeviceUnavailable` (AirPods removed, Bluetooth or CarPlay disconnected, headphones unplugged) → pause(.routeLost). The header itself recommends pausing for this reason. Never auto-resume on reconnection.
- Optionally, on iOS 17+, `setPrefersInterruptionOnRouteDisconnect(true)` lets the system raise an interruption with reason `.routeDisconnected`. Pick one mechanism in S5 to avoid pausing twice.
- AirPods automatic ear detection and play/pause gestures go through remote commands (§9.5).
- CarPlay: narration plays over the CarPlay audio route. The Now Playing screen in CarPlay for an app without the CarPlay audio entitlement is unverified. CarPlay templates are a later phase (§14, phase 7; Q9).

### 9.4 Background, lock, and data protection

- Add `UIBackgroundModes = [audio]` to `Configuration/Info.plist`. This is the only plist change, and it covers the app target only. The `BibleWidgets` extension is unaffected.
- With the audio mode and an active session, synthesis continues when the app is backgrounded or the screen locks (to be confirmed on a device in S3: spoken-audio continuity with the screen locked for over 10 minutes).
- **Corpus while locked:** `BibleStore.chapter(_:)` reads `BibleCorpus.sqlite` from the app bundle through a read-only `DatabaseQueue`, plus the in-memory cache. Bundle resources are expected to be readable while locked, unlike the **complete**-protected user DB. Verify this by extending the Debug `LockProbe` to load a not-yet-cached chapter while locked (S3).
- **User DB while locked:** `ReaderState.navigate` calls `ensureAnnotations` (user DB) and fails with "Couldn't Load Chapter" while locked. So:
  - The narration cursor advances using **only** `source.chapter` (corpus). It never calls `navigate` in the background.
  - When the scene becomes active again, if following was active, `ReaderState.followNarration(to:)` moves the reader to the narrated verse. Annotation loading stays as today (once unlocked, the scene is active).
  - **Position persistence** goes through `ReaderState` so there is one writer of `reading_position`:
    - If `chapterID == reader.chapterID`, set `anchor` (the existing debounce and save).
    - Otherwise call a new `ReaderState.recordNarrationPosition(chapterID:anchor:)`. It saves the position, and if the device is locked it keeps only the newest pending value and saves it after `waitForProtectedData` returns, using the existing `retryPositionAfterUnlock` pattern. It never reports a lock failure as an error.
  - Write at verse boundaries, at most every ~5 s, and on pause, stop, and finish. Wrap these writes in a `BackgroundWriteLease` when backgrounded, as `flushPosition(protectInBackground:)` does.
- **Cold launch while locked** (a remote "play" or a Siri intent after the app was terminated) cannot open `BibleStore`. Its initializer opens the user DB, giving `ReaderOpenFailure.locked`. v1 behavior: remote commands return `.commandFailed` / `.noActionableNowPlayingItem` when no store is open, and intents require authentication (§9.6). A corpus-only store split, where `BibleStore` opens the corpus separately, is a possible later refactor. It is not in this plan's scope.

### 9.5 Now Playing and remote commands

- `MPNowPlayingInfoCenter.default().nowPlayingInfo`:
  - `MPMediaItemPropertyTitle` = "John 3" (catalog reference)
  - `MPMediaItemPropertyArtist` = edition label "KJV"
  - `MPMediaItemPropertyAlbumTitle` = "Bible"
  - `MPNowPlayingInfoPropertyMediaType` = `.audio`
  - `MPNowPlayingInfoPropertyPlaybackRate` 1 or 0
  - `MPNowPlayingInfoPropertyDefaultPlaybackRate` = 1
  - `MPNowPlayingInfoPropertyChapterNumber` / `ChapterCount` for the verse position within the chapter (optional; check the display in S5)
  - also set `playbackState`
  - No elapsed time or duration, since TTS has no reliable duration, and `changePlaybackPositionCommand` stays disabled. Optional artwork is the app icon rendered locally. The Lock Screen shows only the reference, never verse text (owner-approved, Q7).
- `MPRemoteCommandCenter`: enable `play`, `pause`, `togglePlayPause`, `nextTrack` (next chapter), `previousTrack` (restart the chapter if past verse 1, otherwise the previous chapter; never before Genesis 1), and optionally `changePlaybackRate` with the preset rates. Disable `skipForward`/`skipBackward`, since their intervals are seconds and there's no time base; `seekForward`/`seekBackward`; `changePlaybackPosition`; and like, dislike, bookmark, and rating. Saving a bookmark from the Lock Screen would create an annotation while locked and fail. Remove targets on stop. Add them once per controller lifetime.
- iOS 27 adds `MPNowPlayingInfoPropertyAppEntityIdentifiers`, tying Now Playing to App Intents entities. Consider it only with phase 6.

### 9.6 App Intents and Siri (optional, phase 6)

- `ListenToChapterIntent: AudioPlaybackIntent` ("Read John 3 aloud in Bible", "Listen to John 3 in Bible") with a `ChapterEntity` parameter resolved against the catalog, and `ContinueListeningIntent: AudioPlaybackIntent` (from the saved reading position), plus `AppShortcutsProvider` phrases. `AudioStartingIntent` is deprecated since iOS 17. Use `AudioPlaybackIntent` (verified in the AppIntents swiftinterface).
- Set `authenticationPolicy = .requiresAuthentication`, because the user store is locked otherwise (§9.4). Use `supportedModes` rather than the deprecated `openAppWhenRun` (deprecated in iOS 26, per the interface). Verify that a background mode can start audio without foregrounding.
- The widget extension already uses `AppIntentConfiguration`. Narration intents live in the app target, not `BibleWidgets`.
- No intents donate reading history (privacy).
- Owner wants this phase (Q10). Lock Screen Siri start needs a corpus-only store split; plan that as separate work before promising it.

---

## 10. Accessibility

- **VoiceOver coexistence:** narration and VoiceOver are separate speech streams. Starting narration never moves VoiceOver focus. Follow scrolling pauses while VoiceOver focus is in the reader text, and narration-caused page turns post no announcements (§6.4). The mini player has labeled buttons with `.updatesFrequently` only on the reference element, without per-word value changes, to avoid chatter. Magic Tap toggles playback.
- "Read aloud from this verse" custom actions on verse elements give non-visual users a precise start point without needing a selection.
- **Dynamic Type:** the mini player reflows to two rows at accessibility sizes. Large Content Viewer is supported. The Read Aloud sheet uses `Form` rows that scale.
- **Reduce Motion:** follow scrolling jumps without animation, auto page turns are not animated, and the indicator has no pulsing or animation.
- **Reduce Transparency and Increase Contrast:** system glass fallbacks. Add Increase Contrast variants to `NarrationVerse` and `NarrationWord`. Differentiate Without Color: the word underline still shows.
- **Keyboard:** §8.4. Every mini-player control is focusable (`.focusable`, standard buttons).
- **Hearing and Switch Control:** standard controls. Narration volume follows the system volume.
- Narration is an *additional* way to read and never replaces visible text or actions (AGENTS.md §11).

---

## 11. Privacy and App Store

- **No network:** `AVSpeechSynthesizer` with installed voices is on-device. Third-party voices from synthesis provider extensions (`AVSpeechSynthesisProviderAudioUnit`, `AVSpeechSynthesisProvider.h` in the SDK) appear in `speechVoices()`. Their privacy behavior is outside the app's control. **Proposal:** list only voices whose `identifier` starts with `com.apple.`, plus authorized Personal Voices (trait `.isPersonalVoice`), and exclude `.isNoveltyVoice`. Q5 asks whether to allow other installed voices with a disclosure. The identifier-prefix heuristic is unverified as a vendor test.
- **No logging:**
  - Don't log references, verse text, speech ranges, or voice choices.
  - Signposts (`ReaderPerformance.signposter`) use static names only, for example "Narration segment start". No content.
  - Error states carry codes, not content, as `LockProbe` does.
- **No audio persistence:** don't write synthesized buffers to disk. Don't use `writeUtterance`.
- **Now Playing shows the reference** on the Lock Screen, in Control Center, and on paired outputs (Watch Now Playing, CarPlay, AirPlay receivers). This is user-visible exposure of what the user is reading, so it is disclosed in the help text (owner-approved, Q7).
- **Personal Voice:** `AVSpeechSynthesizer.requestPersonalVoiceAuthorization` is requested only when the user taps "Use Personal Voice" in the voice picker, never at launch. Whether an Info.plist usage-description key is needed is unverified; check the current Apple docs and a device build.
- **Privacy manifest:** narration uses `UserDefaults` (already declared, `NSPrivacyAccessedAPICategoryUserDefaults`) and no new required-reason APIs as planned. Re-audit after implementation and update `PrivacyInfo.xcprivacy` only if a new category is used. Never invent reasons.
- **App Store:**
  - The `audio` background mode is used for audible, user-started narration, consistent with Guideline 2.5.4 (to be re-read at submission).
  - The privacy label stays "Data Not Collected". Re-verify with an offline network capture of narration flows (AGENTS.md §12).
  - Release notes and the App Store description must describe narration as synthesized speech using device voices, not a recorded audio Bible.
  - The UK storefront exclusion (0015) is unchanged.

---

## 12. Error and availability states

Use the `ChapterSummaryState.Status.unavailable(String)` pattern. Every message keeps reading available and never suggests deleting data.

| Condition | Detection | Behavior |
| --- | --- | --- |
| No English voice at all (unusual) | `NarrationVoiceCatalog` finds no `en*` voices | "Read Chapter Aloud" is disabled with the explanation "No English speech voice is installed. Add one in Settings → Accessibility → Spoken Content." |
| Only default-quality voices | Quality of the best voice is `.default` | Narration works. The Read Aloud sheet suggests enhanced or premium voices. No nagging prompt. |
| Chosen voice missing | `AVSpeechSynthesisVoice(identifier:)` returns nil, or `availableVoicesDidChangeNotification` (iOS 17+) | Fall back to the default voice and show a notice once. Keep the stored ID (§8.3). |
| Personal Voice denied, unsupported, or revoked | `personalVoiceAuthorizationStatus` | Hide or disable the row with an explanation. Fall back. |
| Ring/Silent switch on or volume 0 | Not detectable reliably and not needed for `.playback` | Help text only. Narration plays with the switch silenced. |
| Session activation fails (another app holds a non-mixable session, active call) | Activation error | `.failed("Narration couldn't start while another app is using audio. Try again.")`. Keep the cursor. |
| Interrupted / route lost | §9.2 and §9.3 | Paused state with reason. Play resumes. |
| Corpus chapter fails | Store error | `.failed` with a local-content message. Stop. No placeholder. |
| Locked at cold launch | `ReaderOpenFailure.locked` | Remote commands fail gracefully. Intents require unlock. |
| Position write while locked | Existing protected-data path | Retried after unlock. Not reported. |
| Synthesizer goes silent (no events for N s while "playing") | Watchdog on the clock | Restart the current segment once, then `.failed` with Retry. |

---

## 13. Testing strategy

Use Swift Testing for domain and controller logic, and XCTest/XCUITest for interactions (AGENTS.md §14). Never weaken existing tests.

### 13.1 Unit tests (new files in `BibleReaderTests/`)

- **`NarrationScriptTests.swift`**
  - **Full-corpus fidelity:** open the bundled corpus through `BibleStore` (as `StorageTests` and `SpreadPaginationIntegrityTests` already do). For all 1,189 chapters, check that every verse segment's speech equals `verse.text` minus only allow-listed omissions, and that the attributed `.string` equals the speech string.
  - **Map agreement:** segment `displayRange`s equal `ChapterTextMap` entry and heading ranges, in order.
  - **Fixtures:**
    - Genesis 1 (pilcrows)
    - Psalm 3 (superscription)
    - Psalm 119 (acrostic headings, 176 verses)
    - Romans 16 (colophon)
    - John 3
    - Jude (single chapter)
    - Revelation 22 (last chapter)
    - synthetic bridge `3-4` and a non-integer label
    - grapheme edge cases (`æ`, `’`, a combining mark in a synthetic document)
  - **Offset mapping:** spoken→display across an omitted `¶`, at range ends, empty ranges, and out-of-bounds clamping.
  - **Options:** verse and chapter announcements are separate segments with nil `displayRange`. Italics have no effect on speech.
- **`NarrationControllerTests.swift`** with `FakeSpeechSynthesizer` (scripted `started` / `willSpeak` / `finished` events, controllable timing), `FakeNarrationAudioSession`, `FakeNowPlaying`, and a test clock:
  - Focus maps to the expected verse ID and UTF-16 range for scripted word ranges, including a voice that reports no ranges.
  - Stale generation events after stop, seek, or rate change are ignored.
  - Rate change restarts from the last word.
  - Continuation from chapter end to the next chapter's announcement. Malachi 4 → Matthew 1 crosses books. Revelation 22 → `.finished(.endOfBible)`, no wrap. Genesis 1:1 previous verse stays.
  - Interruption begin/end with and without should-resume. A user pause is not overridden by a resume recommendation.
  - Route lost pauses and does not auto-resume.
  - Sleep timer: End of Chapter, and N minutes stops at a verse boundary.
  - Position writes are debounced, written at pause and stop, and routed for a non-displayed chapter.
  - A locked-store write failure is retried, not surfaced (reuse the `ReaderState.waitForProtectedData` test pattern).
  - Remote commands: next and previous track semantics, disabled commands report as disabled.
  - Missing voice → fallback with the stored ID preserved. `NarrationPreferences` decodes older and missing payloads.
- **`NarrationFollowAlongTests.swift`**
  - The page index for a focus offset uses `ChapterPagination.page(containing:)`. Turn decisions: next spread → turn; behind or far → no jump; selection active → wait.
  - Renderer cost: a `ChapterTextView` driven through a full chapter of focus updates leaves `documentBuildCount` and `highlightVerseUpdateCount` unchanged, keeps `selectedRange` intact, and copy output stays identical.

### 13.2 UI tests (`BibleReaderUITests/`)

Add a Debug-only launch environment `BIBLE_TEST_FAKE_SPEECH=1`, alongside the existing `BIBLE_TEST_STORE` and `BIBLE_TEST_CHAPTER`. It injects a deterministic fake synthesizer so tests don't depend on Simulator audio:

- **Start narration from More:** the mini player appears, play/pause/stop work, and the reference updates.
- **"Read Aloud from Here":** from a selection in John 3. The selection remains and a highlight saved during narration persists.
- **Follow-along:** scrolling in Scroll mode. Two Pages auto-turn on an iPad simulator and across a chapter boundary.
- **Large text:** largest accessibility size, two-row mini player, all destinations reachable.
- **Keyboard:** ⌘⇧L and ⌥⌘[ / ⌥⌘] where hardware keyboard simulation allows.
- **Persistence:** relaunch restores the narrated verse as the reading position.
- **Duo (Device Hub):** fold and unfold while narrating, book-pose auto-turn, tabletop controls.

### 13.3 Manual device matrix (required before release; record results in `Docs/Validation/narration/README.md`)

Devices: smallest supported iPhone, a Pro Max, an iPad, iPhone Duo (Device Hub, then physical), on iOS 26.x and 27.x. Record the Xcode build and SDK (27.1), runtime, and device, per the Duo directive.

| Area | Checks |
| --- | --- |
| Voices | Default, enhanced, premium, Personal Voice. Word-range granularity per class. `¶`, `LORD`, `æ`, Hebrew letter. IPA entries (phase 5). |
| Background | Screen locked for 30+ min. Chapter rollover while locked (corpus while locked). Position saved after unlock. |
| Controls | Lock Screen, Control Center, Dynamic Island / Live Activity system media UI, AirPods squeeze/tap, Apple Watch Now Playing. |
| Interruptions | Phone and FaceTime call, Siri, alarm and timer, Maps navigation prompt, another music app starting, a podcast app (spoken-audio policy). |
| Routes | AirPods in and out, Bluetooth speaker, wired, CarPlay connect and disconnect, AirPlay. |
| Modes | Ring/Silent switch, Low Power Mode, Focus modes, airplane mode on first launch. |
| Accessibility | VoiceOver on (focus, Magic Tap, custom actions), largest text, Reduce Motion, Increase Contrast, keyboard (iPad Magic Keyboard). |
| Layouts | Compact 2a, iPad top tab bar, Split View resize during narration, Duo all postures. |
| Performance | Psalm 119 narration with follow-along. No dropped frames while scrolling. Verse-boundary gaps measured per voice. |
| Privacy | Network capture during all narration flows: no app-originated requests. |

The Simulator can play AVSpeech audio but is not evidence of background, lock, route, or interruption behavior. AGENTS.md says to report unavailable tooling explicitly.

---

## 14. Phased delivery

Each phase ends with a successful build, no new warnings, the relevant tests passing, and a validation entry. Don't claim later-phase behavior from earlier evidence.

### Phase 0: Owner decision and API spike (isolated, Debug-only, not merged into the reader)

- ~~File the 0023 decision, update the AGENTS.md scope, and answer the §16 questions.~~ Done 31 October 2026.
- Spikes, recorded in `Docs/Validation/narration-spike/README.md`:
  - **S1 voice behavior:** `¶`, `LORD`, `æ`, Hebrew letter. `willSpeakRange` granularity per voice class. Delegate callback thread.
  - **S2 IPA:** attribute honored per voice. Range reporting inside IPA ranges.
  - **S3 background:** locked-screen continuity, corpus readable while locked (LockProbe extension), rate mapping, verse-gap latency per queue depth.
  - **S4 TextKit 2 rendering attributes** in `UITextView`: supported keys, survival across `attributedText` replacement, interaction with selection drawing.
  - **S5 session and Now Playing:** iOS 26 vs 27 interruption paths, route disconnect strategy, Now Playing fields shown.
- **Acceptance:** written results for S1–S5 with device and OS. A go/no-go on the rendering approach and the omission allow-list.

### Phase 1: Narration script (domain only)

- `NarrationScript`, options, and the label formatter, plus `NarrationScriptTests`.
- **Acceptance:** the full-corpus fidelity test passes. Range agreement with `ChapterTextMap` passes. No app UI change.

### Phase 2: Foreground playback

- `SpeechSynthesizing` + `SystemSpeechSynthesizer`, `NarrationController` (foreground), `NarrationPreferences`, `NarrationVoiceCatalog`, the More menu item, the mini player (all layouts), the Read Aloud sheet, ⌘⇧L, Magic Tap, chapter continuation and endpoints, and the `BIBLE_TEST_FAKE_SPEECH` hook.
- **Acceptance:**
  - Controller unit tests pass.
  - UI tests for start, pause, and stop pass on an iPhone and an iPad simulator.
  - Genesis 1 → Genesis 2 continuation works. Revelation 22 stops.
  - Existing iPhone and iPad regression suites pass.
  - Narration doesn't change `documentBuildCount`.

### Phase 3: Follow-along

- The renderer indicator (rendering attributes or overlay), Scroll follow with suspension rules, Two Pages auto-turn, Duo placements, "Read Aloud from Here", and the VoiceOver "Read aloud from this verse" action.
- **Acceptance:**
  - Follow-along tests pass.
  - Selection, highlights, and copy are unchanged during narration (tests).
  - Two Pages crosses a chapter boundary in the iPad UI test.
  - Duo Device Hub pose checks for book and tabletop pass.
  - Reduce Motion paths are verified.

### Phase 4: Background and system integration

- `UIBackgroundModes` audio, `NarrationAudioSession` (iOS 26 and 27), interruptions, routes, Now Playing and remote commands, position persistence through `ReaderState` (locked-safe), sleep timer, and lifecycle flushes.
- **Acceptance:**
  - Unit tests for interruption, route, timer, and persistence pass.
  - Device matrix rows for Background, Controls, Interruptions, and Routes are recorded on at least one iPhone running iOS 26 and one running iOS 27.
  - Network capture is clean.

### Phase 5: Voices and pronunciation

- Personal Voice authorization flow, the voice filter (Apple voices plus authorized Personal Voice only, Q5), and the owner-reviewed lexicon with IPA attributes.
- **Acceptance:** each lexicon entry has a reviewer and was heard on the listed voices. The fidelity test still passes, since the attributed string equals the speech string.

### Phase 6: App Intents and Siri (owner-requested, after v1 playback)

- `ListenToChapterIntent` and `ContinueListeningIntent` (`AudioPlaybackIntent`), and App Shortcuts.
- **Acceptance:** they work from Siri and Shortcuts on a device while unlocked. They decline gracefully while locked. No history donation.

### Phase 7: CarPlay audio app (owner-requested, after v1 playback)

- Owner action first: request the CarPlay audio entitlement from Apple. Don't start template work until it is granted.
- `CPTemplateApplicationSceneDelegate` with a list template for books/chapters and the system Now Playing template, driven by the same `NarrationController`.
- **Acceptance:** CarPlay Simulator and a real head unit or CarPlay-capable car; connect and disconnect while reading aloud; Now Playing controls; no verse text on screen.

### Phase 8: Release hardening

- Full accessibility matrix, performance on the slowest supported device, privacy manifest re-audit, App Store copy, and README, HANDOFF, and AGENTS.md updates.
- **Acceptance:** every §13.3 row is recorded or explicitly marked untested with a reason.

---

## 15. Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Voices report coarse or no word ranges (some premium or Personal Voices) | Word highlight is missing | Verse-level indicator is always available. Never time-interpolate. |
| `¶` or Hebrew letters spoken aloud, or `LORD` spelled out | Distracting, sounds wrong | Speech-only allow-list (owner approval), a lexicon entry for `LORD` if needed, S1 evidence. |
| IPA attribute ignored by premium voices | Names mispronounced | Phase 5 is optional. Hints are per-voice verified. Default pronunciation is the fallback. |
| Gaps between per-verse utterances | Choppy listening | Queue depth 2–3, prefetching. If gaps are unacceptable, paragraph-level utterances with a multi-verse offset map (the design supports it; the segment becomes the paragraph). |
| Rendering attributes unsupported in `UITextView` TextKit 2 | Highlight work changes `textStorage` | Overlay-layer fallback. Never fall back to `layoutManager` (TextKit 1 switch). |
| Delegate thread undocumented | Data races | Nonisolated delegate → `AsyncStream` → main actor. Sendable payloads only. |
| iOS 27 interruption API deprecations | Warnings, behavior drift | Availability-split adapter. Test on both OS versions. |
| User DB locked during background rollover | Navigation errors | Corpus-only cursor, deferred reader sync, locked-safe position retries. |
| Five-icon toolbar pressure | Clipping on small phones | No new toolbar icon. More menu, mini player, keyboard, Magic Tap. |
| Lock Screen shows what the user is reading | Privacy perception | Reference only, disclosed, Q7. |
| Battery drain from long background sessions | User complaint | Sleep timer, End of Chapter option, no wake locks beyond the audio session. |
| App Review on background audio | Rejection | Audio plays only while audible narration is active. Deactivate the session on stop. |

---

## 16. Owner decisions (answered 31 October 2026)

All questions are resolved; [0023](../Decisions/0023-narration.md) records them.

| # | Question | Decision |
| --- | --- | --- |
| 1 | Entry point | More menu + selection menu + VoiceOver action + ⌘⇧L + Magic Tap, with the mini player. No toolbar icon. |
| 2 | Continuation default | Continue to the next chapter by default. Users can turn it off. Never wrap. |
| 3 | Colophons | Speak the 14 trailing colophons. |
| 4 | Psalm 119 Hebrew letters | Omit the Hebrew glyph from speech. Speak the transliteration ("ALEPH."). |
| 5 | Voice policy | On-device Apple voices plus authorized Personal Voice only. No third-party provider voices. |
| 6 | Announcements | Natural titles: "John, Chapter 3"; "Psalm 23"; book name alone for single-chapter books. |
| 7 | Lock Screen detail | Show the chapter reference and edition ("John 3 · KJV"), never verse text. Disclose in help text. |
| 8 | VoiceOver users | Use the Read Aloud voice by default, with a toggle for VoiceOver voice settings. |
| 9 | CarPlay | Wanted later (phase 7). The owner must request the CarPlay audio entitlement first. |
| 10 | Siri and App Intents | Wanted (phase 6). Unlock is required at first. Lock Screen start needs a corpus-only store split, planned separately. |
| 11 | Lexicon review | The owner approves each entry by listening on device. No external reference is required. |
| 12 | Naming | "Read Aloud" ("Read Chapter Aloud", "Read Aloud from Here", "Stop Reading Aloud"). |

---

## 17. Verification notes

### Verified against the installed SDK (Xcode at `/Applications/Xcode.app`, iPhoneOS **27.1** SDK)

- `AVFAudio/AVSpeechSynthesis.h`:
  - `AVSpeechSynthesizer` (`speak`, `pauseSpeaking(at:)`, `continueSpeaking`, `stopSpeaking(at:)`, `usesApplicationAudioSession`, `outputChannels`)
  - delegate `willSpeakRangeOfSpeechString` (iOS 7), `willSpeakMarker` (iOS 17)
  - `AVSpeechSynthesisIPANotationAttribute` (iOS 10) and its header comment
  - `AVSpeechUtterance(attributedString:)`, `rate` (pinned to min/max; no effect after enqueue), `prefersAssistiveTechnologySettings` (iOS 14), `preUtteranceDelay`/`postUtteranceDelay`
  - SSML init (iOS 16; prosody properties ignored)
  - `AVSpeechSynthesisVoiceQuality.premium` (iOS 16)
  - Personal Voice authorization API and `.isPersonalVoice`/`.isNoveltyVoice` traits (iOS 17)
  - `availableVoicesDidChangeNotification` (iOS 17)
  - `NS_SWIFT_SENDABLE` only on `AVSpeechSynthesisVoice` and the marker types, not on the synthesizer or utterance
- `AVFAudio/AVAudioSession*.h` and the Swift overlay:
  - `.playback`, `.spokenAudio`
  - `interruptionNotification` and its keys deprecated in iOS 27 in favor of `didBecomeInactiveNotification`/`DeactivationContext` and `resumptionRecommendationNotification`/`ResumptionContext` (iOS 27), with `MainActorMessage` wrappers
  - `activate(options:completionHandler:)` and `deactivate(options:completionHandler:)` (iOS 27)
  - `setPrefersInterruptionOnRouteDisconnect` (iOS 17), interruption reason `.routeDisconnected`
  - route-change reason `.oldDeviceUnavailable`
- `MediaPlayer`:
  - `MPNowPlayingInfoCenter.playbackState` (iOS 13)
  - the Now Playing property keys used above
  - `MPNowPlayingInfoPropertyAppEntityIdentifiers` (iOS 27)
  - `MPRemoteCommandCenter` commands listed in §9.5
- `UIKit/NSTextLayoutManager.h`: `addRenderingAttribute`, `removeRenderingAttribute`, `setRenderingAttributes`, `invalidateRenderingAttributes(for:)`.
- `AppIntents` swiftinterface: `AudioPlaybackIntent` (iOS 17), `AudioStartingIntent` deprecated, `supportedModes` replacing the deprecated `openAppWhenRun` (iOS 26), `authenticationPolicy` `.requiresAuthentication`.

### Not verified (needs a spike, a device, or current documentation)

- The thread `AVSpeechSynthesizerDelegate` callbacks arrive on.
- Word-range granularity per voice class, and inside IPA-attributed ranges.
- Whether premium voices and Personal Voice honor IPA.
- How voices speak `¶`, `LORD`, `æ`, and Hebrew letters.
- Which TextKit 2 rendering-attribute keys `UITextView` draws, and whether they persist across text replacement.
- Bundle corpus readability while the device is locked (expected, but test it with LockProbe).
- Background synthesis continuity over long locked sessions.
- Whether a Personal Voice Info.plist usage key is required.
- Whether `tabViewBottomAccessory` suits a `.tabBarOnly` top tab bar.
- CarPlay Now Playing behavior without the entitlement.
- System and Globe-key shortcut conflicts for ⌘⇧L and ⌥⌘[ / ⌥⌘].
- A public deep link to Spoken Content voice settings (assume none).
- Whether the `com.apple.` identifier prefix reliably identifies Apple voices.
- The deprecation-warning behavior of the iOS 26 interruption branch when built with the 27.1 SDK.
- App Review interpretation at submission time.
