# 0003 — Offline corpus and local persistence

21 September 2026. Implemented engineering baseline; release gates remain open.

## Corpus

The existing archive pin remains unchanged: `6d834ebe8bcf157587ce93b774615d9e9554f1201951a072cc379930d49bb6fb`. `Content/Tools/build_corpus.py` uses an explicit 66-book allowlist and records excluded source books. This is the proposed canon, not new owner approval. The source notice dates its input files to 17 September 2026. The earlier four chapter fixtures remain regression references.

The corpus contains 66 books, 1,189 chapters, and 31,102 verses. Counts are pinned per chapter in `Content/Source/edition-counts.json`. Every verse is compared with an independent XML extraction; notes/headings never enter verse text or FTS. Source superscriptions and trailing source headings are retained separately and displayed in the reader. Their transient selection boundaries are mapped alongside stable verse anchors. Full note presentation and all source paragraph/poetry styling remain further renderer work.

The SQLite schema and chapter document format are version 1. Stable identities use `eng-kjv-1769-protestant:BOOK:chapter:verse`; logical revision and binary hashes are separate. Imported aliases currently include source names, short names, and codes. They are infrastructure, not a complete reference parser. FTS5 is built offline and tested against system SQLite in Simulator; runtime never rebuilds it.

Acquisition, conversion, and validation are separate commands. Output uses sorted insertion order, deterministic JSON, and a closed rollback-journal database without WAL dependencies. The manifest includes provenance, configuration/importer hashes, source date, counts, exclusions, and unresolved rights review. `EditionNotice.txt` includes the provider's original notice paragraphs; it does not claim mobile/territory clearance.

## Database ownership and preservation

GRDB 7.11.1 (MIT) is pinned by version and revision. The maintainer's license is bundled. `BibleStore` is an actor with separate read-only corpus and writable user queues; views receive domain values, never SQL/connections. Store opening runs outside the main actor. Only the active chapter is kept in reader memory; the navigation catalog contains metadata only. Saved resolves grouped passages in batches.

`v1_local_reader` is the first GRDB migration. It creates highlights, exact-range bookmarks, and encoded semantic reading position; `grdb_migrations` is the version history. There is no destructive reset path. Unknown future migrations and unreadable databases fail while preserving the existing file. No prior prototype user database existed. Before adding a future risky migration, add a consistent protected backup/free-space/retention policy and migration fixtures; copying a live WAL main file is not sufficient.

The user directory and database/sidecars use complete file protection. Locked data is treated as an opening/write error, not an empty store. Actual locked-device behavior requires physical-device verification. User data stays eligible for OS backup; no app-operated sync is added.

## Transactions, navigation, and UI

Whole-verse range edits use one transaction and bound values. Bookmarks have exact-range uniqueness; overlapping ranges remain independent. Highlight operation IDs preserve contiguous grouping; recoloring a subset splits displayed groups. Bookmark-only edits preserve mixed existing highlights. UI refreshes after the write succeeds; failures retain the editor and show an error. Session Undo compares affected records with its expected after-state before restoring prior values, preventing stale operations from overwriting later edits.

Reading anchors debounce for 400 ms and flush at scene transitions/navigation. First install opens Genesis 1. Unavailable saved chapters retain their stored reference until explicit navigation; valid revised verse offsets are clamped by the renderer. No first-run download is involved. UI tests use separate UUID-named test stores and never reset the real user database.

The chapter picker now opens the current book, offers canonical Old/New Testament book lists, and uses actual chapter counts. More contains previous/next chapter (no Bible-boundary wrap) and Undo. Saved shows durable, grouped highlight passages and range bookmarks; wide selection remains visible beside the reader. Search/filter/delete refinements remain separate feature work.

Testing exposed that clear space inside unselected compact navigation buttons was not tappable on iPad. Explicit content shapes now cover their entire layout bounds. Tests also distinguish native switch hit regions and wait for durable state rather than treating the preexisting reader behind a sheet as evidence of saving.

## Verification and remaining gates

`Content/Reports/Validation.json` records the eight passing offline checks, toolchain versions, and corpus hashes. Storage tests cover complete catalog/packaged FTS, reopening position/annotations, exact bookmark uniqueness, recolor grouping, atomic rollback after an injected second-verse failure, stale Undo, mixed-highlight bookmark edits, future migrations, and corruption preservation. Native tests cover selection, annotation menus, chapter/theme navigation, relaunch, and iPad wide/narrow restoration.

The iPhone package-product issue was resolved by resolving the pinned dependency in Xcode's standard cache. An unsigned generic iOS build succeeded; this does not verify signing or installation on the owner's phone.

Physical-device performance, lock/unlock protection, airplane-mode/network-capture acceptance, complete VoiceOver/Dynamic Type/keyboard checks, appearance persistence, final source/territory review, and distribution remain open. Search UI/reference grammar and richer Saved controls are the next feature work. No account, tracker, runtime network service, or publishing action was added.

### Recorded results

- Eight content tests pass; Python 3.13.3 / SQLite 3.49.1. The report's packaged binary and logical checksums match the Release corpus.
- `.build/Content-iPhone-final.xcresult`: 13 Swift Testing cases pass; six applicable UI cases pass (the iPad-only case skips).
- `.build/Content-iPad-final.xcresult`: 13 Swift Testing cases plus durable annotation relaunch pass. Wide/narrow restoration, cross-verse selection, native annotation menu, and chapter/theme round trip passed in `.build/Content-iPad-1.xcresult`; its earlier Saved-tap failure is resolved by the final relaunch run.
- `.build/Content-first-launch.xcresult`: an isolated fresh store opens Genesis 1; choosing Genesis 2, backgrounding, terminating, and relaunching restores Genesis 2.
- Debug simulator and unsigned Release iPhone builds succeed. Release inspection finds the full corpus, manifest, edition notice, and GRDB license; excludes `PrototypeChapters.json`; has no corpus WAL/SHM dependency; passes integrity check with 31,102 verses.
- Inspected fresh-reader, durable Saved, and wide-iPad screenshots. Using full-screen captures fixes the previous application-frame rotation/cropping artifact. All six original design assets still match their manifest hashes.
