# Reader performance follow-up

22 September 2026. Owner requested implementation of the second code audit, prioritizing annotation responsiveness, repeated rendering work, and navigation/cache overhead before device-dependent search/storage changes.

## Implemented

- Exact annotations decode once into an actor-owned chapter dictionary. Ordinary writes use only the touched chapter, and legacy snapshots use bound verse IDs in SQL. No schema migration. Cache changes occur only after successful commit. SQLite `data_version` invalidates the cache after another connection changes the store, including before Undo conflict checks. One decoder handles the initial annotation load.
- A shared pure `ExactAnnotationEditor` computes exact recolors, removals, retained fragments, legacy conversion, and bookmarks. ReaderState uses it to render a pending highlight before awaiting persistence. Failure restores the prior state and preserves Retry intent. Undo/Saved success is published only after commit. Committed changes patch the reader directly instead of rereading the library. Editing remains serialized while a transaction is pending.
- A revision integer replaces full-library deep equality during reader updates. Exact annotations are indexed by chapter in UI state; preview pages mirror them only after an annotation revision. Bookmark membership is cached per document/revision and uses a verse-index map.
- Highlight rendering compares per-verse parts only on annotation updates, rewrites only changed verse ranges, and retains selection/scroll position. Same-chapter reference/Saved navigation restores the target/cue without reconstructing the attributed document.
- Gutter labels remain in content coordinates. Native layout observes viewport fragment changes; there is no extra per-scroll `setNeedsLayout`. Repeated viewport passes are skipped, fonts/label content are cached, and only entering/leaving or changed frames/indicators are written. Typography/reflow still invalidates geometry.
- VoiceOver keeps existing verse elements. Annotation edits update affected values/actions without recomputing every verse frame; reflow still refreshes geometry. Menu palette colors are cached and refreshed when color appearance changes.
- The reader’s decorative full-width background ignores touches, fixing iPad sidebar taps intercepted behind the detail. The pager uses its actual horizontal bounds (already inset by the split view) and passes top/bottom chrome touches through. Sidebar buttons expose their full 44-point hit target.
- Catalog IDs map to indices for chapter moves, adjacency, source navigation, and Saved navigation. Books/catalog/position/notice use one bootstrap actor call. This removes repeated actor hops; it does not claim parallel database execution or a measured launch-time gain.
- Saved caches resolved items and rebuilds only dirty chapters, including while the iPad Saved sidebar is visible. Its bulk chapter reads do not populate/evict the small interactive chapter cache. External changes invalidate the Saved cache. Unresolved items retain their original quotes/references.
- Preferred-only summary retrieval binds verified chapter/verse candidates in SQL instead of loading the whole book. General lexical retrieval and search semantics remain unchanged.
- Static Instruments intervals cover annotation transactions, Saved resolution, reader bootstrap, local search, and book source retrieval. No references, queries, annotations, or paths are recorded. Debug-only counters support structural regression tests; they are not timing estimates.

## Validation boundaries and deferred work

The regression suite verifies a warm edit performs no further annotation-library decoding, Saved does not evict current/neighbor chapters, incremental Saved matches a fresh rebuild, another connection invalidates caches, stale Undo is rejected, and an injected write failure rolls back a visible pending highlight. Renderer checks verify unrelated state and same-chapter navigation avoid text rebuilds, a single-verse highlight updates one range, and VoiceOver annotation changes reuse geometry. Existing migration, exact-range, cancellation, persistence, and corpus-backed source tests remain in place.

[Actual build/test inventory and screenshots](../Validation/reader-followups/README.md). Simulator evidence establishes behavior and eliminated repeated work, not physical-device latency or frame-rate improvements.

Following the audit’s proposed profiling gate, relevance/keyset search paging, a general tokenized-book cache, corpus external-content FTS/compression, and WAL journal policy are deferred. Search changes would need ranking/paging evidence; corpus changes require reproducible rebuild/integrity/search validation; WAL/protection changes need lifecycle/locked-device/checkpoint testing. They are not zero-risk substitutions. No user database or bundled corpus was replaced.

For the next device pass, use an optimized development-signed build on the slowest supported iPhone. Record Time Profiler and Points of Interest while recoloring in a large saved library, scrolling/selecting Psalm 119, switching Saved/Read, paging a common search, and asking about Psalms. Compare identical workloads and record device, OS, build, and corpus revision. Physical-device signing/test-target configuration and an actual trace remain outstanding.
