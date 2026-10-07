# Physical-device QA — October 2026

Device: Kyle's iPhone 17 Pro Max (iPhone18,2), connected over Device Hub. Toolchain: Xcode 27.1 (27A9269) through a per-process `DEVELOPER_DIR`, Debug, signed with team AVER2M3454 (automatic provisioning registered `dev.kpierre.bible.widgets` and App Group `group.dev.kpierre.bible`). Record the iOS build from Settings → General → About.

## Automated on device

| Run | Result bundle | Outcome |
| --- | --- | --- |
| Full scheme (unit + UI), iOS 27.0 (24A437) | `.build/DeviceQA-full-1.xcresult` | **Passed**: 143 passed, 0 failed, 12 skipped. The skipped tests are iPad/Duo/wide-layout cases plus the two opt-in model-evaluation suites. |

Observed on device: Image Playground is reported as supported, so the button is enabled. The editor renders correctly in dark appearance. Saved chapter, Make Widget, the Widgets sheet, and the widget link all pass, with screenshots in the result bundle.

UI tests use isolated stores and card folders (`BIBLE_TEST_STORE`); the owner's real reading data is not touched. Installing this Debug build over an existing install keeps the app's data; the next normal launch applies migration `v4_saved_chapters` after making the protected pre-migration backup.

## Owner checklist (cannot be scripted)

Mark each ✅ / ❌ with a note. Cards from the UI tests live in isolated folders, so make a fresh card first: Saved → touch and hold an item → Make Widget → Save.

### Widgets
1. Home Screen: touch and hold → Edit → Add Widget → Bible → add Small, Medium, and Large. Each shows your newest card; text is readable and not clipped mid-glyph.
2. Touch and hold a widget → Edit Widget → choose a different card; then turn on Rotate Daily.
3. Tap a widget: the app opens the passage, with the verse cue for passage cards and the chapter start for chapter cards.
4. Lock Screen: add the rectangular and inline widgets; check they render while locked (after first unlock).
5. Home Screen → Edit → Customize → Tinted, then Clear: the image background desaturates and the text stays legible.
6. Delete the card in Saved → Widgets: the widget says the card was removed and asks you to choose another.

### Backgrounds
7. Make Widget → Create with Image Playground: suggested concepts relate to the passage; the generated image appears in the preview with legible text, and Automatic ink picks a sensible color.
8. Choose Photo: pick a bright photo and a dark photo; check Automatic ink, then override Light/Dark.
9. Save, reopen the card from Saved → Widgets: the background persists; the Home Screen widget updates.

### Saved chapters
10. More → Save Chapter on a long chapter (Psalm 119), then check Saved → Bookmarks. Undo from Saved. Command-D with a hardware keyboard if available.

### Feel and performance (prior open gates)
11. Page curl feel and interrupted turns; selection handles and magnifier across verses in Psalm 119; first swipe and first Search keyboard (no stall).
12. Cold launch to a usable reader (target ≈2 s) and chapter change (target ≤150 ms by feel; Instruments trace optional).
13. Airplane mode, then relaunch: reading, Search, Saved, widgets all work.
14. VoiceOver pass over the reader, Saved (Make widget / Delete actions), and the card editor; largest text size in the editor.
- Image Playground now opens with an empty prompt (owner feedback: pre-filled phrase and delay). Rebuilt and reinstalled on device; owner to confirm the delay is gone.
