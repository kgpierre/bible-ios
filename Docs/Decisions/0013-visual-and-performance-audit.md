# Visual consistency and performance audit — 25 September 2026

The owner asked for an audit of the whole app, including fixes for technical issues and visual inconsistencies, plus performance work. Findings come from simulator screenshots taken with a temporary XCUITest tour: iPhone 18 Pro and iPad Pro 13-inch (M5) on iOS 27.0, light, dark, largest accessibility type, John 3, Song of Solomon 2, and Psalm 119. They also come from Debug timing measurements against the bundled corpus. No Scripture, corpus, schema, user-database, or signing changes.

## Fixed

- **Passage capsule showed an abbreviation beside empty space** ("Jhn 3", "Lev 2"). The capsule's `HStack` re-proposed the label's own measured width to `ViewThatFits`, and floating-point rounding rejected the full label. Each option is now a complete capsule label. `ReaderNavigationLayout` proposes the width the tabs leave (168-point tab target, 10-point gap) and stacks the rows only when no label fits beside the tabs. Stacking still happens at accessibility sizes. Song of Solomon 2 no longer stacks at default type. It uses the short label.
- **Italic overhang.** Serif italic runs ("*of* the Spirit", "*to be* an") visually swallowed the following roman space. Their last glyph now gets presentation-only kerning (0.08 em). A new regression test (`italicOverhangSpacingIsPresentationOnly`) checks that the text storage and copied text still equal the source text.
- **No edge effect behind the floating toolbar.** The navigation bar cannot discover the text view nested inside the page-curl controller, so Scripture showed through at full contrast under the status bar and glass controls. `ChapterTurnContainer` now requests the native top edge effect with `UIScrollEdgeElementContainerInteraction` and tracks the active chapter page. It does not use a custom blur or gradient.
- **Saved looked different from Search.** Saved used a small navigation-bar title, plain rows, and accent-tinted body text. Both destinations now share `DestinationTitle`, a scaled serif heading. Saved rows now match Search results: an accent reference, a serif excerpt in the primary color, and card rows. The highlight label shows a color swatch with its name, so color is never the only cue.
- **Sheet chrome was inconsistent.** Appearance, About, and Summary used "Done" on gray grouped backgrounds, while the chapter picker used the native close role on the warm canvas. All four now use the close role (existing accessibility identifiers kept), and Appearance and About use the reading canvas.
- **The Appearance theme picker repeated "Theme"** under its own section header. The inline picker's label is hidden.
- **The current book used a bookmark symbol** in Books and the wide sidebar, which reads as a saved bookmark. It is now a checkmark with the existing "Current book" accessibility label.
- **The wide sidebar always opened on Old Testament.** It now follows the current book, so John opens New Testament.
- **More menu.** Items are grouped (navigation, annotation/share, About), and About has an icon like the others.
- **Dead code.** Removed `isBooksPresented` and its unreachable Books sheet, left over from the removed compact Books button.

## Performance

Debug build, iOS 27.0 simulator on the development Mac. These are relative indicators, not device results:

| Work | Time |
| --- | --- |
| Open stores / reader bootstrap | 4 ms / 9 ms |
| Decode Psalm 119 | 1.7 ms |
| Psalm 119 configure + first layout | ~2.5 + ~9 ms |
| Highlight update | 1.2 ms |
| Warm search, common terms ("the", "and") | ~30 ms |
| First search of a session ("the", cold) | 134 ms |

Rendering, storage, and warm search were already within the §13 goals, so they were left alone. The measured outlier was the **first query of a session**: cold FTS pages plus building the reference parser. A rewritten query that computed snippets only for the page rows made no difference (the cost is scoring every match with `bm25`), so the SQL is unchanged. Instead, `BibleStore.prewarmSearch()` builds the parser and reads the FTS index blocks (about 3.5 MB) once, at utility priority on the search connection, when Search first becomes active. It is read-only, idempotent, and does not block chapter or position work.

Smaller changes: highlight fills resolve their dynamic asset colors once instead of per highlighted verse, and the italic font is built once per document build instead of once per run.

## Follow-up: compact corpus and About (owner request, same day)

The owner asked for the bundled Bible file to be shrunk. Importer version 2 (`Content/Tools/build_corpus.py`) writes corpus **schema 2 / document 2**:

- Chapter documents are stored as raw-DEFLATE JSON BLOBs (identical JSON after inflation) instead of TEXT (11.1 → 3.3 MB).
- `verse_search` is an external-content FTS5 table over `verse.text`, with `content_rowid='ordinal'`. The duplicate `verse_search_content` copy is gone (−5.5 MB). The FTS index is optimized after the rebuild and integrity-checked.
- The redundant `verse_chapter` index is dropped. `UNIQUE(chapterID,label)` already leads with `chapterID`.

Result: **34 MB → 16 MB**. The logical content revision is unchanged (`221de95d…`), so stored reading positions and annotation revisions remain valid. A direct comparison against the previous file found no differences in verses, books, chapters, or aliases, and all 1,189 inflated documents are byte-identical. The app requires schema 2 and document 2 and treats a corrupt payload as a corpus error. Timings (simulator, Debug): Psalm 119 decode 1.7 ms (unchanged); cold first "the" search 47 ms (was 134 ms); warm 23 ms. The binary checksum now reflects the local SQLite 3.53.1 and Python 3.13.14 toolchain. The previous file was built with SQLite 3.49.1.

About was rebuilt as `AboutView` and is reached from More → About Bible. It shows:

- the app name ("Bible", also the home-screen display name) and version
- a short description
- an icon slot (a placeholder until an `AboutIcon` image asset is added)
- the author credit (Kyle Pierre, kpierre.dev)
- a Support development button driven by `AppInfo.donationURL`, disabled while it is nil
- Scripture attribution with the edition notice
- GRDB credit and license, the Apple Intelligence disclaimer, and the privacy statement

External donation links can conflict with App Review guideline 3.1.1 outside approved nonprofits or specific storefront rules; review before submission.

## Not changed

- `UITabBar` titles do not grow with Dynamic Type (UIKit offers the large-content viewer instead). This is native behavior.
- Automated simulator taps through AXe did not reach the app in this environment, so screenshots come from XCUITest. One iPad long-press step failed once and passed on rerun. Treat that as simulator input flakiness, not verified device behavior.

## Validation

See the README entry "Visual and performance audit (25 September 2026)" for commands and results. Physical-device performance, assistive-technology passes, and the release gates in decision 0012 remain open.
