# 0019 — Saved chapters and Scripture widgets

Status: accepted for implementation, 7 October 2026. Owner request: "the ability to save entire chapters, and the ability to take saved verses / chapters and turn them into widgets (maybe people can use Apple Intelligence tools to design their own backgrounds)."

This is an explicit owner scope change. AGENTS.md previously listed widgets and AI features beyond the chapter overview as out of scope; widgets and on-device Image Playground backgrounds are now in scope. Accounts, sync, cloud services, and generated Scripture remain out of scope.

## Feature 1 — Save an entire chapter

### Data

- New user-store migration `v4_saved_chapters` (additive; the existing pre-migration backup runs automatically because an applied store has fewer migrations than registered):
  `saved_chapter(id TEXT PRIMARY KEY, editionID TEXT NOT NULL, chapterID TEXT NOT NULL, created REAL NOT NULL, updated REAL NOT NULL, UNIQUE(editionID, chapterID))`.
- Chapter identity, not a first-to-last-verse bookmark. A range bookmark would mark every verse in the gutter, show the whole chapter text in Saved, and depend on verse boundaries; a chapter save survives compatible verse corrections.
- Unresolved chapter IDs are retained and shown as unavailable, never deleted.

### Store / state

- `BibleStore.setChapterSaved(_:saved:) -> SavedChapterChange` (one transaction, idempotent), `savedChapterIDs()`, and Undo of that change with the same conflict check as annotations.
- `ReaderAnnotationChange.chapter(SavedChapterChange)` joins session/system Undo.
- Saved resolution adds one `SavedItem` per saved chapter: reference "John 3", the opening verse as preview, verse count, `savedChapter = true`. Incremental Saved rebuilds mark the chapter dirty like other edits.
- `SavedRecords.chapters` lets Delete remove exactly the displayed record, with Undo.

### UI

- Reader More menu: **Save Chapter** / **Remove Saved Chapter** (`book.closed` / `book.closed.fill`), plus Command-D in the Reader command menu.
- Saved: chapter rows read "John 3 · Chapter", with the opening line and a "Saved chapter · 36 verses" label. The **Bookmarks** filter includes saved chapters, so the segmented control stays at three readable segments on compact widths. Bible order puts a chapter before its own verses.
- VoiceOver: the More item is labeled with the chapter; Saved rows announce "Saved chapter".

## Feature 2 — Scripture widgets ("cards")

### Concept

A **card** is a styled snapshot of a Saved passage or chapter that the user designs in the app. A widget shows one chosen card, or rotates daily through all cards. Card text is copied verbatim from the bundled corpus (or the exact saved excerpt) at creation and is never generated, paraphrased, or corrected. Apple Intelligence is used only for **background images** (Image Playground), labeled as such.

### Storage and process boundary

- WidgetKit extension `BibleWidgets` (`dev.kpierre.bible.widgets`, iOS 26.0) and App Group `group.dev.kpierre.bible` on the app and extension.
- Cards live in the App Group container: `Cards/cards.json` (versioned, atomic writes) and `Cards/Backgrounds/<uuid>.jpg`. The extension reads only this folder. It never opens the corpus or the user database, so no SQLite handle crosses processes and the user database keeps complete protection.
- Card files use `completeUntilFirstUserAuthentication`, so Home and Lock Screen widgets render while the device is locked. That is a deliberate, narrower tradeoff than the user database. Only text the user explicitly placed on a card is exposed. The App Group container stays eligible for ordinary device backup.
- Deleting a saved highlight or chapter does not delete its card. Cards are independent and managed in the Widgets sheet.

### Card model (shared `BibleShared/` folder, compiled into both targets)

`WidgetCard { id, kind (passage | chapter), chapterID, verseID, reference, text, isExcerpt, editionLabel, verseCount?, style, created, updated }`.
`CardStyle { background: preset(id) | image(file, luminance), ink: automatic | light | dark, typeface: serif | sans }`.

### Backgrounds

1. **Presets** drawn in SwiftUI from the app palette: Paper, Evening, Sage, Dawn, Ink, and Rose.
2. **Image Playground** (`imagePlaygroundSheet`, shown only when `supportsImagePlayground`). It opens with an empty prompt, so people describe whatever background they want. (Revised after device QA: seeding concepts extracted from the passage delayed the sheet and pre-filled a phrase the owner didn't want.) A preview badge reads "Image Playground".
3. **Photo** via `PhotosPicker` (out of process, no library permission).

Images are downsampled to a 1200-pixel long edge, center-cropped by the widget, and stored as JPEG. Average luminance chooses light or dark ink automatically, with a manual override. A gradient scrim under the text keeps contrast.

### Widget

- Families: systemSmall, systemMedium, systemLarge, systemExtraLarge (iPad), accessoryRectangular, and accessoryInline. Accessory families are text-only.
- `AppIntentConfiguration` with **Card** (an entity query over `cards.json`) and **Rotate daily** (one entry at each local midnight, chosen deterministically).
- Text fit: `ViewThatFits` steps down serif sizes. Text that still overflows is truncated with an ellipsis, and the reference stays visible. Tapping opens the full passage.
- Tinted/clear Home Screen rendering desaturates images via `widgetAccentedRenderingMode`. `containerBackground` follows the card style.
- Tap: `widgetURL(dev.kpierre.bible://open?chapter=<id>&verse=<id>)`. The app validates the IDs against the catalog before navigating, and ignores unknown links.
- Empty state: "Make a widget from Saved in Bible."

### App UI

- Saved rows: a **Make Widget** context menu and leading swipe action.
- Saved header: a **Widgets** button opens the Widgets sheet, which lists cards with live previews, edit, and delete (with confirmation), plus how to add a widget to the Home Screen.
- Card editor: a size switcher (small/medium/large preview), background grid (presets, Image Playground, Photo), ink, typeface, and Save. Saving reloads widget timelines.

## Privacy

No network access is added. Image Playground runs through Apple's system UI; Photos uses the out-of-process picker. The extension gets its own privacy manifest declaring no collection and no tracking. It reads its own files without required-reason APIs, so it declares none. Re-audit if that changes.

## Verification plan

- Unit: the v4 migration on a v3 store preserves records; save/unsave is idempotent and unique; Saved shows chapter rows, filter, order, and unavailable chapters; delete and Undo conflict checks; card JSON round trip and version rejection; atomic replace; background deletion; deep-link validation; daily rotation; text copied verbatim from the Saved item.
- UI: Save Chapter from More, see it in Saved, and remove it; Make Widget from Saved, save, and see it in the Widgets sheet.
- Rendering: `ImageRenderer` exports of each family and style for visual review in `Docs/Validation/widgets/`.
- Manual: add the widget on the simulator Home and Lock Screens. Image Playground requires an Apple Intelligence device, so its availability fallback is verified in the simulator and real generation remains a device check.

## Evidence

- **Evidence (7 October 2026):** Xcode 27.1 (27A9269) through a per-process `DEVELOPER_DIR`, iPhone 18 Pro simulator on iOS 27.0, Debug. The full scheme run `.build/Widgets-full-phone.xcresult` passed 142 tests with 0 failures; 13 skipped are the iPad/Duo-only cases. That includes the new SavedChapterTests and ScriptureCardTests (with a rendered gallery in the attachments) and the UI tests `testSaveChapterAndMakeWidget` and `testWidgetLinkOpensValidatedPassage`. The unsigned simulator build embeds `BibleWidgets.appex`, and the simulated entitlements include the App Group.
