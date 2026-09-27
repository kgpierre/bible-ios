# iPad top tab bar, bottom-trailing passage selector, glass chapter picker — 27 September 2026

The owner asked to optimize the iPad layout: move the book/chapter picker from the top toolbar to the bottom right, and replace the custom sidebar with the system's sidebar-to-top-bar navigation. After reviewing a sidebar-adaptable build, the owner chose **the top tab bar only, with no sidebar**. They also asked for Liquid Glass chapter buttons on every device.

These are explicit owner instructions. They supersede frames 3a–3c (open sidebar, toolbar passage selector, Saved beside the reader) and the "Wide iPad" line in AGENTS.md §3.

## Decisions

- **Regular width** (a full-screen iPad in either orientation, or a regular-width multitasking window) uses `TabView` with `.tabViewStyle(.tabBarOnly)`. Read, Saved, and Search appear in the system top tab bar, and Search uses the `.search` role. Appearance, Summary, and More stay trailing on Read.
  - A sidebar-adaptable version was built and tested first: its sidebar held a Books section with Old and New Testament. The owner removed the sidebar. Books stay reachable from the passage picker, which is also how iPhone reaches them.
- **Passage selector:** the 2a glass capsule floats at the bottom-trailing corner of the Read tab. It sits in a bottom safe-area inset, so the final verses scroll clear of it. The picker opens as a popover that points at the capsule.
- **Saved and Search** are full tabs bounded to a 720-point column. Opening an item switches to Read, as on iPhone. The earlier 3c "Saved beside reader" composition is gone.
- **Compact width** (iPhone, and narrow iPad windows) is unchanged 2a chrome. It now uses a plain `NavigationStack`; the `NavigationSplitView` it replaced was forced to show only its detail column. The switch between layouts follows `horizontalSizeClass`, the same trait the system uses, instead of the earlier 920-point width check.
- **⌘⇧S (Toggle sidebar)** is removed because there is no sidebar. ⌘F, ⌘[, and ⌘] are unchanged.
- **Chapter picker:** chapter numbers are interactive `glassEffect` circles in a `GlassEffectContainer` with 0 spacing, so neighbors never merge. The current chapter uses accent-tinted glass. The highlight ring and dot are unchanged. The manual Reduce Transparency fill is gone: system glass adapts to Reduce Transparency and Increase Contrast by itself. The same view serves the iPhone sheet and the iPad popover.

## Tradeoff

Moving between regular and compact width (for example, resizing a Stage Manager window) swaps the container, so the reader view is rebuilt. Position is restored from the semantic anchor in `ReaderState`, as it is after a relaunch. An active text selection is restored from `ReaderState.selection` where possible, but this has not been re-verified across the swap. Full-screen rotation stays within regular width, and the test below verifies it.

## Validation (iOS 27 simulators, Xcode 27.0 27A266a)

- On iPad Pro 13-inch (M5), four tests pass:
  - `testIPadTopTabsAndRotationRestoration`: top tabs, capsule placement, Psalm 119 first visible verse restored after rotation, no sidebar in landscape;
  - `testIPadSavedTabOpensReader`;
  - `testSearchSurvivesIPadTabsAndRotation`;
  - `testChapterPickerGlassAndHighlightIndicators` (light and dark glass screenshots).
- They replace `testIPadWideAndNarrowRestoration`, `testIPadSavedUpdatesAlongsideReader`, and `testSearchSurvivesIPadResize`. Those tests assumed a custom sidebar and a rotation from portrait to compact width, which a full-screen iPad no longer does.
- **Not verified:** compact-width iPad windows (Split View or Stage Manager) and device feel.

## Two Pages in iPad landscape (owner request, same day)

The owner asked whether landscape iPad could show facing pages that turn like a book instead of scrolling. They chose to make it a setting.

- **Setting.** Appearance → Pages → *Landscape pages*: Scroll (default) or Two Pages. It appears on iPad only.
  - It is stored in the existing appearance payload as an optional field. Payloads saved before it existed read as Scroll and keep their other values, and a unit test covers this.
  - *Reset reading style* leaves it unchanged.
- **When it applies.** Only in the regular-width Read tab, in landscape, when the reader is at least 960 points wide. Otherwise the continuous reader is used.
- **Pages.** `SpreadChapterView` is a `UIPageViewController` with a middle spine and double-sided page curl.
  - Each page is an ordinary `ChapterTextView`. Its `ChapterDocument` holds a slice of the chapter's verses (`ChapterDocument.page`) with the same chapter ID. Highlights, exact annotations, bookmarks, source notes, copy and share references, and VoiceOver verse actions therefore resolve unchanged.
  - The chapter's first page shows the full title; later pages show a small running head.
  - Chapters start on a left page; an odd page count ends with blank paper.
  - Turns cross into the neighboring chapter and commit through `ReaderState.commitTurn`. They never wrap past Genesis 1 or Revelation 22.
- **Page breaks** (`ChapterPagination`, pure and unit-tested). A hidden `ChapterTextView` in the page hierarchy lays out the whole chapter at page size with the same Dynamic Type traits and typography. Pages break between verses using the measured bottom of each verse. Headings travel with the verse they precede, and trailing source blocks stay on the last page or get their own.
  - A verse taller than a page gets its own page and scrolls within it.
  - Pagination is cached per chapter and recomputed when size, insets, typography, text size, or theme change.
  - Neighboring chapters are loaded and paginated ahead of a turn, one per main-actor turn.
- **Reading position.** After every turn, the reading anchor becomes the first verse of the left page. Rotating to portrait, switching to Scroll, or relaunching resumes there. Navigating to a verse (Search, Saved, summary sources) opens the spread containing it.
- **Interaction.**
  - Taps never turn pages. The curl begins only on a clearly horizontal drag, and is disabled while text is selected, saving, or navigating.
  - With Reduce Motion, Reduce Transparency, Increase Contrast, or VoiceOver, a discrete swipe turns without the curl.
  - VoiceOver's three-finger scroll turns pages and announces "John 3, pages 3 and 4 of 6".
  - ← and → key commands turn pages.

**Tradeoff (accepted by the owner).** A selection cannot cross the spine or a page break, because each page is its own text view. The continuous reader keeps cross-page selection, and it remains the default.

**Not verified.** Real-device curl feel; Psalm 119 pagination time on the slowest supported iPad; accessibility text sizes, where one verse can fill a page; hardware-keyboard arrow keys.

## Text size slider

At the owner's request, Appearance's *Text size* stepper is now a slider on iPhone and iPad. It has seven whole-number stops (−2…+4, each 2 points on top of Dynamic Type), smaller and larger text-size symbols at its ends, and a value such as "Default" or "+2" for VoiceOver. The stored value is unchanged.

## Validation added

- **Unit tests:**
  - `ChapterPaginationTests`: page breaks, a verse taller than a page, trailing blocks, a single-page chapter, and page documents that keep chapter identity and cover every verse once;
  - `ReaderPreferencesTests.pageLayoutPersistsAndOlderPayloadsReadAsScroll`.
- **iPad UI test** `testIPadTwoPageSpreadTurnsIntoNextChapterAndRestoresScroll`: enables Two Pages, checks that John 3 opens on a left page with its title, curls forward into John 4 and back to John 3's last spread, and checks that portrait resumes at that spread's first verse.
- **Test fix.** `testAboutShowsIdentityCreditsAndAttributions` now taps Back in the sheet's *Edition notice* bar. Once the compact layout used a plain `NavigationStack`, the reader's bar behind the sheet became the first navigation bar in the hierarchy, so the old query tapped Appearance instead.

## Crash fix: page curl with no pages (owner report, 27 September)

**The crash.** The owner hit `NSInvalidArgumentException: The number of view controllers provided (0) doesn't match the number required (2)` after swiping in Two Pages and then tapping a top-bar button. A middle-spine curl needs both pages of the destination spread. UIKit raised this when a finger-driven curl had to be abandoned without them.

**The two causes.**
- **Neighbor not ready.** A curl could begin while the neighboring chapter was still loading or paginating, so the data source returned no page.
- **Pan toggled mid-drag.** The curl pan could be toggled mid-drag, because the "turning" flag was only set when UIKit reported the transition, which happens after the pan begins. A toolbar tap that ended a text selection re-evaluated gestures and disabled the pan.

**The fix** (`SpreadChapterView`).
- A curl begins only when the destination spread is ready.
- A live curl counts from the moment its pan begins, when it goes to `.began` or `.changed`. Until it ends, gestures are never toggled and pages are never replaced, even for a layout change.
- `turn(by:)` shares the same readiness check.

**Validation.** `testIPadSpreadSurvivesRapidTurnsAndToolbarTaps` runs six rounds on Jude and 3 John, where most turns cross a chapter boundary. Each round has back and forward flicks, a partial drag that cancels, Saved/Read/Search tab switches, and opening and closing Appearance, and all six pass. XCUITest waits for the app to be idle before each tap, so it cannot tap in the middle of a finger's curl; the exact interleaving still needs a check on the owner's iPad.

**Remaining edge.** Rotating the device while a finger is mid-curl replaces the spread under UIKit. This is not reproduced and not fixed.

## Page and fold settings only where they apply (owner request, 27 September)

- **Landscape pages** (Two Pages) appears on iPad and on devices with a hinge. A phone never meets `ReaderLayout.supportsTwoPages`: that needs regular width and 840 points of usable width, and even a Pro Max in landscape falls short after its safe areas. It would be a dead control there.
- **Book layout when folded** appears only on devices with a hinge.
- **Hinge detection.** `HingeProbe` attaches UIKit's public `UIHingeInteraction` (iOS 27.1) at the app root and records whether the hierarchy provides a hinge. The app never checks a device model name or screen size. On iOS earlier than 27.1, fold settings stay hidden.
- **Footer.** The Pages section and its footer show only the sentences that apply to the device.
- **Tests.**
  - `testPhoneWithoutHingeHidesPageAndFoldSettings` (iPhone 18 Pro) and `testIPadShowsLandscapePagesButNotFoldSettings` (iPad Pro 13-inch) pass.
  - `testPagePreferenceRemainsAvailableInCompactLayoutAndPersists` now skips on phones without a hinge.
  - `testReaderChapterAndAppearanceRoundTrip` uses whichever tab control the layout shows, and passes on iPad.
  - UI tests identify the Duo simulator by the runner's `SIMULATOR_DEVICE_NAME`. That check is in the tests only, never in the app.
