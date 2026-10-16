# 0021 — Optional developer tips

Date: 13 October 2026
Status: Implemented; App Store release and device sandbox acceptance remain pending.

## Owner decision

Support goes to Kyle Pierre for developing the app. Every reading feature remains free. Tips are optional, repeatable one-time consumable in-app purchases; they grant no entitlement and are not subscriptions or charitable donations. The owner approved three US price points: $0.99, $2.99, and $4.99.

The App Store listing is **Bible — Quiet KJV** (Apple ID `6821789204`), while the installed app still displays **Bible**. Bundle ID remains `dev.kpierre.bible`.

## Products and flow

More → About Bible → Support Development opens the tip screen:

- Small Tip: `dev.kpierre.bible.tip.small`, US reference price $0.99.
- Medium Tip: `dev.kpierre.bible.tip.medium`, US reference price $2.99.
- Large Tip: `dev.kpierre.bible.tip.large`, US reference price $4.99.

The app requests these exact IDs from StoreKit only when support is opened. Display names and formatted prices come from Apple, including the current storefront currency. No hardcoded production price or external donation link is used. An unavailable store, connection, or payment restriction does not affect reading.

An app-owned TipStore survives dismissal of About. StoreKitTipClient verifies purchases before finishing their transactions, listens for delayed approvals, and recovers unfinished transactions at launch. Verified redeliveries are acknowledged again without granting any entitlement. After a successful purchase, the client also reconciles StoreKit’s latest unfinished records. Cancellation is quiet; pending approval, purchase failure, and verification failure have distinct messages. Background deliveries only thank; verification warnings are reserved for a purchase just made. Messages clear when the screen closes, including the awaiting-approval notice (a declined Ask to Buy delivers no transaction, so keeping it would leave a stale notice); a later approval still arrives through the app-lived listener and thanks. Product loading is owned by TipStore so leaving mid-load cannot discard it. No tip entitlement, user account, purchase analytics, or new server is introduced. Consumable tips have nothing to restore.

Unlike product loading, transaction observation is not deferred until support is opened: the app-owned TipStore starts `Transaction.updates` and a `Transaction.unfinished` scan at every launch, including launches that never visit About. The offline network capture required by AGENTS §12 must therefore account for any StoreKit daemon traffic at launch, attribute it to the system rather than the app, and confirm that core reading flows issue no app-originated requests. Record the result before release; it has not yet been captured.

## Local testing

`StoreKitTesting/BibleTips.storekit` contains the three consumables and is bundled only into the test targets. **BibleReader-Tips** is a separate Debug scheme for manual simulated purchases; the owner's standard **BibleReader** scheme retains its existing Release Run setting and real App Store configuration. Select BibleReader-Tips in Xcode to exercise the system purchase sheet without real charges. Disable its StoreKit configuration or use BibleReader for App Store sandbox testing.

The StoreKit integration and UI tests opt in through `BIBLE_LOCAL_STOREKIT_TESTS=1`, which the BibleReader-Tips scheme supplies. They intentionally skip under the normal scheme; the pure model tests run in either scheme. UI tests launch the app before configuring StoreKit so a fresh simulator can register the app first.

TipStoreTests cover cancellation, pending and unverified outcomes, clearing a declined Ask to Buy notice, errors and retry, missing products, restrictions, repeated tips, simultaneous taps, and delayed approvals. StoreKitTipTests exercises actual local StoreKit products, finishing repeat consumables, and Ask to Buy approval. TipJarUITests covers the About route, real simulated purchases, closing back to the free reader, dark appearance, largest text, and rotation.

## Validation

Debug and Release builds passed. Seven focused tests passed on iPhone 18 Pro; both UI flows passed on iPad mini. The normal scheme passed four model tests plus the About regression, with the StoreKit integration test intentionally skipped. See [results and screenshots](../Validation/tips/README.md). These were local simulated purchases, not sandbox or production transactions.

## Release follow-up

The products were saved in App Store Connect as drafts, available in 174 regions with the United Kingdom excluded. Future regions are not added automatically. Prices are equalized from the US reference prices. At portal setup, the W-9 was active and banking changes were processing; confirm the Paid Apps Agreement is active before sandbox acceptance.

Before release: test the real configured products on a physical device through Apple's sandbox/TestFlight, attach a support-screen review screenshot to each product, submit the initial purchases with the first app version, and finish the app's free pricing, territory settings (excluding the UK), metadata, and review. Local tests do not establish approval or live product availability.

References: [Apple transaction updates](https://developer.apple.com/documentation/storekit/transaction/updates), [unfinished transactions](https://developer.apple.com/documentation/storekit/transaction/unfinished), and [StoreKit testing](https://developer.apple.com/documentation/storekittest/sktestsession).
