# Local Search and Books navigation

21 September 2026. Implementation evidence, not release acceptance.

Search uses the bundled immutable FTS5 index, bound expressions assembled from supported tokens/quoted phrases, real counts, deterministic BM25/canonical ordering, and 50-result pages. The reference parser resolves explicit aliases against the configured corpus, including numbered and single-chapter books. Misspellings require an explicit suggestion tap. Debounced/cancelled requests reject stale responses. Query, results, and scroll state remain in memory only.

Books is a separate compact control beside Read/Saved/Search. Native subtitle rows contain editorial descriptions, never Scripture. An Old/New Testament segmented picker becomes a menu at accessibility sizes. The current passage opens its book’s chapters, and direct-reference input shares the Search parser. Compact Books chapter selection returns to Read.

The compact custom Layout retains control identity and reserves navigation height while destination labels collapse/expand. Books presentation attaches once to the stable root. The reader draws behind chrome but excludes those regions from text-view hit testing. Crucially, the hit test uses `bounds.minY/maxY` because points in a scrolled UITextView are in content coordinates. Comparing directly to viewport height blocked valid upward drags after scrolling.

Earlier Search evidence is preserved in HANDOFF.md (`Search-second`, `Search-iPad-final`, `Search-iPhone-final` bundles). Those were not a green full phone suite. Current focused iPhone Books collapse/expand, single-tap Books, Testament switching, and chapter selection passed in `.build/Handoff-interactions-run.xcresult`; the cross-verse direct-selection and palette checks also passed there. The corrected coordinate behavior has a renderer regression test. Subsequent final validation is recorded in README/HANDOFF.

Remaining release acceptance includes physical devices, full assistive-input coverage, and offline/network capture. Simulator results do not establish any of those.
