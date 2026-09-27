# Release identity, minimum OS, and Scripture rights — 26 September 2026

The owner made these decisions on 26 September 2026 and delegated the rights and canon review ("review this and solve for me"). This record separates owner decisions from engineering findings. It is an engineering rights review, not legal advice.

## Owner decisions

| Decision | Value | Where it applies |
| --- | --- | --- |
| Minimum OS | iOS and iPadOS **26.0** | Already the deployment target of every target; no availability branches added. |
| App name | **Bible** | `CFBundleDisplayName` and About. The Xcode target, scheme, and module stay `BibleReader` (internal names only). |
| Bundle ID | **dev.kpierre.bible** | App target. Tests use `dev.kpierre.bible.tests` and `dev.kpierre.bible.uitests`; the signpost subsystem is `dev.kpierre.bible`. |
| Signing team | `AVER2M3454` (owner-configured on the app target) | Also set on both test targets so tests can run on the owner's devices. No certificates or profiles are stored in the repository. |

Changing the bundle ID gives the app a new data container. Earlier development installs (`org.example.BibleReader`) keep their own local highlights and positions. They are not migrated, and the new app starts at Genesis 1. Delete the old development app only once nothing in it is needed.

## Scripture rights review

**Source.** The corpus is eBible.org's `eng-kjv` USFX archive, pinned by SHA-256 `6d834ebe…bb6fb` and retrieved 21 September 2026: the King James Version, standardized 1769 text. The provider notice bundled in `Content/Source/copr.htm` says: "Public Domain … You may copy the King James Version of the Holy Bible freely." It credits CrossWire Bible Society and eBible.org. The notice sets no conditions beyond that credit, which the app already gives in About.

**Outside the United Kingdom.** The text is in the public domain. The 1769 standardization is also long out of copyright. The eBible.org archive does not add a license to the Bible text itself. No permission is needed.

**United Kingdom.** Rights in the Authorized Version are vested in the Crown under Letters Patent with no expiry. Cambridge University Press administers them as the Crown's patentee, for England, Wales, and Northern Ireland. Cambridge's published allowance is for quotations: up to 500 verses for liturgical and non-commercial educational use, with attribution, and not a complete book. A complete Bible reader exceeds that allowance, and Cambridge's terms say nothing about apps. Distributing in the UK therefore needs written permission from Cambridge's Bible permissions department. The App Store's United Kingdom storefront covers all of the UK, including Scotland, so it cannot serve only the regions outside the patent.

**Decision.** Release worldwide **except the United Kingdom storefront**. The storefront is configured in App Store Connect under Pricing and Availability, not in code, and the manifest records it as `distribution.excludedStorefronts: ["GBR"]`. UK availability can be added later if Cambridge grants permission; that needs no code or corpus change. Only the notice text would gain Cambridge's required attribution line.

**Other obligations.**

- Keep the attribution in About: "King James Version (standardized 1769 source), provided by CrossWire Bible Society and eBible.org." This is already bundled.
- Do not describe the text as edited or corrected. The importer preserves wording and the added-word italics, which matches the source.
- The on-device overview is AI-generated commentary, labeled as such and kept separate from Scripture. It raises no rights issue for the text.
- Source notes are the 1611 translators' marginal notes from the same public-domain archive.

**User-facing notice.** `EditionNotice.txt` previously showed users the internal line "Unresolved; do not publish until edition, canon, and territories are reviewed." It now says: "The King James Version is in the public domain outside the United Kingdom. In the United Kingdom, rights in the Authorized Version are vested in the Crown; this app is not distributed there." The importer generates this text (`Content/Tools/build_corpus.py`). The rebuilt `BibleCorpus.sqlite` is byte-identical to the previous file. The logical revision is unchanged (`221de95d…`) and `validate_corpus.py` passes 9 of 9. Only `CorpusManifest.json` and `EditionNotice.txt` changed. The manifest's `schemaVersion` now correctly says 2, matching the database's `user_version`.

## Canon

Under the owner's delegation, the **66-book Protestant canon** is adopted for v1, with the Apocrypha and preface excluded as the manifest lists. This matches "KJV" as most readers expect it. It also matches the planned iPhone navigation (Old/New Testament) and the corpus validation that already covers first and last books. The source archive retains the excluded books, so adding an Apocrypha edition later would be a separate edition ID, not a change to this one. The owner can revisit this decision; it needs no code change now.

## App icon

**Done 27 September 2026.** The owner added `BibleReader/Resources/Bible.icon`: an Icon Composer document with glow, page, page-edge, shadow, and cover layers. `ASSETCATALOG_COMPILER_APPICON_NAME` is now `Bible`, and the flattened `AppIcon.appiconset` was removed; `AboutIcon` stays. An unsigned Release build succeeded, and its `Assets.car` contains the layered `Bible` icon with its dark variant. The steps used are kept below for reference.

1. In Icon Composer, choose **File → Save** (⌘S). The document is saved as a `.icon` package, such as `AppIcon.icon`. Exporting PNGs does not save it; if it was never saved, save it now.
2. Put it at `BibleReader/Resources/AppIcon.icon` (Finder is fine; the synchronized group picks it up), or drag it into Xcode's project navigator with the BibleReader target checked.
3. The app's **App Icon** build setting (`ASSETCATALOG_COMPILER_APPICON_NAME`) is already `AppIcon`, so a file named `AppIcon.icon` is used automatically. Then remove the flattened `AppIcon.appiconset` from `Assets.xcassets` so only one icon source has that name. Keep the `AboutIcon` image set, which About uses.

The deployment target is 26.0, so no fallback icon set is needed.

## Still open

- App Store Connect: set the availability to exclude the United Kingdom, and complete the privacy answers ("Data Not Collected", which matches the bundled privacy manifest).
- Donation link: `AppInfo.donationURL` is still `nil`. Guideline 3.1.1 allows an external donation link only for approved nonprofits; otherwise donations must use in-app purchase. Choose before enabling the button.
- The owner's review of the compact Saved controls (0016) and the Appearance layout.
