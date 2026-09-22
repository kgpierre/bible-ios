# Repository Guidelines

## Bible Reader — Engineering and Agent Instructions

Version 1.1 · 21 September 2026 · Implementation specification

Latest owner refinements from `HANDOFF.md` take precedence: exact selected-word highlights/bookmarks save directly from native menus; persisted typography composes with Dynamic Type; an optional on-device current-chapter overview uses an icon-only Apple Intelligence button between Appearance and More. Summaries remain separate from authoritative Scripture.

Build a free, private, native Bible reader for iPhone and iPad around **iPhone frame 2a**. Scripture, navigation, search, highlights, bookmarks, and appearance must work in airplane mode on first launch. No accounts, trackers, advertising, subscriptions, or app-operated backend.

This is a specification, not evidence of an implemented or tested app. The original design export is preserved under `Design/Reference/`; file checksums are recorded in `Design/REFERENCE-MANIFEST.json`. The native reader now bundles the configured 66-book corpus and uses durable local annotations/reading position in `BibleReader.xcodeproj`; see `README.md` and `Docs/Decisions/0003-offline-corpus-and-persistence.md` for scope and validation. Local Search and direct-reference navigation are implemented; see `Docs/Decisions/0004-search-and-books.md` for validation. Release acceptance remains incomplete. The four earlier fixtures remain Debug regression resources. Do not claim unperformed validation, final canon approval, or distribution rights.

The previous guide is preserved verbatim in [Docs/IOS-DEVELOPMENT-GUIDELINES.md](Docs/IOS-DEVELOPMENT-GUIDELINES.md). Its general iOS practices remain applicable, with the project-specific exceptions below. Read the relevant sections of this guide before implementation.

## 1. Authority, Nonnegotiable Requirements, and Defaults

Precedence: explicit owner instructions → selected 2a and newer 2b/3a–3d frames → compatible supporting frames → earlier visual brief → engineering defaults. Resolve conflicts explicitly; do not combine incompatible layouts.

- Preserve 2a's verse-per-line text, margin numbers, three-tier heading, and compact bottom passage selector. The owner's later navigation refinement adds a separate Books control to the right of the tabs and collapsible destination labels while scrolling.
- Never invent, paraphrase, silently correct, or regenerate Scripture with AI.
- Never incidentally add analytics, attribution tracking, ads, remote configuration, authentication, or cloud synchronization.
- Never delete a user database to repair initialization, corruption, or migration failures.
- Use public Apple APIs. Exported HTML is a visual reference, not production code.
- Prove native text selection and bottom navigation before building the remaining screens around them.
- Distinguish observed design details, engineering decisions, and unresolved release decisions in implementation notes.

### Project-specific exceptions to the reusable iOS guide

- **Deployment:** the reusable default is iOS/iPadOS 27. This handoff proposes **26.0** for initial engineering, pending final deployment approval. Liquid Glass on 26+ does not itself establish that older OS support was rejected. If older support becomes required, add availability-gated native material fallbacks and a compatibility matrix. Do not add unnecessary availability branches above the actual minimum target.
- **Navigation:** prefer `TabView`, `Tab`, and `.tabViewStyle(.sidebarAdaptable)` where they fit. They do not override 2a's adjacent bottom passage capsule or the selected iPad compositions. Prototype fidelity with the actual SDK before choosing the container.
- **Dependencies:** prefer native frameworks; GRDB via Swift Package Manager is the proposed SQLite exception. Verify its current API/license and pin the tested version in `Package.resolved`.

### Scope

V1 includes restored reading position; previous/next chapter; book, chapter, and direct-reference navigation; local search; four highlight colors; range bookmarks; Saved; attributed copy/system sharing; appearance/accessibility; adaptive layouts; and About with provenance, notices, and privacy information.

Defaults: KJV with a pinned exact edition; a 66-book Protestant canon pending owner confirmation; Genesis 1 on first launch and John 3 for previews; local persistence eligible for ordinary OS backup; one active scene with resizing/restoration; English UI and text with localization-ready strings.

Out of scope: accounts, iCloud sync, downloadable translations, audio, commentary, personal notes, tags, folders, plans, streaks, notifications, social features, AI features beyond the explicitly requested on-device chapter overview, widgets, Apple Watch, and arbitrary Bible imports. Do not build speculative infrastructure for these.

## 2. Design Sources

The owner supplied the extracted `Project scope selections` folder on 21 September 2026. Its six files, including `.thumbnail` and the supporting brief, are preserved byte-for-byte under `Design/Reference/`. The original ZIP itself was not supplied. Keep these references unchanged and out of the app target.

| Source | Role |
| --- | --- |
| `Bible Reader - iPhone.dc.html` | 2a, 2b, compact interactions |
| `Bible Reader - iPad.dc.html` | Responsive 3a–3d |
| `uploads/Bible-App-Visual-Design-Brief.docx` | Earlier brief, subordinate to selected frames |
| `ios-frame.jsx`, `support.js` | Export machinery; never ship |

Owner-supplied SHA-256 fingerprints, verified against both supplied and preserved files on 21 September 2026:

```text
iPhone: a4d613c33f5ac052c76562dd0880815ff7e4a32bde4e46cf8e19c344c98d570f
iPad:   d453bb28100c94ce6a4d8b14680ec7692b0f97ba009b56268ce45b7c8c4d45e6
```

| Frame | Instruction |
| --- | --- |
| 2a | Authoritative compact merged reader |
| 2b | Native chapter picker; replaces 1f |
| 3a | Wide iPad: open sidebar, bounded centered reader, toolbar passage selector |
| 3b | Collapsed sidebar; bounded reading column and sidebar toggle |
| 3c | Saved beside reader; retain visible selection |
| 3d | Narrow iPad adopts compact 2a during resizing |
| 1d | Adapt dark palette and chapter-end navigation to 2a |
| 1e | Book selection and grouped canonical navigation |
| 1g–1h | Search results and explicit typo suggestions |
| 1i–1k | Selection, highlights, existing annotation actions |
| 1a–1c | Earlier ingredients, not additional reader modes |
| 1f | Superseded chapter tiles; do not implement |

Sample Scripture, partial chapters, simulated controls, and “263 verses” are mock data, not authoritative content or verified behavior. Compact Saved and Appearance are native design extrapolations requiring review.

## 3. Native Visual Design and Liquid Glass

Use system serif for reading/book headings and system sans serif for controls, metadata, and verse numbers. Resolve fonts through platform APIs; do not require a literal “New York” font or bundle extracted Apple fonts.

Default-size targets in points, not fixed accessibility dimensions:

| Element | Compact | Wide iPad |
| --- | --- | --- |
| Book eyebrow | Sans 13 semibold, tracking 0.6 | Sans 14 semibold, tracking 0.6 |
| Book title | Serif 40 semibold, nominal line 44 | Serif 46 semibold, nominal line 52 |
| Chapter subtitle | Serif 22, line 30 | Serif 24, line 32 |
| Verse text | Serif 22, line 32 | Serif 24, line 35 |
| Verse number | Sans 14 medium | Sans 15 medium |
| Gutter / trailing inset | 36 / 10 | 40 / 12 |
| Verse gap | 6 | 6 |
| Heading-to-text gap | 26 | 30 |
| Reading width | Available width with safe margins | Target maximum 640 including gutter |

Scale font metrics and paragraph spacing; never clip glyphs, diacritics, emphasis, or large text. Align headings and wrapped lines with verse text, not the gutter edge.

| Semantic asset | Light | Dark |
| --- | --- | --- |
| Reading canvas | `#F7F4ED` | `#181A18` |
| Primary text | `#242824` | `#E9E6DE` |
| Secondary text | `#62675F` | `#B1B6AC` |
| Accent | `#45604C` | `#A5C1A8` |
| Yellow highlight | `#F1E3A5` | `#51482A` |
| Sage highlight | `#D9E6CE` | `#324638` |
| Blue highlight | `#D8E5EF` | `#2D414F` |
| Rose highlight | `#EED9DE` | `#4D353F` |

Dark fills are proposals; validate actual contrast before freezing tokens. Store semantic highlight IDs, never hex colors, in user data.

### Compact and adaptive layout

- Top trailing Appearance/More controls have at least 44-point targets. The book heading scrolls away.
- Preserve bottom passage and Read/Saved/Search capsules and selected state. Per the 21 September owner refinement, add a separate Books button on the right; collapse tab/Books labels on downward reader scrolling and restore them on upward scrolling. Retain accessibility labels, at least 44-point targets, and visible labels at accessibility sizes. Books uses an Old/New Testament segmented picker and native subtitle rows; editorial descriptions stay separate from Scripture. Reference targets: 56-point passage capsule, 64-point tab capsule, 10-point separation, 16-point outer margins.
- Use native safe areas and toolbar heights, not exported device-chrome offsets. Inset scrolling so final verses and chapter controls clear floating navigation.
- Use curated book abbreviations with full accessibility labels. At large type/narrow widths, place passage control above tabs in two rows; keep every destination reachable.
- Wide iPad: approximately 320-point sidebar, bounded 640-point reading column, passage selector in top toolbar, Appearance/More trailing, and destinations in sidebar. No redundant bottom tabs.
- Collapse sidebar without widening reading lines; retain a toggle. Narrow windows adopt 2a based on usable container width and actual content needs, not an “is iPad” check.
- Preserve chapter, visible verse, selection, Saved, and search state through resizing. Adapt popovers to sheets.

### Glass boundary

Prefer system bars, sheets, and controls. Glass is for navigation and controls; scripture remains on an opaque reading canvas. Avoid custom blur/shadow stacks and backgrounds that obscure native effects. For related custom glass controls, use `glassEffect`, glass button styles, and `GlassEffectContainer`; apply effects after layout modifiers and interactive effects only to interactive elements.

Prototype whether system tab APIs support 2a faithfully. If necessary, use a narrowly scoped custom compact container with native buttons, public glass APIs, selection semantics, keyboard focus, and safe-area handling. Do not relocate the compact passage selector to the top to avoid this work. Record the decision and SDK validation.

## 4. Architecture and Repository Organization

Use Swift 6 with strict concurrency, SwiftUI, and UIKit where native text behavior requires it. Pin a tested stable Xcode toolchain in documentation/CI; do not invent a version. Start with one app target and test targets; introduce packages only for concrete build/testing benefits.

Keep views small and composable; separate persistent/domain state from presentation state. Prefer `@Observable`, `@State` ownership, and `@Binding`/`@Bindable` editing. Keep state narrowly scoped and dependencies explicit. Use constructor injection, no global service locator or mandatory third-party state framework.

Use structured concurrency, cancellation-aware `.task`, stable model identities, and explicit loading/empty/error states. UI-bound mutable state belongs on `@MainActor`; expensive database work, parsing, indexing, and attributed-string preparation belong off the main thread where APIs permit. Respect GRDB isolation; never share raw SQLite handles across uncontrolled tasks. Cancel superseded work and reject stale responses by request identity.

| Proposed path | Responsibility |
| --- | --- |
| `BibleReader/App/` | Composition, dependencies, lifecycle, routing, restoration |
| `BibleReader/DesignSystem/` | Semantic assets, scaled typography, controls |
| `BibleReader/Features/Reader/` | Reader state and native text bridge |
| `BibleReader/Features/Library/` | Book/chapter/reference navigation |
| `BibleReader/Features/Saved/` | Annotations and list actions |
| `BibleReader/Features/Search/` | Queries and presentation |
| `BibleReader/Features/Settings/` | Appearance and About |
| `BibleReader/Domain/` | Identities, parsing, validation, annotation operations |
| `BibleReader/Data/` | Repositories, SQLite configuration, migrations |
| `BibleReader/Resources/` | Bundled corpus, manifest, attribution, localization |
| `BibleReaderTests/`, `BibleReaderUITests/` | Domain/storage and native interaction tests |
| `Content/Source/` | Pinned raw source and manifest |
| `Content/Tools/`, `Content/Tests/` | Importer, validation, local fixtures |
| `Design/Reference/` | Unchanged supplied exports |
| `Docs/Decisions/` | Architectural/design decisions and evidence |

Views must not build SQL or read files. Repositories expose domain values (`ChapterDocument`, `Passage`, `SearchPage`, `SavedItem`), not connections. Use bundled read-only SQLite plus a separate writable user database. Do not introduce SwiftData/Core Data for the same records.

## 5. Scripture Acquisition and Reproducible Content Pipeline

Acquire a vetted source during development, validate and bundle it. Never require a Bible API or first-run download. Approved corpus revisions ship with app updates. Normal builds use pinned local inputs without fetching “latest.”

Proposed source: eBible.org structured KJV, using USFX XML or an established USFM parser. Select one production format. The supplied handoff identifies a standardized 1769 source with Apocrypha and UK rights considerations; verify the current edition and redistribution terms before release. A public-domain label alone does not establish worldwide mobile rights. Keep source identity distinct from the “KJV” display label; do not silently substitute translations. Rights uncertainty blocks affected publication, not renderer/navigation work.

Manifest must record edition/display/language/provider/versification IDs; source page/archive URLs; retrieval date; raw SHA-256; source version/date; importer version/configuration hash; explicit book allowlist/order/exclusions; rights notices/attribution/review status; schema/revision/output checksums; and verified counts.

Import stages:

1. Explicitly acquire and checksum the source separately from conversion.
2. Validate archive paths, size limits, and entries; reject traversal and unexpected executable content.
3. Parse structured markup safely. Disable XML external entities/network access; never parse Scripture with regex or scrape presentation HTML.
4. Preserve books, chapters, verse boundaries, semantic runs, paragraph/poetry structure, titles, and notes in an intermediate representation.
5. Apply the explicit canon allowlist; preserve the original archive and report exclusions. Never take the first N books.
6. Generate immutable chapter documents, verse records, aliases, and search index.
7. Validate structure/text/search/integrity; fail on unknown markers instead of silently dropping content.
8. Produce a closed SQLite corpus, manifest, attribution, and machine-readable validation report; eliminate build-time WAL dependencies.
9. Review generated differences before replacing shipping resources.

Prefer a small Python CLI importer with a pinned environment. Preserve wording, punctuation, and meaningful emphasis. Document encoding/whitespace normalization; separate source/display/search representations where necessary. Never modernize spelling, invent headings, or mix publisher notes into verse text/search.

Acceptance: explicit handling of labels, bridges, omissions, and superscriptions; no duplicate IDs, orphans, unexplained dropped nodes, replacement characters, or empty expected verses. Counts come from the reviewed edition, not a universal total. Golden fixtures include Genesis 1, Psalms 23/119, John 3, a single-chapter book, and Revelation's last chapter, including italics/titles. Test known positive/negative searches and first/last books. Identical inputs yield identical normalized records and logical checksum; track binary checksum separately.

## 6. Identities and Storage Contracts

Never use pixels, SQLite row numbers, or rendered offsets as verse identities.

- `EditionID`: stable across compatible corrections; changes for edition/versification identity changes.
- `ContentRevision`: exact corpus build. `BookID`: stable code such as `JHN`.
- `ChapterID` / `VerseID`: edition, book, and source chapter/verse labels. Labels are source-aware strings, not universally integers.
- `canonicalOrdinal`: explicit sort order, not durable identity. `Passage`: validated inclusive endpoints within one edition.
- Represent bridges such as `3-4` explicitly; never fabricate two verses. Resolve covered numbers through aliases. Titles are typed blocks unless explicitly part of a source verse.

Corpus schema: `edition` (identity/revision/provenance), `book` (canonical order/names/group/heading metadata), `chapter` (source label/order/document version), `verse` (stable identity/ordinal/canonical text), `chapter_document` (one versioned Codable semantic payload per chapter), `reference_alias` (explicit ambiguity), optional `source_note`, and `verse_search` (FTS linked to stable verses). Enforce foreign keys, uniqueness of edition/book order, book/chapter order and edition/verse ordinal, and lookup indexes. Flattened document text must equal verse records; documents are not HTML blobs.

FTS5 is proposed; verify tokenizer/features in packaged on-device SQLite. Parse supported query syntax before constructing expressions; parameter binding alone does not sanitize FTS operators.

User database lives in Application Support. Bound values and transactions are mandatory:

| Record | Contract |
| --- | --- |
| `highlight` | UUID, edition/verse IDs, semantic color ID, operation/group UUID, timestamps; unique edition/verse |
| `bookmark` | UUID, edition, start/end IDs, timestamps; unique exact passage |
| `reading_position` | Edition, chapter/verse IDs, intra-verse anchor, viewport fraction, revision, timestamp |
| `migration_history` | Applied migration IDs and metadata |

Validate cross-store references in application code; SQLite foreign keys cannot span the two stores. Preserve unresolved annotations. Keep theme, face, size adjustment, and line-spacing preset in typed `UserDefaults`; not Scripture/annotations, and no Keychain for non-secret appearance settings.

Highlights and bookmarks preserve exactly the selected words, anchored to verse IDs with revision-scoped UTF-16 ranges, quoted text, and surrounding context. Recolor overlapping words rather than stacking; subset edits retain unselected fragments. Bookmarks are independent and stay within one chapter; exact duplicates are not allowed. Preserve v1 whole-verse records; convert only touched legacy highlights transactionally. Unresolved saved excerpts remain visible without guessing their word location.

## 7. Reader Renderer and Selection Prototype

Start with one noneditable, selectable `UITextView` bridged into SwiftUI and TextKit layout. One continuous chapter document enables native cross-verse selection; do not use independent text views per verse or a WebView.

Generate UTF-16-range-to-verse maps. Draw gutter numbers aligned to each verse's first line fragment, outside selectable text. Bookmark indicators must not shift indentation. Derive geometry from current wrapping/layout; preserve semantic poetry/paragraph structure and emphasis while retaining verse-per-line composition. Heading metadata is book-specific.

- Native long press, handles, magnification, and edit menus must work across the entire current chapter, including Psalm 119.
- Copy/Share uses exact selected text plus separately formatted reference/edition. Highlight/Bookmark immediately saves exactly the selected words with their resolved reference. Explicit VoiceOver “Highlight verse” actions cover that verse.
- Exclude gutter/header/control text from annotations. Safely convert Swift strings and UIKit UTF-16 ranges; offsets are ephemeral.
- Persistent fills follow text lines behind glyphs; active native selection stays distinguishable.
- Remap selection from semantic anchors after resizing/type changes. Retain selected passage where possible if a popover dismisses.
- Avoid replacing the entire attributed document on annotation changes when it destroys selection or scroll position.

Before expanding screens, prove cross-verse selection, gutter-free copying, multiline fills, menu actions, VoiceOver order, long-chapter performance, and resize restoration. If TextKit 2 is unsuitable, document a public-API alternative and tradeoffs.

## 8. Navigation and Restoration

Maintain independent Read/Saved/Search state and one reader coordinator for canonical chapter navigation. Prefer `NavigationStack` for drill-down and `NavigationSplitView` for genuine multicolumn content; preserve per-destination history.

| Action | Result |
| --- | --- |
| Cold launch | Last valid passage/position; Genesis 1 on first install |
| Passage capsule | Current book's chapter picker; Books returns to book selection |
| Choose chapter / dismiss picker | Commit and show heading / preserve current position |
| Search result | Navigate to first verse with temporary cue; retain query/results/scroll |
| Open Saved item, compact | Navigate to Read; preserve Saved filter/scroll |
| Select Saved item, wide | Update reader detail with Saved still visible |
| Previous/next | Edition order across books; never wrap Bible endpoints |
| Appearance change | Preserve semantic reading anchor |

Persist first meaningfully visible verse, intra-verse anchor, and relative viewport position. Debounce scroll writes and flush at lifecycle transitions, not only termination. Restore after layout; clamp revised offsets and fall back to verse start. Retain unavailable references and offer navigation without deleting them.

2b picker: native adaptive sheet/popover, grouped content, large sans book title, real chapter count, plain numbers, circular filled current chapter. Five columns is a default, not an accessibility limit. Keep Psalms scrollable; books use complete configured canonical groups. Direct-reference input uses the Search parser.

## 9. Search and Reference Parsing

All search is local. Reference grammar supports `John 3`, `John 3:16`, `John 3:16-18`, `Jn 3:16`, and `1 John 2:1` through explicit aliases and corpus validation. `Jude 5` means verse 5; `Jude 1:5` is explicit; bare single-chapter books open their chapter. Reject cross-chapter/disjoint ranges understandably. Typo suggestions require a tap; never silently correct `Jhon 3`.

Proposed text behavior: case-insensitive whole tokens, AND for ordinary words, quoted phrases. Trim/limit input, escape supported syntax, bind values, and handle punctuation-only queries. Do not expose arbitrary SQL/FTS operators or claim unimplemented stemming, semantic, synonym, or fuzzy text search.

Debounce about 200 ms, cancel superseded work, reject late responses. Page 50 results with deterministic relevance-then-canonical ordering and real counts. Use native styled excerpts with validated match ranges, never executable HTML. Preserve query/results/position on return; do not persist search history in v1.

## 10. Annotations, Saved, Copy, and Share

Yellow/Sage/Blue/Rose controls show names and checkmarks, not color alone. Native selection menu color and Bookmark actions save immediately in one transaction; there is no annotation confirmation sheet. Existing highlights support recolor/removal and session Undo; bookmarks are independent.

Persist intent before showing completed success. Roll back optimistic UI on failure and explain unsaved changes. Range writes are atomic. Session Undo captures before/after operations and must not overwrite later edits inadvertently.

Saved filters: All, Highlights, Bookmarks. Default recent order with Bible order available. Batch-resolve legacy passages from the corpus. Exact annotations retain their original selected quote/context for verification and unresolved-source recovery. Show text/reference plus labeled color/icon; preserve iPad selection. Empty copy: “Your highlights and bookmarks will appear here.” No sign-in/onboarding. Delete only requested annotations, offer Undo, preserve reading position.

Copy/share exact text followed by reference and edition, for example `— John 3:16–18, KJV`; label partial selections as excerpts where needed and include required notices. Use system sharing. Write clipboard only after Copy, never proactively read it. No promotional images, marketing links, or app advertisements.

## 11. Appearance and Accessibility

Offer System/Light/Dark, Serif/System Sans, modest text-size adjustment, and a few line-spacing presets. Default system theme/serif. Adjustments compose with Dynamic Type.

- Support all Dynamic Type categories without clipping; maintain readable wide-screen line lengths.
- Use semantic colors, localized strings, accessible icon names, destination labels that collapse only at non-accessibility sizes while scrolling down, and at least 44-point targets.
- VoiceOver announces verse reference/text in reading order, annotation states/actions, without duplicate gutter numbers. Offer per-verse annotation actions independent of selection.
- Chapter labels include book/chapter/selected state. Respect Reduce Motion, Reduce Transparency, Increase Contrast, and differentiate-without-color.
- Validate both themes, all highlight fills, and actual glass backgrounds.
- Keyboard: Command-F Search; Command-Shift-S wide sidebar; Command-[ / Command-] previous/next when not editing; standard Copy; Escape dismissal; discoverable shortcuts.
- Support pointer focus/hover without requiring hover. Pencil uses normal touch; no handwriting.

Accessibility may change spacing/chrome arrangement, never remove content, actions, or destinations to match screenshots.

## 12. Privacy, Security, and Data Preservation

No analytics/crash SDKs, ad IDs, fingerprinting, remote fonts, embedded web content, runtime Bible service, or app-operated sync disguised as backup. Do not log reading history, selections, queries, annotations, or personal database paths. Diagnostics must be privacy-safe. User-initiated sharing/external attribution links are explicit exceptions to offline operation.

Protect the user database and sidecars with iOS Data Protection; complete protection is proposed. Test post-unlock access; locked data is retryable, never grounds for replacing the store. Corpus stays immutable in the bundle. User data remains eligible for ordinary OS backup; protected temporary exports/snapshots are removed after use.

Audit final application/dependencies with network capture: core offline flows produce no app-originated requests. Derive App Store disclosures from actual behavior; verify “no data collected.” Include applicable privacy manifests and valid required-reason API declarations; never invent reasons.

Version corpus schema, document format, user schema, and content revision independently. Migrate transactionally with tests. Before risky migration, create a consistent protected database backup, not a main-file-only copy of active WAL storage; check free space and document snapshot retention/cleanup. Failure retains originals, gives actionable errors, and supports retry. Never silently reset.

Compatible corrections retain verse IDs and update revision. Canon/versification identity changes may require new edition IDs and explicit mappings. Preserve unresolved annotations and expose unavailable references; never guess mappings by equal verse numbers. Invalid corpus means local-content error, never placeholder Scripture or automatic deletion.

## 13. Errors and Performance

Avoid network-style launch screens, wrong-chapter flashes, full-Bible view/attributed-string instantiation, and launch-time corpus/index rebuilding. Keep current chapter plus a small bounded neighboring cache; profile before adding complexity.

Handle locked stores with safe retry; disk-full/write errors with previous state and an unsaved-change message; missing corpus with explicit load failure; invalid references with guidance; search failure with retained query/retry rather than “No results”; missing annotation targets with retained records.

Unmeasured targets on the slowest supported real test device: usable cold reader ~2 seconds; ordinary chapter change within 150 ms; first search page within 100 ms after debounce; no perceptible Psalm 119 scroll/selection stalls. Record device, OS, build mode, corpus revision, and workload. These are goals, not results.

## 14. Development Workflow and Verification

Inspect implementation and relevant source frame, plan briefly, implement the smallest coherent change, build, fix introduced compiler warnings/errors, and run risk-appropriate tests. Launch/inspect iPhone and iPad simulators for UI changes, including resizing. Do not claim implementation complete without a successful build; report blocked tooling precisely and continue independent work. Documentation-only edits do not establish app build readiness.

Prefer Swift Testing for domain logic and XCTest/XCUITest for interactions. Never weaken tests to pass or write tests that only mirror implementation.

| Area | Required coverage |
| --- | --- |
| Import | Canon/counts/IDs/markers/fidelity and safe archive/XML parsing |
| References | Numbered books, aliases, single-chapter books, invalid ranges, bridges, explicit typo correction |
| Search | Tokens/phrases, apostrophes/punctuation, syntax safety, deterministic paging/cancellation |
| Persistence | Atomic edits, duplicate bookmarks, recolor splits, failures, Undo, all shipped migrations |
| Renderer | UTF-16/graphemes, cross-verse selection, gutter-free copying, long verses/chapters |
| Restoration | Relaunch, theme/type/orientation/resizing, Saved/Search round trips |
| Accessibility | VoiceOver, largest type, contrast, reduced motion/transparency, keyboard |
| Offline/privacy | Fresh airplane-mode install and no core-flow runtime requests |
| Release corpus | Packaged integrity/SQLite compatibility/provenance/rights |

Visual references cover 2a light/dark, 2b, and 3a–3d. Check hierarchy, alignment, bounded width, typography, and placement; HTML pixel identity is not required. Pin simulator/runtime versions for snapshots. Run native tests on a small supported iPhone and an iPad plus manual physical-device checks. Resize with selection and Saved active; test short chapters, Psalm 119, Genesis 1, and the final chapter.

Establish shared `BibleReader` scheme. The shared `BibleReader` scheme now exists. Commands below describe project discovery and testing; `README.md` records the foundation validation commands:

```sh
xcodebuild -list -project BibleReader.xcodeproj
xcodebuild -showdestinations -scheme BibleReader -project BibleReader.xcodeproj
xcodebuild test -project BibleReader.xcodeproj -scheme BibleReader -destination 'platform=iOS Simulator,id=SIMULATOR_UUID'
```

Use actual project/workspace and available destination. Record tested toolchain and exact successful setup/build/test commands in README. Native validation requires macOS/Xcode; Linux importer tests are not compilation evidence. Document explicit acquisition, deterministic import, and content validation commands. Tests use pinned local fixtures, not live endpoints. CI validates corpus, domain/storage tests, simulator build, and focused UI smoke tests; wider physical-device checks gate release.

Keep changes/commits focused, with imperative subjects; never rewrite unrelated code. PRs explain behavior, link relevant issues, list validation, and include UI screenshots. Commit dependency resolution, manifests, migrations, and reproducible tooling; never secrets, signing credentials, or personal device identifiers.

## 15. Delivery Sequence, Open Decisions, and Done Criteria

1. **Foundation/risk prototypes:** running native 2a chrome, continuous selection, gutters, glass, resizing.
2. **Content:** pinned source/canon, importer, validated bundled database, provenance.
3. **Reader/navigation:** 2a/2b/3a/3b/3d, books, chapter boundaries, restoration.
4. **Annotations:** transactional exact-word highlights/bookmarks, direct menu actions, Undo, Saved/3c.
5. **Search/appearance:** parser, local search, themes/scaling, copy/share.
6. **Resilience/accessibility:** assistive-input matrix, errors, migrations, offline verification.
7. **Release:** rights/territories, corpus/privacy audits, device QA, TestFlight/store materials.

Resolve before release: final name/bundle ID/signing owner; exact KJV source/canon/territories; minimum OS 26 versus older support; native compact navigation choice; final compact Saved/Appearance layouts. Use temporary `BibleReader` naming, configurable content tooling, proposed OS 26 baseline, early navigation prototypes, and documented native design extrapolations meanwhile. Do not invent ownership, rights clearance, or approvals. These decisions do not require repeated permission for reversible engineering; escalate product-requirement changes, material rights issues, and ungranted publishing/signing authority.

Done means faithful 2a and lossless 3a–3d adaptation; complete sourced/validated/attributed offline corpus; real-data search/selection/annotations/copy/share/Saved; durable data through updates/migrations; usable large type/VoiceOver/keyboard/dark/reduced transparency; no trackers/unexpected networking; documented rights/canon/OS/distribution decisions; passing relevant tests and physical-device performance/native checks. Completion notes name actual tests and limitations. No simulated controls, mock counts, or partial chapters in production.

## 16. Implementation References

The owner-supplied handoff dates its source consultation to 21 September 2026. This update does not independently verify those sources, SDK details, or licensing. Recheck at implementation/release; external references do not override selected designs.

- [Apple Fonts](https://developer.apple.com/fonts/)
- [Apple: Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)
- [Apple: UITextView](https://developer.apple.com/documentation/uikit/uitextview)
- [Apple: Privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [eBible.org: proposed KJV edition and rights](https://ebible.org/find/show.php?id=eng-kjv)
- [USFM specification](https://ubsicap.github.io/usfm/)
- [SQLite FTS5](https://www.sqlite.org/fts5.html)
- [GRDB maintainer repository](https://github.com/groue/GRDB.swift)

## Paper-turn Experiment

The owner requested a thin Bible-paper left/right turn. Follow the ordered hypothesis and acceptance gates in `Docs/Decisions/0005-thin-paper-turn.md` after Search and navigation verification. Start with public native page-curl APIs in an isolated development experiment. Preserve the continuous selectable reader, semantic anchors, annotations, accessibility alternatives, and opaque resting paper. Do not claim physical fidelity or production readiness from a simulator-only prototype.
