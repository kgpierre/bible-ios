import SwiftUI
import UIKit

struct NativeChapterView: UIViewRepresentable {
    let document: ChapterDocument
    let state: ReaderState
    let wide: Bool
    var chromeInsets = EdgeInsets()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicType

    func makeUIView(context: Context) -> ChapterTextView {
        ChapterTextView()
    }

    func updateUIView(_ view: ChapterTextView, context: Context) {
        view.chromeInsets = chromeInsets
        view.configure(document: document, state: state, wide: wide, scheme: colorScheme)
    }

    static func dismantleUIView(_ view: ChapterTextView, coordinator: ()) {
        view.capturePosition()
        view.resignFirstResponder()
    }
}

/// A single TextKit 2 document. Never access `layoutManager`: that switches UITextView to TextKit 1.
@MainActor
final class ChapterTextView: UITextView, UITextViewDelegate {
    private(set) var map: ChapterTextMap?
    private var document: ChapterDocument?
    private weak var readerState: ReaderState?
    var chromeInsets = EdgeInsets() {
        didSet {
            guard chromeInsets != oldValue else { return }
            needsAnchorRestore = true
            setNeedsLayout()
        }
    }
    private var wide = false
    private var lastWidth: CGFloat = 0
    private var lastCategory: UIContentSizeCategory?
    private var lastTypography = ReadingTypography()
    private var lastScheme: ColorScheme?
    private var lastRevision = -1
    private var appliedBookmarks: Set<String> = []
    private var bookmarkIndicators: [String: UIImageView] = [:]
    private var accessibilityNeedsUpdate = true
    private var appliedExact: [ExactAnnotation] = []
    private var appliedCue: Set<String> = []
    private var appliedHighlights: [String: HighlightColor] = [:]
    private var applying = false
    private var needsAnchorRestore = false
    private var needsSelectionFocusRestore = false
    private let header = UIStackView()
    private let eyebrow = UILabel()
    private let bookTitle = UILabel()
    private let chapterTitle = UILabel()
    private var gutterLabels: [String: UILabel] = [:]
    private var verseAccessibility: [UIAccessibilityElement] = []
    private let chapterContent: NSTextContentStorage
    private var gutterWidth: CGFloat { wide ? 40 : 36 }

    init() {
        // Explicitly assemble TextKit 2. The inherited ObjC convenience initializer can
        // bypass a Swift subclass's designated initializer and stored-property setup.
        let content = NSTextContentStorage()
        let layout = NSTextLayoutManager()
        let container = NSTextContainer(size: .zero)
        content.addTextLayoutManager(layout)
        layout.textContainer = container
        chapterContent = content
        super.init(frame: .zero, textContainer: container)
        isEditable = false
        isSelectable = true
        backgroundColor = .clear
        self.textContainer.lineFragmentPadding = 0
        alwaysBounceVertical = true
        contentInsetAdjustmentBehavior = .never
        delegate = self
        accessibilityIdentifier = "chapterText"
        // Preserve the native selection interaction; custom verse accessibility is installed only for VoiceOver.
        header.axis = .vertical
        header.spacing = 6
        [eyebrow, bookTitle, chapterTitle].forEach {
            $0.numberOfLines = 0
            header.addArrangedSubview($0)
        }
        bookTitle.accessibilityTraits = .header
        addSubview(header)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: ChapterTextView, _) in
            guard let document = view.document, let state = view.readerState else { return }
            view.configure(document: document, state: state, wide: view.wide, scheme: view.lastScheme ?? .light)
        }
    }

    required init?(coder: NSCoder) { fatalError("Use the native reader initializer") }

    func configure(document: ChapterDocument, state: ReaderState, wide: Bool, scheme: ColorScheme) {
        if self.document == nil, state.selection != nil { needsSelectionFocusRestore = true }
        let changedChapter = self.document?.id != document.id || lastRevision != state.navigationRevision
        let changedStyle = self.wide != wide || lastCategory != traitCollection.preferredContentSizeCategory || lastScheme != scheme || lastTypography != state.typography
        self.readerState = state
        guard changedChapter || changedStyle || appliedHighlights != state.highlights || appliedBookmarks != state.bookmarks || appliedCue != state.navigationCue || appliedExact != state.exactAnnotations else { return }
        if !changedChapter { capturePosition() }
        accessibilityNeedsUpdate = true
        applying = true
        defer { applying = false }
        self.document = document
        self.wide = wide
        lastCategory = traitCollection.preferredContentSizeCategory
        lastScheme = scheme
        lastTypography = state.typography
        lastRevision = state.navigationRevision
        overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        backgroundColor = UIColor(resource: .readingCanvas)
        tintColor = UIColor(resource: .accent)
        if changedChapter || changedStyle {
            let map = ChapterTextMap(document: document)
            self.map = map
            let string = NSMutableAttributedString(string: map.text)
            let font = scaledFont(size: (wide ? 24 : 22) + state.typography.pointAdjustment, style: .body, serif: state.typography.face == .serif)
            let paragraph = NSMutableParagraphStyle()
            paragraph.baseWritingDirection = .leftToRight
            paragraph.lineSpacing = UIFontMetrics(forTextStyle: .body).scaledValue(for: (wide ? 6 : 5) + state.typography.spacing.extraPoints, compatibleWith: traitCollection)
            paragraph.paragraphSpacing = 6
            string.addAttributes([.font: font, .foregroundColor: UIColor(resource: .readingPrimary), .paragraphStyle: paragraph], range: NSRange(location: 0, length: string.length))
            for range in map.sourceHeadingRanges {
                string.addAttributes([.font: scaledFont(size: 16 + state.typography.pointAdjustment, style: .subheadline, serif: state.typography.face == .serif), .foregroundColor: UIColor(resource: .readingSecondary)], range: range)
            }
            for entry in map.entries {
                var offset = entry.range.location
                for run in entry.verse.runs {
                    if run.italic, let descriptor = font.fontDescriptor.withSymbolicTraits(.traitItalic) {
                        string.addAttribute(.font, value: UIFont(descriptor: descriptor, size: font.pointSize), range: NSRange(location: offset, length: run.text.utf16.count))
                    }
                    offset += run.text.utf16.count
                }
            }
            attributedText = string
            eyebrow.text = document.eyebrow
            eyebrow.font = scaledFont(size: wide ? 14 : 13, style: .caption1, weight: .semibold)
            eyebrow.textColor = UIColor(resource: .readingSecondary)
            bookTitle.text = document.bookName
            bookTitle.font = scaledFont(size: wide ? 46 : 40, style: .largeTitle, serif: true, weight: .semibold)
            bookTitle.textColor = UIColor(resource: .readingPrimary)
            chapterTitle.text = "Chapter \(document.label)"
            chapterTitle.font = scaledFont(size: wide ? 24 : 22, style: .title2, serif: true)
            chapterTitle.textColor = UIColor(resource: .readingSecondary)
            gutterLabels.values.forEach { $0.removeFromSuperview() }
            gutterLabels.removeAll()
            bookmarkIndicators.values.forEach { $0.removeFromSuperview() }
            bookmarkIndicators.removeAll()
            appliedHighlights = [:]
            appliedCue = []
            needsAnchorRestore = true
            if changedChapter, state.anchor == nil { setContentOffset(.zero, animated: false) }
        }
        applyHighlights(state.highlights, exact: state.exactAnnotations)
        let selected = selectedRange
        let offset = contentOffset
        for entry in map?.entries ?? [] {
            if state.navigationCue.contains(entry.verse.id) {
                textStorage.addAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: UIColor(resource: .accent)], range: entry.range)
            } else if appliedCue.contains(entry.verse.id) {
                textStorage.removeAttribute(.underlineStyle, range: entry.range)
                textStorage.removeAttribute(.underlineColor, range: entry.range)
            }
        }
        appliedCue = state.navigationCue
        selectedRange = selected
        setContentOffset(offset, animated: false)
        appliedBookmarks = state.bookmarks
        restoreSelection()
        setNeedsLayout()
    }

    private func scaledFont(size: CGFloat, style: UIFont.TextStyle, serif: Bool = false, weight: UIFont.Weight = .regular) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let descriptor = serif ? (base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor) : base.fontDescriptor
        return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: descriptor, size: size), compatibleWith: traitCollection)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // Text draws behind floating chrome, but must not steal its taps after scrolling.
        guard point.y >= bounds.minY + chromeInsets.top, point.y < bounds.maxY - chromeInsets.bottom else { return false }
        return super.point(inside: point, with: event)
    }

    override func layoutSubviews() {
        let widthChanged = abs(lastWidth - bounds.width) > 0.5
        if widthChanged { needsAnchorRestore = true; accessibilityNeedsUpdate = true; lastWidth = bounds.width }
        let column = min(max(0, bounds.width - 40), 640)
        let outer = max(20, (bounds.width - column) / 2)
        let textWidth = max(1, column - gutterWidth)
        let headerSize = header.systemLayoutSizeFitting(CGSize(width: textWidth, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        header.frame = CGRect(x: outer + gutterWidth, y: chromeInsets.top + 20, width: textWidth, height: headerSize.height)
        let inset = UIEdgeInsets(top: header.frame.maxY + (wide ? 30 : 26), left: outer + gutterWidth, bottom: chromeInsets.bottom + 32, right: outer)
        if textContainerInset != inset { textContainerInset = inset }
        verticalScrollIndicatorInsets = UIEdgeInsets(top: chromeInsets.top, left: 0, bottom: chromeInsets.bottom, right: 0)
        super.layoutSubviews()
        if needsAnchorRestore, bounds.width > 0, bounds.height > 0 {
            needsAnchorRestore = false
            restorePosition()
            restoreSelection()
        }
        if needsSelectionFocusRestore, window != nil, selectedRange.length > 0 {
            // Restoring offsets alone leaves an inactive selection after a destination round trip.
            // Wait for attachment and layout before restoring native text-interaction focus.
            needsSelectionFocusRestore = !becomeFirstResponder()
        }
        layoutGutters()
    }

    private func applyHighlights(_ highlights: [String: HighlightColor], exact: [ExactAnnotation]) {
        guard let map else { return }
        let selected = selectedRange, offset = contentOffset
        textStorage.beginEditing()
        for entry in map.entries {
            textStorage.removeAttribute(.backgroundColor, range: entry.range)
            if let color = highlights[entry.verse.id] {
                textStorage.addAttribute(.backgroundColor, value: UIColor(named: color.assetName) ?? .clear, range: entry.range)
            }
            for record in exact where record.color != nil {
                for part in record.passage.parts where part.verseID == entry.verse.id {
                    guard let local = part.resolvedRange(in: entry.verse.text), let color = record.color else { continue }
                    textStorage.addAttribute(.backgroundColor, value: UIColor(named: color.assetName) ?? .clear,
                        range: NSRange(location: entry.range.location + local.location, length: local.length))
                }
            }
        }
        textStorage.endEditing()
        appliedHighlights = highlights
        appliedExact = exact
        accessibilityNeedsUpdate = true
        selectedRange = selected
        setContentOffset(offset, animated: false)
    }

    private func layoutGutters() {
        guard let manager = textLayoutManager, let content = manager.textContentManager, let map else { return }
        gutterLabels.values.forEach { $0.isHidden = true }
        bookmarkIndicators.values.forEach { $0.isHidden = true }
        let start = manager.textViewportLayoutController.viewportRange?.location ?? content.documentRange.location
        let font = scaledFont(size: wide ? 15 : 14, style: .caption1, weight: .medium)
        manager.enumerateTextLayoutFragments(from: start, options: []) { fragment in
            let offset = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
            guard let entry = map.entries.first(where: { $0.range.location == offset }), let line = fragment.textLineFragments.first else { return true }
            let y = fragment.layoutFragmentFrame.minY + self.textContainerInset.top
            if y > self.contentOffset.y + self.bounds.height + 100 { return false }
            let label = self.gutterLabels[entry.verse.id] ?? UILabel()
            if label.superview == nil { self.addSubview(label); self.gutterLabels[entry.verse.id] = label }
            label.isAccessibilityElement = false
            label.isUserInteractionEnabled = false
            label.text = entry.verse.label
            label.font = font
            label.textColor = UIColor(resource: .readingSecondary)
            label.textAlignment = .right
            label.isHidden = false
            let baseline = y + line.typographicBounds.minY + line.glyphOrigin.y
            label.frame = CGRect(x: self.textContainerInset.left - self.gutterWidth, y: baseline - font.ascender, width: self.gutterWidth - (self.wide ? 12 : 10), height: font.lineHeight)
            if self.appliedBookmarks.contains(entry.verse.id) {
                let indicator = self.bookmarkIndicators[entry.verse.id] ?? UIImageView(image: UIImage(systemName: "bookmark.fill"))
                if indicator.superview == nil { self.addSubview(indicator); self.bookmarkIndicators[entry.verse.id] = indicator }
                indicator.tintColor = UIColor(resource: .accent)
                indicator.isAccessibilityElement = false
                indicator.isHidden = false
                indicator.frame = CGRect(x: self.textContainerInset.left - self.gutterWidth - 13, y: baseline - font.ascender + 2, width: 10, height: 12)
            }
            return true
        }
        if UIAccessibility.isVoiceOverRunning, accessibilityNeedsUpdate { prepareVerseAccessibility() }
    }

    func capturePosition() {
        guard !applying, let state = readerState, state.chapterID == document?.id, let map, bounds.height > 0 else { return }
        state.selection = map.selection(for: selectedRange)
        if contentOffset.y < 4 { state.anchor = nil; return }
        let point = CGPoint(x: textContainerInset.left + 2, y: contentOffset.y + chromeInsets.top + 8)
        guard let position = closestPosition(to: point) else { return }
        let offset = self.offset(from: beginningOfDocument, to: position)
        // A source heading or inter-verse newline belongs to the following reading anchor,
        // not the previous verse's end paired with the heading's unrelated geometry.
        guard let entry = map.entries.first(where: { NSMaxRange($0.range) > offset }) ?? map.entries.last else { return }
        let local = min(max(0, offset - entry.range.location), entry.range.length)
        guard let semanticPosition = self.position(from: beginningOfDocument, offset: entry.range.location + local) else { return }
        let rect = caretRect(for: semanticPosition)
        state.anchor = ReadingAnchor(text: VerseAnchor(verseID: entry.verse.id, utf16Offset: local), viewportY: (rect.minY - contentOffset.y) / bounds.height)
    }

    private func restorePosition() {
        guard let state = readerState, let anchor = state.anchor, let map,
              let offset = map.offset(for: anchor.text), let position = position(from: beginningOfDocument, offset: offset) else { return }
        if let manager = textLayoutManager, let content = manager.textContentManager,
           let location = content.location(content.documentRange.location, offsetBy: offset),
           let end = content.location(location, offsetBy: min(1, map.text.utf16.count - offset)),
           let range = NSTextRange(location: location, end: end) {
            manager.ensureLayout(for: range)
        }
        let y = caretRect(for: position).minY - anchor.viewportY * bounds.height
        applying = true
        setContentOffset(CGPoint(x: 0, y: min(max(0, y), max(0, contentSize.height - bounds.height))), animated: false)
        applying = false
    }

    private func restoreSelection() {
        guard let selection = readerState?.selection, let range = map?.range(for: selection), selectedRange != range else { return }
        selectedRange = range
    }

    private var scrollDirectionStart: CGFloat = 0
    private var lastScrollY: CGFloat = 0
    private var scrollingDown = false

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        lastScrollY = scrollView.contentOffset.y
        scrollDirectionStart = lastScrollY
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Only a reader gesture changes chrome; restoration and inset changes do not.
        if !applying, scrollView.isDragging {
            let y = scrollView.contentOffset.y
            let down = y > lastScrollY
            if down != scrollingDown {
                scrollingDown = down
                scrollDirectionStart = lastScrollY
            }
            if y <= 0 || (!down && scrollDirectionStart - y > 24) {
                readerState?.navigationCollapsed = false
            } else if down && y - scrollDirectionStart > 40 {
                readerState?.navigationCollapsed = true
            }
            lastScrollY = y
        }
        if !needsAnchorRestore { capturePosition() }
        setNeedsLayout()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        guard !applying else { return }
        readerState?.selection = map?.selection(for: selectedRange)
    }

    override func copy(_ sender: Any?) {
        guard let map, let document, let text = map.copyText(range: selectedRange, document: document) else { return }
        UIPasteboard.general.string = text
    }

    /// Inspect the rendered selection, excluding source headings and inter-verse separators.
    /// A checkmark means every selected word has that color; mixed/partial coverage has no checkmark.
    func selectionHighlightStatus(in range: NSRange) -> (color: HighlightColor?, hasHighlights: Bool) {
        guard let map else { return (nil, false) }
        var colors = Set<HighlightColor>()
        var unhighlighted = false
        for entry in map.touched(by: range) {
            let selected = NSIntersectionRange(entry.range, range)
            textStorage.enumerateAttribute(.backgroundColor, in: selected) { value, _, _ in
                guard let fill = value as? UIColor,
                      let color = HighlightColor.allCases.first(where: {
                          fill.resolvedColor(with: traitCollection).isEqual(UIColor(named: $0.assetName)?.resolvedColor(with: traitCollection))
                      }) else { unhighlighted = true; return }
                colors.insert(color)
            }
        }
        return (colors.count == 1 && !unhighlighted ? colors.first : nil, !colors.isEmpty)
    }

    func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard let map, let document, !map.touched(by: range).isEmpty else { return UIMenu(children: suggestedActions) }
        guard let passage = map.exactPassage(range: range, document: document), let state = readerState else {
            return UIMenu(children: suggestedActions)
        }
        let highlightStatus = selectionHighlightStatus(in: range)
        let colors = HighlightColor.allCases.map { color in
            let tint: UIColor = switch color { case .yellow: .systemYellow; case .sage: .systemGreen; case .blue: .systemBlue; case .rose: .systemPink }
            let image = UIImage(systemName: "circle.fill")?.withTintColor(tint, renderingMode: .alwaysOriginal)
            return UIAction(title: (highlightStatus.color == color ? "✓ " : "") + color.rawValue.capitalized, image: image,
                            attributes: state.isSaving || !state.annotationEditingEnabled ? .disabled : [],
                            state: highlightStatus.color == color ? .on : .off) { _ in
                Task { await state.saveExact(passage, color: color) }
            }
        }
        let palette = UIMenu(title: "Highlight selected words", options: [.displayInline, .displayAsPalette], children: colors)
        let bookmarked = state.isExactlyBookmarked(passage)
        let bookmark = UIAction(title: bookmarked ? "Remove Bookmark" : "Bookmark", image: UIImage(systemName: bookmarked ? "bookmark.slash" : "bookmark"), attributes: state.isSaving || !state.annotationEditingEnabled ? .disabled : []) { _ in
            Task { await state.saveExact(passage, color: nil, bookmarkAction: !bookmarked) }
        }
        let remove = UIAction(title: "Remove Highlight", image: UIImage(systemName: "highlighter"), attributes: state.isSaving || !state.annotationEditingEnabled ? .disabled : []) { _ in
            Task { await state.saveExact(passage, color: nil) }
        }
        let share = UIAction(title: "Share Passage", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
            guard let self, let text = map.copyText(range: range, document: document) else { return }
            let controller = UIActivityViewController(activityItems: [text], applicationActivities: nil)
            controller.popoverPresentationController?.sourceView = self
            if let selection = self.selectedTextRange {
                controller.popoverPresentationController?.sourceRect = self.firstRect(for: selection)
            } else {
                controller.popoverPresentationController?.sourceRect = self.bounds
            }
            var parent = self.window?.rootViewController
            while let presented = parent?.presentedViewController { parent = presented }
            parent?.present(controller, animated: true)
        }
        let annotationActions: [UIMenuElement] = [palette, bookmark] + (highlightStatus.hasHighlights ? [remove] : [])
        return UIMenu(children: annotationActions + [share] + suggestedActions)
    }


    func prepareVerseAccessibility() {
        accessibilityNeedsUpdate = false
        guard let map, let document else { return }
        isAccessibilityElement = false
        verseAccessibility = map.entries.compactMap { entry in
            guard let start = position(from: beginningOfDocument, offset: entry.range.location),
                  let end = position(from: start, offset: entry.range.length), let range = textRange(from: start, to: end) else { return nil }
            let element = UIAccessibilityElement(accessibilityContainer: self)
            element.accessibilityLabel = "\(document.reference):\(entry.verse.label). \(entry.verse.text)"
            var annotations: [String] = []
            if let color = readerState?.highlights[entry.verse.id] { annotations.append("\(color.rawValue) highlight") }
            if readerState?.bookmarks.contains(entry.verse.id) == true { annotations.append("Bookmarked") }
            if readerState?.exactAnnotations.contains(where: { !$0.isBookmark && $0.passage.verseIDs.contains(entry.verse.id) }) == true {
                annotations.append("Contains highlighted words")
            }
            element.accessibilityValue = annotations.joined(separator: ", ")
            element.accessibilityTraits = .staticText
            element.accessibilityFrameInContainerSpace = firstRect(for: range)
            if let passage = map.exactPassage(range: entry.range, document: document), let state = readerState, state.annotationEditingEnabled {
                element.accessibilityCustomActions = HighlightColor.allCases.map { color in
                    UIAccessibilityCustomAction(name: "Highlight verse \(color.rawValue)") { _ in
                        Task { await state.saveExact(passage, color: color) }
                        return true
                    }
                } + [UIAccessibilityCustomAction(name: state.isExactlyBookmarked(passage) ? "Remove verse bookmark" : "Bookmark verse") { _ in
                    Task { await state.saveExact(passage, color: nil, bookmarkAction: !state.isExactlyBookmarked(passage)) }
                    return true
                }, UIAccessibilityCustomAction(name: "Remove verse highlights") { _ in
                    Task { await state.saveExact(passage, color: nil) }
                    return true
                }]
            }
            return element
        }
        accessibilityElements = [header] + verseAccessibility
    }
}
