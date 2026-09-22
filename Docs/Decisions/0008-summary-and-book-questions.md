# Summary sheet and book-scoped questions

22 September 2026. The owner requested larger serif text, a visible overview question, book-scoped follow-up questions, and subsequently supplied the 4a/4b summary/questions reference. This explicitly extends the previous overview-only AI scope. The owner selected **current chapter and book**, not the whole Bible.

## Presentation

The sheet follows the supplied layout with native Summary/Questions chrome, a captured chapter subtitle, paper canvas, scalable reader serif typography, and a bounded reading column. The default overview question remains visible above generated text. An optional generated title and people/place labels decorate successful overviews; names absent from the captured source text and duplicate labels are discarded. These are AI-generated labels, never new Scripture headings.

Questions appear as tinted bubbles; answers remain directly on the page. Validated reference chips open the actual bundled verse in the reader. The last twelve successful exchanges live only in the sheet. The previous accepted question may clarify a follow-up; generated answers are not recycled into the next model context. Back preserves the sheet session; dismissal discards it. Failed/rejected/cancelled questions stay editable.

The bottom input uses iOS 26 `safeAreaBar`, native soft scroll-edge treatment, and `glassEffect(.regular.interactive())` after layout. Suggestions use native glass button styles inside the same `GlassEffectContainer`. There are no custom blur/shadow stacks or glass backgrounds behind the reading content. Reduce Transparency adds an opaque semantic canvas beneath the native effect. At accessibility sizes suggestions remain reachable through a native menu; the input grows vertically and icons retain a 44-point target. Reference/name chips wrap without shrinking text.

## Scope and grounding boundaries

- The book identity is captured from the reader. A bound SQL query retrieves only that book's immutable verse records. Deterministic lexical ranking selects at most 24 complete verses and 6,500 source characters. This is not semantic retrieval; missed sources produce an insufficient-evidence response. Questions explicitly saying “this chapter” further restrict evidence to that chapter.
- User questions are limited to 400 characters and encoded as JSON data, never inserted into trusted model instructions. The preceding accepted question is separately bounded to 400 characters.
- A fresh guided assessment classifies the request before retrieval/generation. It rejects unrelated topics, other books, personal advice, instruction overrides, prompt disclosure, and mixed requests.
- A fresh guided answer session receives only the question data and selected passages. App code requires nonempty bounded text and one to six source IDs that actually occur in the supplied passages. Wrong-book sources and invented source IDs fail closed.
- Another independent session checks the proposed answer against its cited passages before display. Questions outside scope and unsupported answers use fixed app messages. References and navigation targets come from the corpus, not generated strings or URLs.
- All sessions explicitly use `SystemLanguageModel.default` and Apple's default guardrails. No tools, remote fallback, app action execution, user annotations, clipboard, or filesystem access is exposed to the model. There is no prompt/output logging or persistence.

### Whole-book key-verse questions

The owner reported a false rejection of “What are some key verses in this book?” Exact normalized forms of that bounded, unambiguously textual request are now admitted directly; appended instructions do not match. Other free-form requests still use guided scope assessment, with explicit examples for key verses and whole-book themes. The answer/review instructions allow an interpretive selection of useful passages without asserting an authoritative ranking.

Whole-book questions can ask the model for up to six chapter/single-verse locators. These are retrieval suggestions, not evidence or executable tools. The repository resolves them only against the captured book's actual bundled rows, discards nonexistent locators, and prioritizes those verified passages within the existing 24-verse/6,500-character bound. This fixes the earlier lexical-only fallback that could limit broad questions to the open chapter. For the exact admitted key-verse requests, the app displays a fixed introduction followed by those verified corpus quotations and tappable references; the model selects locations but writes none of the displayed verse text. This path needs neither a generated prose answer nor a stochastic support review of fixed app copy. Other generated answers still require corpus-backed IDs and a separate support review. Preferred-only retrieval binds the nominated chapter/verse labels directly in SQL, avoiding a full-book fetch. No generated text becomes Scripture.

These are risk-reduction measures, **not a guarantee against prompt injection or factual errors**. Model-based classification and review can both make mistakes, including false refusals. Supported citations do not establish that every claim is correct. Broader adversarial and physical-device model-quality testing remains release work. Apple's unavailable/refusal states are surfaced; model setup remains an OS prerequisite.

Chapter overview generation retains bounded chunk/reduction behavior and context-limit retries. Optional presentation generation cannot turn a completed overview into a failure. Cancellation/request identity prevents late results from overwriting cancelled or newer work.

## Primary APIs checked

- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
- [Native safe-area bars](https://developer.apple.com/documentation/swiftui/view/safeareabar(edge:alignment:spacing:content:))
- [Scroll-edge effects](https://developer.apple.com/documentation/swiftui/view/scrolledgeeffectstyle(_:for:))
- [Guided generation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation)
- [Model-output safety](https://developer.apple.com/documentation/FoundationModels/improving-the-safety-of-generative-model-output)

The installed Xcode 27 SDK confirms `safeAreaBar` availability starting at iOS 26. No unnecessary lower-OS fallback is added below this project's deployment target.

## Validation

[Native screenshots and exact result inventory](../Validation/summary-redesign/README.md). The final iPhone run passed 44 non-UI tests and three UI flows; the subsequent vertical alignment fix passed two focused UI tests and the unsigned Release device build. The iPadOS 26 native-bar/refusal/large-type run passed 43 non-UI tests and two UI flows before the final small refinements noted in the inventory. A real iOS 27 model summary and supported answer were observed, an unrelated override request was rejected, and a source chip opened the reader. The iPad model declined the valid question, which remained editable. Physical-device model-quality and broader adversarial testing remain open.

Follow-up validation and the real key-verse answer are recorded in [reader follow-ups](../Validation/reader-followups/README.md).
