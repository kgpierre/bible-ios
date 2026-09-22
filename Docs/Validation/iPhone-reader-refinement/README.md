# iPhone reader interaction evidence

22 September 2026. Xcode 27.0 (27A266a), iPhone 18 Pro simulator, iOS 27.0. Exported from `.build/Reader-refinement-final.xcresult`; visually inspected after its 35 non-UI and four UI tests passed. Tests use isolated local stores.

- [Short-press selection and swatches](selection-swatches.png)
- [Selected swatch checkmark](selected-swatch.png)
- [Native tabs beside chapter and Books](native-tabs.png)
- [Completed chapter turn](chapter-turn.png)
- [Chapter retained after a short edge drag](cancelled-turn.png)

The chapter-turn image shows the settled destination, not animation frame pacing. These are simulator captures, not physical-phone performance evidence. See [decision 0007](../../Decisions/0007-iphone-reader-interactions.md) for implementation and limitations.
