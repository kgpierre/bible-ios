# Summary refusals, source notes, large libraries, and search paging — 26 September 2026

The owner asked to debug Apple Intelligence summary refusals, test locked-device behavior, and implement footnotes and the large-Saved-library fix. They also asked for the rest of the open engineering work except iPad, and for Saved's Show and Sort controls to become buttons. Release identity and rights are in [0015](0015-release-identity-and-scripture-rights.md).

## 1. Summary refusals: found and fixed

**Method.** `SummaryRefusalProbeTests` runs the real on-device model; it is disabled unless `BIBLE_MODEL_PROBE` is set (`TEST_RUNNER_BIBLE_MODEL_PROBE=1` with xcodebuild). It runs the production `ChapterSummarizer` over 20 chapters, chosen to include violence, sexual content, and genocide alongside ordinary chapters. `SummaryDiagnostics`, which is Debug-only and records static stage names with no text, reports which stage failed.

**Finding.** Before the fix, **12 of 20** summaries failed on the iOS 27 simulator (iPhone 18 Pro, host Apple Intelligence model). The failing chapters were Genesis 19, Leviticus 18, Numbers 31, Joshua 6, Judges 19, 2 Samuel 11 and 13, Esther 9, Psalm 137, Ezekiel 16 and 23, and Matthew 27. **Every failure came from the post-generation refusal check, not from writing the summary.** Generation uses `permissiveContentTransformations` and succeeded every time. The check was a second guided-generation session asking "is this a refusal?" Apple's permissive guardrails apply only to plain-string responses, so that session ran with *default* guardrails over the summary text itself. It either raised a guardrail violation (4 chapters) or refused (8 chapters). Either way the app reported "Apple Intelligence declined this summary" for a summary that had been written.

**Fix.** The model-based check is replaced by `SummaryRefusal.looksLikeRefusal`, which checks only the opening of the output for refusal phrasing ("I'm sorry…", "I can't…", "As an AI…"). Checking the opening only means an overview that says someone in the chapter "cannot" or "refuses" is not rejected. This also removes one model call per summary. Guardrail and refusal *errors* from generation are still reported as declined.

**After.** 20 of 20 chapters produced overviews. All 12 former failures succeeded, and there were no diagnostic events. Unit tests cover refusal and overview wording.

**Questions.** A five-question probe on difficult chapters (Genesis 19, Judges 19, Matthew 27, 2 Samuel 11, John 3) answered four. Judges 19 was rejected by the answer-support review as insufficiently supported; that is the designed quality gate, not a guardrail false-positive. The scope and review checks are prompt-injection defenses and are unchanged.

**Limits.** These are simulator results using the Mac's model. Device model versions can behave differently; run the probe on the iPhone with the same flag. Overviews often exceed the instructed 120 words (77–240 observed). They are not truncated, because truncation would cut sentences. Real refusals remain possible and are still shown as refusals.

## 2. Source notes (footnotes)

The corpus carries **6,959** marginal notes from the source edition, all in the form `c.v catchphrase: text`. Examples are "Heb. between the light…" and "or, from above". Every note parses; an unexpected shape would be shown whole.

- **Marker.** A 5-point accent dot beside the verse number marks verses with notes. Tapping the number opens that verse's notes in a sheet, with medium and large detents. The tap target is 44 points tall and stays in the gutter, so it never overlaps selectable text.
- **Whole chapter.** More → **Chapter notes** lists every note in the chapter by verse, for keyboard, Voice Control, and discoverability. It is disabled when the chapter has none; John 3, for example, has none.
- **VoiceOver.** A verse with notes adds "Has source notes" to its value and a **Show notes** action.
- **Setting.** Appearance → **Show source notes**, on by default, hides the markers. Stored preferences saved before this field existed decode with their other values intact.
- **Separation from Scripture.** Notes are not in the text storage. They are excluded from selection, copy, share, search, annotations, and anchors, and tests assert that copy excludes them. The sheet labels them as marginal notes from the source edition that are not part of the verse text.
- **Not rendered.** The Pauline subscriptions at the end of some epistles (for example "Written to the Romans from Corinthus…") were already rendered as trailing source blocks and are unchanged.

## 3. Large Saved libraries

The audit (0013 performance README, finding 2) measured every annotation being decoded at launch and Saved being resolved on the store's serial queue. That was 54–114 ms and 98–283 ms at 10,000 records, blocking chapter loads and position saves.

- **Additive migration `v3_exact_chapter_index`.** It adds `chapterID` and `highlighted` columns to `exact_annotation`, backfilled from the unchanged JSON payloads, with an `(editionID, chapterID)` index. v1 and v2 tables and records are kept. A store with an unknown migration still fails without resetting.
- **Backup before migrating.** An existing store is first copied with SQLite's online backup API to `ReaderData/User-before-migration.sqlite`, which is consistent even with a pending journal. The copy has Complete protection and is excluded from device backup, because the live store is already backed up. One copy is kept and replaced by the next migration. If free space is below twice the store size plus 1 MB, the migration stops with `insufficientSpace` before touching anything.
- **Reader.** The reader decodes only the open chapter, its neighbors when a page turn prepares them, and recently read chapters, capped at 24 and then pruned to current ±1. The chapter picker's highlight rings come from a `SELECT DISTINCT chapterID … highlighted=1` index query, not from decoding. A Saved deletion in an unloaded chapter refreshes that index instead of guessing.
- **Saved.** Raw rows are read on the store queue. Decoding and verse resolution run in a `@concurrent` function on a dedicated read-only corpus connection, so a chapter load is no longer queued behind a big Saved rebuild. Incremental rebuilds track a generation per chapter: a chapter edited while a rebuild is in flight stays dirty. If another connection invalidates the cache mid-rebuild, a full rebuild runs.
- **Saved controls (owner request).** Show is now a one-tap segmented control (All, Highlights, Bookmarks). Sort is an icon button (↑↓) whose accessibility label and value give the current order. At accessibility text sizes both fall back to full-width menus, because segments would truncate. This layout is for the owner's review.

Measured results are in section 7.

## 4. Search paging

Deep pages re-scored and re-sorted every match (`ORDER BY bm25 … OFFSET`); the audit measured 68–126 ms at offset 10,000. The store now ranks a query's matches **once**, keeping the ordinals of up to all 31,102 verses, about 250 KB. That list also gives the total, so the count query is gone. Each later page fetches its 50 rows by rowid with `snippet()`. On the host this took offset 10,000 from 47.6 ms to 0.2 ms; the first page cost rises from 7.9 to 10.3 ms for "the". Results are identical: a test compares pages 0, 50, 1,000, and 10,000 with the original `ORDER BY bm25, ordinal LIMIT/OFFSET` query. The corpus is immutable, so the cached ranking never goes stale. A new query replaces it.

## 5. Session Undo cap

Session Undo keeps at most **100** changes, and the scene's `UndoManager` has the same limit. Earlier changes remain saved; only the ability to undo them expires.

## 6. Locked-device test

The Debug-only `LockProbe` and its procedure are in [Validation/locked-device](../Validation/locked-device/README.md). It needs the owner's physical iPhone, because simulators do not enforce data protection. **Passed on 27 September 2026** on an iPhone 17 Pro Max: the pre-lock save succeeded, the locked attempt failed with SQLITE_IOERR without damage, and reads and writes resumed after unlock with the integrity check ok.

The verse-notes sheet originally used a fixed half-screen detent, which left empty space below a short note (owner report). It now measures its content plus the navigation bar and opens at that height, with Large available. `testVerseNoteSheetFitsShortNote` covers it.

## 7. Validation

- **Unit tests.** New or changed tests cover: the v2→v3 migration with the protected backup; per-chapter decoding (an edit decodes only the touched chapter's record); the reader relaunch index; note parsing and copy exclusion; gutter-only markers and their toggle; decoding of older preferences; refusal wording; and deep-page equality.
- **Existing tests.** Tests that inserted rows in the v2 shape now include the v3 columns. The relaunch test now checks persisted records and the highlight index instead of assuming the reader loads the whole library.
- **Real-model probe.** Section 1.
- **Corpus rebuild.** 9 of 9 validation checks pass, and the database bytes are identical.

Suite results and performance numbers are recorded in the README entry for 26 September 2026.
