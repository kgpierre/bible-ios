# 0020 — HIG alignment pass

Status: implemented, 7 October 2026. Owner request: implement the HIG audit's recommendations except #21 (convert Search results to a `List` with context menus) and the first bullet of #6 (replace the glass chapter-number circles in the picker).

## Owner decision: compact tab bar (#7)

The audit suggested evaluating iOS 26's `TabView` + `tabViewBottomAccessory` + `tabBarMinimizeBehavior(.onScrollDown)` for compact width. The system accessory sits above the tab bar and moves inline only when the bar minimizes, so it cannot keep 2a's passage capsule beside the tabs at rest. The owner chose to keep the custom compact bar (`CompactReaderNavigation`). The `NativeTabsProbe` fixture remains for later comparison. These follow-up items were done inside the custom bar instead:

- Each compact destination has its own `NavigationStack` (#9). The selected stack is shown and placed frontmost with `zIndex`. Hidden stacks keep their state but are excluded from touches and VoiceOver.
- Appearance, Summarize, and More appear only on Read (#8).
- Saved and Search use system large titles (#10). Their serif face comes from `UINavigationBar.appearance().largeTitleTextAttributes`, set at launch (`NavigationTitleStyle`). That font is resolved once at launch, so a Dynamic Type change applies to newly created bars, not to bars already on screen.

## Changes

| Audit item | Change |
| --- | --- |
| 1 | Title case for menus, buttons, setting labels, and the Reader command menu. |
| 2 | Widgets uses the icon-only Close button like the other read-only sheets. The card editor keeps Cancel/Save. |
| 3, 16 | `ContentUnavailableView` for the Saved empty, filtered, and error states, Search idle/no-results/failure, and the reader's unavailable state (with Try Again when the failure may be temporary). |
| 4 | Automatic grammar agreement (`^[n verse](inflect: true)`) for verse and chapter counts in Search, Saved, the picker, and widget cards. |
| 5 | `ReaderState.errorTitle` gives each alert a specific title, such as "Couldn’t Save Selection". |
| 6 (second bullet), 18 | Picker reference lookup now uses `.searchable` with suggestions, replacing the glass capsule field. Typo corrections still require a tap. |
| 11 | Search removed from More. Undo is named after the last change ("Undo Highlight", "Undo Delete") in More, in Saved, and for the system `UndoManager`. |
| 12 | Command-1/2/3 for destinations, Command-Shift-A for Appearance, Command-Shift-Y to summarize. AGENTS.md no longer lists the retired Command-Shift-S sidebar shortcut. |
| 14 | The selection menu removes the system Share, leaving Share Passage, which includes the reference and edition. |
| 15 | Source-note targets are at least 44 × 44 points, extending into the leading margin and stopping short of the text. |
| 17, 19 | The picker's root is Books, with the current book's chapters pushed onto the stack, so the system back button returns to Books. The testament control sits in a `safeAreaBar`. |
| 20, 22 | Search uses `.searchable`. The next page loads when the last row appears. A button appears only to retry a failed page. |
| 24–28 | Saved: the filter is in a top `safeAreaBar`, and Sort, Widgets, and Undo are toolbar items. At accessibility sizes, Show and Sort share one menu. Pull to refresh, the redundant section header, the unused `wide` path, and the custom selection fill were removed. The context menu adds Open, Copy, and Share with a preview. Saved chapters offer no Copy/Share because they store only the opening verse. |
| 29, 30 | Appearance opens as a popover from its toolbar button. On iPhone it becomes a medium/large sheet with the reader interactive behind it. Theme uses segments, and each setting has its own footer. |
| 31, 32 | Support is hidden until `AppInfo.donationURL` exists. External links share one row style. Before adding a donation URL, confirm App Store Guideline 3.1.1 (tips to the developer generally require In-App Purchase). |
| 33–35 | Summary uses `navigationSubtitle`, a prominent circular send button, semantic colors, and `textCase(.uppercase)`, so VoiceOver reads ordinary words. |
| 36, 38 | Widget card rows are `NavigationLink`s with chevrons. The Image Playground row is hidden where unsupported, and the footer explains why. |
| 37 | Deliberately kept: card deletion asks for confirmation. A card's Image Playground or photo background cannot be recreated, while Saved deletions have Undo. |
| — | Sheets (Appearance, Widgets, Notes, Summary) set the app accent explicitly. Popover and sheet presentations had shown system blue. |
| 39 | Card text uses `.primary` outside full-color widget rendering, so it stays legible on tinted, clear, and Lock Screen presentations. |

## Not done

- #21 and the first bullet of #6, per the owner.
- #23 (`List(selection:)` for Search) depends on #21 and remains the existing selected-row tint.
- #13 (scroll-edge effect under the reader's top buttons) needed no change. A simulator screenshot of the scrolled reader (iPhone 18 Pro, iOS 27.0) shows the system top edge effect. Confirm on a physical device.
- Search reference matches and typo corrections stay in the results area, not in `.searchSuggestions`, because suggestions disappear when the field loses focus.
