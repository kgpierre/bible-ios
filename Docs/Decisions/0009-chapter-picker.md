# Chapter picker — owner’s updated frame

22 September 2026. The owner supplied the 5a/5b light/dark chapter picker and requested native Liquid Glass. This supersedes the earlier 2b plain chapter-number styling.

The existing SwiftUI navigation and reference parser remain. Chapters use a scalable 60-point circular control in an adaptive grid (five columns at default compact size), system serif numerals, accent fill for the open chapter, and actual saved-highlight indicators. The gold ring plus dot does not depend on color alone; accessibility exposes “Has highlights” and the selected trait. Bookmarks alone do not produce a highlight ring. The book eyebrow follows the existing editorial metadata convention, never generated Scripture.

The book title is the reader’s 40-point scalable serif. The count shares its baseline where space permits and moves below at larger text sizes. The grid, status, legend, and reference entry scroll together; Psalms and large text remain reachable. The dark sheet uses the owner’s proposed #1E201E. The light marker is a darker gold for visibility on paper; dark uses a lighter gold.

Books/Done are system toolbar controls. Chapter controls use public `glassEffect(.regular.interactive(), in: .circle)` inside `GlassEffectContainer`, after their layout and semantic fill. Text and markers are part of the glass content, not separately composited above its effect. The reference field uses a native capsule effect and a 44-point submit target. No custom blur or shadow stacks are used. Reduce Transparency adds an opaque semantic background. A valid reference opens through the existing parser; invalid inputs and explicit typo suggestions remain actionable.

The native effect’s exact tint/shadow follows the OS rather than copying the mockup’s simulated glass. System safe areas, toolbar sizing, sheets, and iPad popovers determine presentation.

[Inspected screenshots and validation](../Validation/chapter-picker/README.md).
