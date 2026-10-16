# Developer tips — validation, 13 October 2026

Xcode 27.1 from `/Users/kyle/Downloads/Xcode.app` was selected per process. Deployment remains iOS/iPadOS 26.0. Simulators ran iOS 27.0. Builds used isolated `/private/tmp/BibleTipsDerivedData` and `BibleTipsReleaseDerivedData` directories.

## Passing checks

- Debug app, unit-test, and UI-test targets compiled; the final Release app build passed. No compiler warnings were emitted in these runs.
- iPhone 18 Pro: **7 passed**, 0 failed, 0 skipped. Four model tests cover cancellation, pending approval, verification failure, load/purchase errors and retry, missing products, restricted payments, duplicate taps, and delayed completion. The real local StoreKit test verifies prices/IDs, two consumable purchases, an empty unfinished queue, and Ask to Buy approval. Two UI tests exercise support navigation, repeated tips, return to reading, dark appearance, largest Dynamic Type, and rotation.
- iPad mini (A17 Pro): **2 UI tests passed**, 0 failed, 0 skipped, covering the same purchase flow and accessibility-size/rotation checks.
- Standard BibleReader scheme: **5 passed**, 0 failed; **1 intentionally skipped**. The four model tests and existing About/attribution regression pass without local purchase configuration. The StoreKit integration test requires the separate BibleReader-Tips scheme.
- `git diff --check` passed. Unrelated reader/pagination work was preserved.

Result bundles on this machine: `/private/tmp/BibleTips-Phone-Final.xcresult`, `/private/tmp/BibleTips-iPad-Final.xcresult`, `/private/tmp/BibleTips-NormalScheme.xcresult`. These temporary bundles may be removed by the OS; the screenshots below are retained in the repository.

## Screenshots

- [iPhone tip screen](iphone-tip-screen.png), [thank-you](iphone-thanks.png), [largest text in dark landscape](iphone-large-text-landscape.png).
- [iPad tip screen](ipad-tip-screen.png), [thank-you](ipad-thanks.png), [largest text in dark landscape](ipad-large-text-landscape.png).

These are unedited screenshots of the running app with local StoreKit products at their US reference prices. The iPhone tip-screen image can be used for the in-app purchase review screenshot.

## Reproduce

Use the **BibleReader-Tips** scheme for local purchase tests. The standard **BibleReader** Run action retains its Release configuration and uses the actual App Store. StoreKitTesting assets belong only to test targets.

```sh
DEVELOPER_DIR=/Users/kyle/Downloads/Xcode.app/Contents/Developer xcodebuildmcp simulator test --project-path /Users/kyle/Developer/bible-ios/BibleReader.xcodeproj --scheme BibleReader-Tips --configuration Debug --simulator-id 0287C297-095D-4DD5-9C38-652D88A0ECCD --derived-data-path /private/tmp/BibleTipsDerivedData --extra-args '-only-testing:BibleReaderTests/TipStoreTests' '-only-testing:BibleReaderTests/StoreKitTipTests' '-only-testing:BibleReaderUITests/TipJarUITests' '-parallel-testing-enabled' 'NO'
```

For iPad, use simulator `65528EB0-E400-43C0-8106-3821BE46A0B9` and select `BibleReaderUITests/TipJarUITests`.

## Transaction reconciliation

A temporary direct Apple-API probe reproduced a local StoreKit behaviour: the second consumable remained in `Transaction.unfinished` after `finish()` returned, and finishing the fresh record from that sequence cleared it. The production client therefore reconciles unfinished records after a successful purchase as well as at launch. The regression asserts the queue becomes empty; it does not clear transactions to satisfy that assertion. The temporary diagnostic was removed.

Physical-device sandbox/TestFlight, live App Store availability, manual split-window resizing, and App Review were not tested. Review screenshots still need to be attached in App Store Connect, and the initial purchases must be submitted with the first app version. See [release follow-up](../../Decisions/0021-optional-developer-tips.md).

## Audit fixes — 13 October 2026

- **Interrupted product load.** Loading ran inside the screen's `.task`; backing out mid-load and reopening hit the in-progress guard, and the cancelled load then discarded its result, leaving "Tips are unavailable" until Try Again. TipStore now owns the load, and a reopened screen joins it.
- **Unexplained background warnings.** Unverified transactions stay unfinished and are redelivered at each launch, which set the "could not be verified" message without any user action. Background deliveries (delayed approval, launch recovery) now only report a completed tip; verification warnings appear only for a purchase the person just made.
- **Persistent status.** The app-lived store kept "Thank you" or a failure message on every later visit. Finished outcomes now clear when the screen closes; a pending Ask to Buy message remains until resolved.
- Duplicate product IDs from StoreKit no longer trap when building the product lookup.
- **HIG/consistency.** Removed the intro card and repeated "free / unlocks nothing" copy; the intro now matches About's plain on-canvas header, and the explanation lives in one section footer. The status row sits with the tip choices with an accent-colored symbol, the form uses the app accent tint and About's icon-only Close button, the loading row no longer flashes under already-loaded tips, and Try Again carries a symbol.
- TipJarUITests resets the simulator to portrait before launch; a previously failed rotation test left the simulator in landscape and caused later runs to fail before reaching tips.

iPhone 18 Pro, BibleReader-Tips scheme: **9 passed**, 0 failed, 0 skipped, no warnings (six TipStore model tests, including new load-join and background-message tests; the StoreKit integration test; both UI tests). The iPhone screenshots above were replaced from this run. The iPad screenshots predate this layout change and were not re-run.
