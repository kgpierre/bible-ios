# 0022 — Save Chapter toolbar button

Date: 15 October 2026
Status: Implemented; owner decision.

## Owner decision

Save Chapter / Remove Saved Chapter moves out of the More menu into its own icon-only toolbar button on Read. The owner confirmed this on 15 October 2026. The trailing order is Appearance, Summary, Save Chapter, More, on both compact and regular width. Summary still sits between Appearance and More, as the earlier refinement requires.

This supersedes "More → Save Chapter" in [0019](0019-saved-chapters-and-widgets.md) and the trailing-group description in [0017](0017-ipad-top-tab-bar.md). Command-D is unchanged.

## Behavior

- The button's glyph and accessibility label reflect the current state ("Save Chapter" or "Remove Saved Chapter"). Undo continues to work from Saved and through system Undo.
- It is disabled while the chapter is loading, like Summary, and while a save is in progress.
- Command-D works only while Read is the active destination and no reader sheet is open, so it cannot save a hidden chapter from Search or Saved.

## Open checks

- A fourth trailing icon on the narrowest supported iPhone, at the largest non-accessibility text size, with Large Content Viewer.
- Final visual review alongside the compact Saved and Appearance layouts, which are still pending owner review.
