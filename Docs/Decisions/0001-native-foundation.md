# 0001 — Native foundation

Status: implemented for development, 21 September 2026.

## Scope

Step 1 establishes the Xcode application, test targets, design tokens, and presentation-state ownership. It does not implement the 2a reader, corpus pipeline, annotations, search, or adaptive navigation prototype.

## Decisions

- Use Xcode 27.0 (27A266a), Swift 6 language mode, and complete concurrency checking. Default actor isolation remains nonisolated; UI-owned reference state is explicitly `@MainActor`.
- Set the proposed minimum to iOS/iPadOS 26.0 for all targets. Final release compatibility remains an owner decision.
- Use one application target and shared `BibleReader` scheme, with Swift Testing and XCUITest targets. No external dependencies or storage framework yet.
- `AppRootView` owns `AppState` with `@State`. A theme binding is passed directly to the Appearance sheet. This is in-memory presentation state; durable appearance preferences are deferred.
- Disable multiple application scenes explicitly while preserving iPad orientation and resizing support.
- Import the supplied light/dark palette into semantic asset colors. Typography uses system fonts and `@ScaledMetric`, not fixed line heights or bundled fonts.
- Keep the entire design export outside application target membership. No sample Scripture from that export is packaged as content.
- Show an explicit missing-content state until a vetted corpus exists. This is a development foundation, not the intended first-launch experience or an approved replacement for 2a.
- Keep native navigation and controls for the foundation. Step 2 must separately prove the adjacent passage capsule, native text selection, and wide/narrow iPad navigation. This foundation does not settle that container decision.
- Use temporary bundle identifier `org.example.BibleReader` and no signing team. Assign actual ownership before device distribution or publication.

## Validation

See README for reproducible commands and the recorded validation matrix. Store disposable build products, results, and screenshots under ignored `.build/`. Native device, corpus, privacy, and release acceptance remain outstanding.
