# Chapter picker validation

22 September 2026 · Xcode 27.0 (27A266a), Swift 6.4 · deployment iOS/iPadOS 26.0.

Inspected native screenshots:

- [iPhone light](light.png), [iPhone dark](dark.png): iPhone 17 Pro, iOS 26.0, `.build/Audit-final-ios26.xcresult`. John 3’s ring/dot comes from an exact-word highlight created by the test; John 14 is the actual current chapter.
- [iPad largest text with Done](largest-type.png): iPad mini (A17 Pro), iPadOS 26.0, `Reader-followups-ipad`; the Done button dismissed the pushed chapter picker successfully.
- [iPad popover](ipad.png): iPad mini (A17 Pro), iPadOS 26.0, `.build/Audit-picker-ipad.xcresult`. The reference field remains reachable by scrolling inside the system popover.

`Audit-final-ios26` passed 51 non-UI tests and three UI flows (chapter picker, largest-type dark Books/Chapters, exact-word recolor/removal/Undo). The iPad picker/light/dark, largest-type, and portrait/landscape restoration cases passed in `Audit-picker-ipad`; that batch’s additional live-Saved test failed on sidebar hit testing and is not a full passing batch. See the follow-up inventory for its correction and final checks.

The native effect is rendered by the OS. No HTML mockup, custom blur/shadow stack, simulated device chrome, or synthetic highlight state was used. The picker uses system toolbar controls plus public custom-glass APIs. Accessibility sizing, selected traits, highlight labels, and reference parser behavior are retained. Physical-device glass appearance and the wider accessibility matrix remain release checks.

Implementation: [decision 0009](../../Decisions/0009-chapter-picker.md). Full follow-up evidence: [reader follow-ups](../reader-followups/README.md).
