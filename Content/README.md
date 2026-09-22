# Offline content pipeline

Use Python **3.13.3** (standard library only; SQLite FTS5 required). App builds read committed local resources. They never invoke these tools or download Scripture.

```sh
python3 Content/Tools/acquire_source.py
python3 Content/Tools/build_corpus.py
python3 Content/Tools/validate_corpus.py
```

Acquisition is explicit and separate. An existing matching archive is reused. If the provider replaces the remote ZIP, acquisition fails rather than accepting new text. Review any source/pin change manually.

The 66-book configuration is an engineering default pending owner confirmation. `Source/edition-counts.json` is the source-derived, pinned chapter/verse inventory, not a universal verse-count rule or evidence of owner approval. The source archive includes additional books and a preface; `CorpusManifest.json` lists exclusions. No first-N-books filtering is used.

The importer rejects unsafe archive entries, entities/DTDs, unknown markers, unexpected verse labels, duplicates, and empty text. It collapses XML formatting whitespace; preserves verse wording and added-word italics; retains source headings, superscriptions, footnotes, and initial paragraph/poetry styles separately. Source heading XML preserves their inline markup. Lexical IDs and full paragraph segmentation remain available in the unchanged raw source. The reader currently renders heading text, but not footnote popovers or every source typography detail.

Outputs in `BibleReader/Resources/`: read-only `BibleCorpus.sqlite`, `CorpusManifest.json`, and plain-text `EditionNotice.txt`. The manifest records source/configuration/importer/output hashes, logical revision, counts, exclusions, and outstanding rights review. The database contains chapter documents, stable verse identities, canonical order, aliases, and an FTS5 index. There are no packaged WAL/SHM dependencies.

`Reports/Validation.json` records the most recent local validation result and hashes. Tests independently reconstruct **every verse** from the pinned XML and compare it with the database; check golden chapters and the earlier four fixtures; validate integrity, counts, first/last-book searches, invalid XML/markers, and reproducible logical/binary output. Run and review these before replacing shipping resources. A binary checksum is specific to the tested SQLite toolchain; the logical checksum is portable.

The original provider notice is preserved in `Source/copr.htm`, and its paragraph text is bundled for About. The archive notice identifies source files dated 17 September 2026. The website listing can have a different update date; the pinned archive is authoritative for this build. Edition/territory rights and canon approval remain release gates; no distribution approval is claimed.
