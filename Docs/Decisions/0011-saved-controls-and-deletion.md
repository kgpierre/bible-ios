# Saved filters, sorting, and deletion

22 September 2026. Continues the owner's requested implementation from the handoff, beginning with Saved.

`SavedView` is shared by compact Saved and the wide sidebar. All/Highlights/Bookmarks filters and Most recent/Bible order sorting live in `AppState`, retaining choices across Read/Saved and layout changes. The compact destination remains mounted to retain its list position. Bible ordering uses catalog chapter order and source-document verse order, then excerpt offset; it does not sort reference labels lexically. Unavailable chapters remain visible after known chapters. Pull-to-refresh reloads Saved explicitly.

Each resolved row carries the original persisted records it represents. A legacy highlight row may represent multiple contiguous records from one operation. The store compares these records inside the deletion transaction before deleting only those IDs. Exact highlights and bookmarks remain independent. Source text need not resolve for deletion or Undo, preserving recovery for unavailable excerpts. No migration or corpus replacement is involved.

The change captures the existing exact/legacy scope and reuses the transactional Undo conflict checks. Later edits in that scope prevent stale Undo. A failed deletion leaves the row present and offers Retry of the original intent. The row disappears and Undo becomes available only after commit. Reading position and the selected Saved identity are not changed by deletion, allowing a restored row to regain its selection.

Delete is available by native swipe action, context menu, and accessibility action. Full-swipe deletion is disabled. A labeled Undo control remains in Saved alongside the existing More action. Dynamic Type uses native menu pickers and untruncated excerpts at accessibility sizes.

Validation also exposed a UIKit lifecycle crash on iPad when Saved remained active while rotation rebuilt the compact reader. The inactive reader must supply an initial page to its `UIPageViewController`, even while its navigation gestures are disabled. This invariant now has a dedicated regression test.

See [validation evidence](../Validation/saved/README.md) for actual results and outstanding checks. The broader physical-device, VoiceOver, privacy, and release gates remain open.
