# iPhone Duo adaptive reader

27 September 2026. Owner request: hypothesize useful Duo features, begin full-feature support with an iPad-like inner reader and landscape page swiping, test it, and update AGENTS.md.

## Design and SDK evidence

Apple's [Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/) describes regular size classes on the inner display, adaptive native bars, and asymmetric safe areas. [Strike a pose with adaptive layouts](https://developer.apple.com/videos/play/tech-talks/111463/) describes reserved division/occlusion regions and arrangements. These are API/design sources, not evidence that this app passes the corresponding device tests.

The owner's expanded Xcode reports **27.1 (27A9269)** and includes the iOS Simulator 27.1 SDK. Commands use a per-process `DEVELOPER_DIR`; the installed system Xcode is unchanged. The app retains minimum iOS 26.0.

## Feature hypotheses

1. **A pocket Bible that opens into facing pages.** Outer-display scrolling continues at the same passage on the inner display. The owner subsequently requested automatic facing-page swiping in the partially folded book pose. This now uses the public active division region, centers the native spread on the fold, and reserves an inner text margin. It temporarily overrides the flat-screen choice without changing it. Appearance has an enabled-by-default opt-out for continuous scrolling/selection.
2. **A source companion beside Scripture.** In a suitable folded arrangement, show the selected verse's existing source notes on the other region. Authoritative Scripture stays visually separate. This reuses sourced notes; it does not introduce commentary or generated Scripture. Proposed, not implemented.
3. **A stable reading surface in tabletop pose.** The initial implementation places the reader above an active horizontal division and chapter controls below it when both regions fit. The live horizontal-division UI test passed after rotating a partially folded Duo; a physical 90-degree tabletop review remains outstanding. An optional source-note companion remains a future proposal.

Continuity is the baseline requirement, not a reason to add a new mode or interrupt reading with a fold prompt. No new accounts, network services, telemetry, or corpus changes are needed.

## Initial implementation

- The existing regular-size-class system-tab layout already admits a regular-width phone. It retains all reader, Saved, Search, notes, annotation, appearance, and overview routes.
- Remove the `.pad` restriction from the page preference. It is also configurable while a foldable phone is closed, and persists normally.
- Replace the 960-point spread cutoff with a content policy: at least 420 points per page at default type, scaled with Dynamic Type, a landscape-shaped usable viewport, regular width, and enough vertical space. This is a provisional readability budget, not a hardcoded Duo screen dimension. Accessibility categories use the continuous reader.
- Keep the existing native page curl, verse-boundary pagination, semantic anchors, and independent local annotations. No storage or Scripture changes.
- On iOS 27.1, query active `GeometryProxy.reservedRegions(kind: .division)`, including their margins. Classify a vertical spanning division as book pose and a horizontal spanning division as tabletop. No model identifiers, guessed angles, or timer polling. Older systems return no fold layout.
- Book mode uses the actual division midpoint, accounting for asymmetric available space, and adds an inner margin to each native text page. The measuring view uses the same reduced text width as the visible pages. Automatic book mode falls back at accessibility text sizes or insufficient page width.
- Any scrolling fallback while a division is active (automatic book layout off, accessibility text, pages too narrow, or a tabletop split that does not fit) places the continuous reader in `ReaderFoldLayout.clearPane`: the larger side of a vertical division, or above a horizontal one whenever that side is at least 200 points or the larger side. Text never spans the division. Chapter controls remain in More and the passage selector. Added after the 27 September codebase audit; covered by layout unit tests, not yet by Device Hub pose transitions.
- Book pose has a separate 360-point default page budget (a narrower reading column plus gutter/margins), scaled with Dynamic Type. The first actual-pose test exposed that the 420-point flat-layout budget rejected usable book pages beside the native side toolbar. The observed layout had 371.5 points per page after fold clearance. These measurements are regression inputs, not device-name or screen-size detection.
- A persisted `automaticBookLayout` option defaults to true when absent from an older preference payload; it does not reset any existing appearance values. No user-database migration.

## Acceptance still required

Actual Duo flat/partially-folded/outer-display transitions; live reserved-region treatment around the fold and camera; system tab and toolbar placement; interrupted curl and selection restoration; Split View; keyboard and largest type; reduced motion/transparency; first-launch offline flows; and physical-device feel/performance. Facing-page selections remain limited to one page, so scrolling is required for selections across page boundaries.

Do not infer fold-readiness from a build, an iPad rotation, or a synthetic window-size test. See the [validation record](../Validation/duo/README.md) for passing runs, tooling failures, and remaining checks.
