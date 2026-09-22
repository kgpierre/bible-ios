# Repository Guidelines

## Platform & Organization

- Target iOS/iPadOS 27 unless compatibility requirements specify otherwise. Use Swift 6 and SwiftUI; prefer native Apple frameworks.
- Verify API availability against the deployment target. Add availability checks and fallbacks only when supporting older systems.
- Organize source by feature, with focused shared components. Document actual setup, build, and test commands once the Xcode project exists.

## Architecture & Concurrency

- Keep views small and composable. Separate domain and persistent state from presentation state; introduce abstractions only for concrete needs.
- Prefer `@Observable`; use `@State` for ownership, `@Binding`/`@Bindable` for editing, and explicit dependency injection. Keep state at the narrowest appropriate scope.
- Use structured concurrency, cancellation-aware `.task`, and `@MainActor` for UI-bound mutable state. Keep expensive work off the main actor and out of `body`.
- Use stable model identities and explicit loading, empty, and error states.

## Liquid Glass & Adaptive Navigation

- Follow Apple’s Human Interface Guidelines. Prefer system navigation bars, toolbars, sheets, and controls, which adopt Liquid Glass automatically on supported systems.
- Reserve glass for navigation and controls; keep scripture and other reading content on legible surfaces. Avoid simulated glass using stacked blurs or opaque backgrounds that obscure system effects.
- For custom controls, use `glassEffect`, glass button styles, and `GlassEffectContainer` for related glass elements. Apply effects after layout modifiers.
- Use `TabView` with `Tab` and `.tabViewStyle(.sidebarAdaptable)` for top-level navigation: iPad supports a top tab bar that adapts into a sidebar. Let the system handle placement and transitions.
- Preserve selection and per-tab navigation history. Use `NavigationStack` for drill-down and `NavigationSplitView` for genuine multicolumn content.
- Support resizable iPad windows, compact layouts, keyboard, and pointer input. Avoid device-size checks and hard-coded screen dimensions.

## Accessibility & Reading

- Support Dynamic Type, VoiceOver, light/dark appearances, Reduce Motion, and Reduce Transparency.
- Use semantic colors, accessible control labels, adequate touch targets, and localized strings. Prioritize readable scripture typography.

## Development & Testing

- Inspect existing code, plan briefly, and implement the smallest coherent change.
- Build, fix introduced warnings/errors, and run relevant tests. For UI changes, launch and inspect iPhone and iPad simulators, including resized layouts.
- Prefer Swift Testing for domain logic and XCTest/XCUITest for interaction flows. Never weaken tests to pass.
- Report validation honestly; disclose blocked builds.

## Git & Content

- Keep commits focused with imperative subjects. Include PR context, validation, and screenshots for UI changes.
- Never commit secrets. Document Bible translation and asset licenses.
