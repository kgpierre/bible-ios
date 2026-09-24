import SwiftUI
import UIKit

/// A single TextKit 2 document. Never access `layoutManager`: that switches UITextView to TextKit 1.
@MainActor
final class ChapterTextView: UITextView, UITextViewDelegate, UIGestureRecognizerDelegate, UIEditMenuInteractionDelegate {
    var selectionDidChange: (() -> Void)?
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
    private var measuredHeaderWidth: CGFloat = -1
    private var measuredHeaderHeight: CGFloat = 0
    private var entriesByOffset: [Int: ChapterTextMap.Entry] = [:]
    private var lastCategory: UIContentSizeCategory?
    private var lastTypography = ReadingTypography()
    private var lastScheme: ColorScheme?
    private var lastRevision = -1
    private var appliedBookmarks: Set<String> = []
    private var bookmarkIndicators: [String: UIImageView] = [:]
    private var accessibilityNeedsUpdate = true
    #if DEBUG
    private(set) var documentBuildCount = 0
    private(set) var highlightVerseUpdateCount = 0
    private(set) var gutterPassCount = 0
    private(set) var accessibilityFrameUpdateCount = 0
    #endif
    private var lastContrast: UIAccessibilityContrast?
    private var lastAnnotationsRevision = -1
    private struct ColoredPart: Equatable {
        let part: SavedTextPart
        let color: HighlightColor
    }
    private var appliedParts: [String: [ColoredPart]] = [:]
    private var accessibilityDirtyVerses = Set<String>()
    private var accessibilityByVerse: [String: UIAccessibilityElement] = [:]
    private var gutterFont: UIFont?
    private var visibleGutterIDs = Set<String>()
    private var guttersDirty = true
    private var gutterViewport: Range<Int>?
    private var resolvedPalette: [(HighlightColor, UIColor)] = []
    private var swatchImages: [String: UIImage] = [:]
    private var paletteTraits: UITraitCollection?
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
    private weak var quickSelectionGesture: UILongPressGestureRecognizer?
    private lazy var quickSelectionMenu = UIEditMenuInteraction(delegate: self)
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
        delaysContentTouches = false
        contentInsetAdjustmentBehavior = .never
        delegate = self
        let quickSelection = UILongPressGestureRecognizer(target: self, action: #selector(beginWordSelection(_:)))
        quickSelection.minimumPressDuration = 0.3
        quickSelection.allowableMovement = 8
        quickSelection.cancelsTouchesInView = false
        quickSelection.delegate = self
        quickSelectionGesture = quickSelection
        addGestureRecognizer(quickSelection)
        addInteraction(quickSelectionMenu)
        NotificationCenter.default.addObserver(self, selector: #selector(captureBeforeBackground),
            name: UIApplication.willResignActiveNotification, object: nil)
        accessibilityIdentifier = "chapterText"
        NotificationCenter.default.addObserver(self, selector: #selector(accessibilityStatusChanged),
            name: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(accessibilityStatusChanged),
            name: UIAccessibility.switchControlStatusDidChangeNotification, object: nil)
        // Semantic verse actions are available to every assistive technology.
        header.axis = .vertical
        header.spacing = 6
        [eyebrow, bookTitle, chapterTitle].forEach {
            $0.numberOfLines = 0
            header.addArrangedSubview($0)
        }
        bookTitle.accessibilityTraits = .header
        addSubview(header)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitAccessibilityContrast.self]) { (view: ChapterTextView, _) in
            guard let document = view.document, let state = view.readerState else { return }
            view.configure(document: document, state: state, wide: view.wide, scheme: view.lastScheme ?? .light)
        }
    }

    override var undoManager: UndoManager? { readerState?.systemUndoManager ?? super.undoManager }

    required init?(coder: NSCoder) { fatalError("Use the native reader initializer") }

    // Start a word selection promptly using public text-input APIs. UIKit continues to own
    // the selection handles, dragging, magnifier, and standard edit menu interactions.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === quickSelectionGesture else { return super.gestureRecognizerShouldBegin(gestureRecognizer) }
        guard selectedRange.length == 0, !UIAccessibility.isVoiceOverRunning,
              !isDecelerating, !isDragging else { return false }
        let point = gestureRecognizer.location(in: self)
        guard point.x >= textContainerInset.left, point.y >= textContainerInset.top,
              self.point(inside: point, with: nil) else { return false }
        return wordRange(at: point) != nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        otherGestureRecognizer !== panGestureRecognizer
    }

    private func wordRange(at point: CGPoint) -> UITextRange? {
        guard let position = closestPosition(to: point),
              let word = tokenizer.rangeEnclosingPosition(position, with: .word,
                  inDirection: UITextDirection(rawValue: UITextStorageDirection.forward.rawValue)),
              firstRect(for: word).insetBy(dx: -4, dy: -4).contains(point) else { return nil }
        let range = NSRange(location: offset(from: beginningOfDocument, to: word.start),
                            length: offset(from: word.start, to: word.end))
        guard map?.touched(by: range).isEmpty == false else { return nil }
        return word
    }

    @objc private func beginWordSelection(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            guard let range = wordRange(at: gesture.location(in: self)) else { return }
            becomeFirstResponder()
            selectedTextRange = range
        case .ended:
            guard let range = selectedTextRange, !range.isEmpty else { return }
            let rect = firstRect(for: range)
            let configuration = UIEditMenuConfiguration(identifier: nil, sourcePoint: CGPoint(x: rect.midX, y: rect.minY))
            configuration.preferredArrowDirection = .down
            quickSelectionMenu.presentEditMenu(with: configuration)
        default: break
        }
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration,
                             suggestedActions: [UIMenuElement]) -> UIMenu? {
        textView(self, editMenuForTextIn: selectedRange, suggestedActions: suggestedActions)
    }


    func editMenuInteraction(_ interaction: UIEditMenuInteraction, targetRectFor configuration: UIEditMenuConfiguration) -> CGRect {
        guard let range = selectedTextRange else { return .null }
        return firstRect(for: range).insetBy(dx: -8, dy: -16)
    }

    func configure(document: ChapterDocument, state: ReaderState, wide: Bool, scheme: ColorScheme) {
        if self.document == nil, state.selection != nil { needsSelectionFocusRestore = true }
        let changedChapter = self.document?.id != document.id
        let changedNavigation = lastRevision != state.navigationRevision || readerState !== state
        let changedStyle = self.wide != wide || lastCategory != traitCollection.preferredContentSizeCategory || lastScheme != scheme || lastTypography != state.typography || lastContrast != traitCollection.accessibilityContrast
        self.readerState = state
        let changedAnnotations = lastAnnotationsRevision != state.annotationsRevision || changedNavigation
        guard changedChapter || changedStyle || changedNavigation || changedAnnotations || appliedCue != state.navigationCue else { return }
        // A width-mode transition may already have intermediate UIKit geometry.
        // Keep the last settled semantic anchor instead of capturing that transient layout.
        if changedStyle && !changedChapter && !changedNavigation && self.wide == wide { capturePosition() }
        applying = true
        defer { applying = false }
        self.document = document
        self.wide = wide
        lastCategory = traitCollection.preferredContentSizeCategory
        lastScheme = scheme
        lastTypography = state.typography
        lastContrast = traitCollection.accessibilityContrast
        lastRevision = state.navigationRevision
        lastAnnotationsRevision = state.annotationsRevision
        overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        backgroundColor = UIColor(resource: .readingCanvas)
        tintColor = UIColor(resource: .accent)
        if changedChapter || changedStyle {
            #if DEBUG
            documentBuildCount += 1
            #endif
            let map = ChapterTextMap(document: document)
            self.map = map
            entriesByOffset = Dictionary(uniqueKeysWithValues: map.entries.map { ($0.range.location, $0) })
            measuredHeaderWidth = -1
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
            chapterTitle.text = String(localized: "Chapter \(document.label)")
            chapterTitle.font = scaledFont(size: wide ? 24 : 22, style: .title2, serif: true)
            chapterTitle.textColor = UIColor(resource: .readingSecondary)
            gutterLabels.values.forEach { $0.removeFromSuperview() }
            gutterLabels.removeAll()
            bookmarkIndicators.values.forEach { $0.removeFromSuperview() }
            bookmarkIndicators.removeAll()
            appliedHighlights = [:]
            appliedParts = [:]
            appliedBookmarks = []
            appliedCue = []
            accessibilityNeedsUpdate = true
            accessibilityByVerse.removeAll()
            gutterFont = scaledFont(size: wide ? 15 : 14, style: .caption1, weight: .medium)
            visibleGutterIDs.removeAll()
            guttersDirty = true
            gutterViewport = nil
            refreshPalette()
            needsAnchorRestore = true
            if changedChapter, state.anchor == nil { setContentOffset(.zero, animated: false) }
        }
        if changedChapter || changedStyle || changedAnnotations {
            applyHighlights(state.highlights, exact: state.exactAnnotations(in: document.id))
            accessibilityDirtyVerses.formUnion(appliedBookmarks.symmetricDifference(state.bookmarks))
            appliedBookmarks = state.bookmarks
            guttersDirty = true
        }
        if changedNavigation {
            needsAnchorRestore = true
            if state.selection == nil { selectedRange = NSRange(location: 0, length: 0) }
            if state.anchor == nil { setContentOffset(.zero, animated: false) }
        }
        let selected = selectedRange
        let offset = contentOffset
        let changedCue = state.navigationCue.symmetricDifference(appliedCue)
        textStorage.beginEditing()
        for entry in map?.entries ?? [] where changedCue.contains(entry.verse.id) {
            if state.navigationCue.contains(entry.verse.id) {
                textStorage.addAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: UIColor(resource: .accent)], range: entry.range)
            } else if appliedCue.contains(entry.verse.id) {
                textStorage.removeAttribute(.underlineStyle, range: entry.range)
                textStorage.removeAttribute(.underlineColor, range: entry.range)
            }
        }
        textStorage.endEditing()
        appliedCue = state.navigationCue
        selectedRange = selected
        setContentOffset(offset, animated: false)
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
        if widthChanged { needsAnchorRestore = true; accessibilityNeedsUpdate = true; guttersDirty = true; lastWidth = bounds.width }
        let column = min(max(0, bounds.width - 40), 640)
        let outer = max(20, (bounds.width - column) / 2)
        let trailingExtra: CGFloat = wide ? 0 : 8
        let textWidth = max(1, column - gutterWidth - trailingExtra)
        if measuredHeaderWidth != textWidth {
            measuredHeaderWidth = textWidth
            measuredHeaderHeight = header.systemLayoutSizeFitting(CGSize(width: textWidth, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        }
        header.frame = CGRect(x: outer + gutterWidth, y: chromeInsets.top + (wide ? 20 : 8), width: textWidth, height: measuredHeaderHeight)
        let inset = UIEdgeInsets(top: header.frame.maxY + (wide ? 30 : 26), left: outer + gutterWidth, bottom: chromeInsets.bottom + 32, right: outer + trailingExtra)
        if textContainerInset != inset { textContainerInset = inset; guttersDirty = true; accessibilityNeedsUpdate = true }
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
        var partsByVerse: [String: [ColoredPart]] = [:]
        for record in exact {
            guard let color = record.color else { continue }
            for part in record.passage.parts { partsByVerse[part.verseID, default: []].append(ColoredPart(part: part, color: color)) }
        }
        textStorage.beginEditing()
        for entry in map.entries {
            let id = entry.verse.id
            guard appliedHighlights[id] != highlights[id] || appliedParts[id] != partsByVerse[id] else { continue }
            accessibilityDirtyVerses.insert(id)
            #if DEBUG
            highlightVerseUpdateCount += 1
            #endif
            textStorage.removeAttribute(.backgroundColor, range: entry.range)
            textStorage.removeAttribute(.readerHighlightColor, range: entry.range)
            if let color = highlights[id] {
                textStorage.addAttributes([.backgroundColor: UIColor(named: color.assetName) ?? .clear, .readerHighlightColor: color.rawValue], range: entry.range)
            }
            for colored in partsByVerse[id] ?? [] {
                guard let local = colored.part.resolvedRange(in: entry.verse.text) else { continue }
                textStorage.addAttributes([.backgroundColor: UIColor(named: colored.color.assetName) ?? .clear, .readerHighlightColor: colored.color.rawValue],
                    range: NSRange(location: entry.range.location + local.location, length: local.length))
            }
        }
        textStorage.endEditing()
        appliedHighlights = Dictionary(uniqueKeysWithValues: map.entries.compactMap { entry in highlights[entry.verse.id].map { (entry.verse.id, $0) } })
        appliedParts = partsByVerse
        selectedRange = selected
        setContentOffset(offset, animated: false)
    }

    private func layoutGutters() {
        guard let manager = textLayoutManager, let content = manager.textContentManager, map != nil else { return }
        let viewport = manager.textViewportLayoutController.viewportRange ?? content.documentRange
        let lower = content.offset(from: content.documentRange.location, to: viewport.location)
        let upper = content.offset(from: content.documentRange.location, to: viewport.endLocation)
        let range = lower..<max(lower, upper)
        // Labels live in content coordinates: scrolling within the same fragments moves them for free.
        if guttersDirty || gutterViewport != range {
            #if DEBUG
            gutterPassCount += 1
            #endif
            gutterViewport = range
            guttersDirty = false
            let font = gutterFont ?? scaledFont(size: wide ? 15 : 14, style: .caption1, weight: .medium)
            gutterFont = font
            var visible = Set<String>()
            manager.enumerateTextLayoutFragments(from: viewport.location, options: []) { fragment in
                let offset = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
                guard let entry = self.entriesByOffset[offset], let line = fragment.textLineFragments.first else { return true }
                let y = fragment.layoutFragmentFrame.minY + self.textContainerInset.top
                if y > self.contentOffset.y + self.bounds.height + 100 { return false }
                let id = entry.verse.id
                visible.insert(id)
                let label: UILabel
                if let existing = self.gutterLabels[id] { label = existing }
                else {
                    label = UILabel()
                    label.isAccessibilityElement = false
                    label.isUserInteractionEnabled = false
                    label.text = entry.verse.label
                    label.font = font
                    label.textColor = UIColor(resource: .readingSecondary)
                    label.textAlignment = .right
                    self.addSubview(label)
                    self.gutterLabels[id] = label
                }
                if label.isHidden { label.isHidden = false }
                let baseline = y + line.typographicBounds.minY + line.glyphOrigin.y
                let frame = CGRect(x: self.textContainerInset.left - self.gutterWidth, y: baseline - font.ascender,
                    width: self.gutterWidth - (self.wide ? 12 : 10), height: font.lineHeight)
                if label.frame != frame { label.frame = frame }
                if self.appliedBookmarks.contains(id) {
                    let indicator: UIImageView
                    if let existing = self.bookmarkIndicators[id] { indicator = existing }
                    else {
                        indicator = UIImageView(image: UIImage(systemName: "bookmark.fill"))
                        indicator.tintColor = UIColor(resource: .accent)
                        indicator.isAccessibilityElement = false
                        self.addSubview(indicator)
                        self.bookmarkIndicators[id] = indicator
                    }
                    if indicator.isHidden { indicator.isHidden = false }
                    let frame = CGRect(x: self.textContainerInset.left - self.gutterWidth - 13, y: baseline - font.ascender + 2, width: 10, height: 12)
                    if indicator.frame != frame { indicator.frame = frame }
                } else if let indicator = self.bookmarkIndicators[id], !indicator.isHidden { indicator.isHidden = true }
                return true
            }
            for id in visibleGutterIDs.subtracting(visible) {
                gutterLabels[id]?.isHidden = true
                bookmarkIndicators[id]?.isHidden = true
            }
            visibleGutterIDs = visible
        }
        if accessibilityNeedsUpdate || !accessibilityDirtyVerses.isEmpty { prepareVerseAccessibility() }
    }

    func capturePosition() {
        guard !applying, !needsAnchorRestore, abs(lastWidth - bounds.width) < 0.5, let state = readerState, state.chapterID == document?.id, let map, bounds.height > 0 else { return }
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

    func restoreSelectionFocus() {
        needsSelectionFocusRestore = selectedRange.length > 0
        setNeedsLayout()
    }

    @objc private func captureBeforeBackground() {
        guard window != nil else { return }
        capturePosition()
        readerState?.flushPosition(protectInBackground: true)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { capturePosition() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { capturePosition() }
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { capturePosition() }
    func scrollViewDidScrollToTop(_ scrollView: UIScrollView) { capturePosition() }

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
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        guard !applying else { return }
        quickSelectionMenu.dismissMenu()
        readerState?.selection = map?.selection(for: selectedRange)
        selectionDidChange?()
    }

    override func copy(_ sender: Any?) {
        guard let map, let document, let text = map.copyText(range: selectedRange, document: document) else { return }
        UIPasteboard.general.string = text
    }

    /// Inspect the rendered selection, excluding source headings and inter-verse separators.
    /// A checkmark means every selected word has that color; mixed/partial coverage has no checkmark.
    private func refreshPalette() {
        guard paletteTraits == nil || traitCollection.hasDifferentColorAppearance(comparedTo: paletteTraits) else { return }
        resolvedPalette = HighlightColor.allCases.map { ($0, (UIColor(named: $0.assetName) ?? .clear).resolvedColor(with: traitCollection)) }
        swatchImages.removeAll()
        paletteTraits = traitCollection
    }

    func selectionHighlightStatus(in range: NSRange) -> (color: HighlightColor?, hasHighlights: Bool) {
        refreshPalette()
        guard let map else { return (nil, false) }
        var colors = Set<HighlightColor>()
        var unhighlighted = false
        for entry in map.touched(by: range) {
            let selected = NSIntersectionRange(entry.range, range)
            textStorage.enumerateAttribute(.readerHighlightColor, in: selected) { value, _, _ in
                guard let name = value as? String, let color = HighlightColor(rawValue: name) else { unhighlighted = true; return }
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
            let tint = resolvedPalette.first { $0.0 == color }?.1 ?? .systemYellow
            let selected = highlightStatus.color == color
            let key = color.rawValue + (selected ? "-selected" : "")
            let image = swatchImages[key] ?? UIGraphicsImageRenderer(size: CGSize(width: 22, height: 22)).image { _ in
                let rect = CGRect(x: 0, y: 0, width: 22, height: 22)
                UIImage(systemName: "circle.fill")?.withTintColor(tint, renderingMode: .alwaysOriginal).draw(in: rect)
                UIImage(systemName: "circle")?.withTintColor(UIColor(resource: .readingSecondary), renderingMode: .alwaysOriginal).draw(in: rect)
                if selected {
                    UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(weight: .bold))?
                        .withTintColor(UIColor(resource: .readingPrimary), renderingMode: .alwaysOriginal)
                        .draw(in: CGRect(x: 5, y: 5, width: 12, height: 12))
                }
            }.withRenderingMode(.alwaysOriginal)
            swatchImages[key] = image
            // The edit menu derives its accessibility name from an image when the visible title is empty.
            image.accessibilityLabel = (selected ? "✓ " : "") + color.title
            let action = UIAction(title: "", image: image,
                            identifier: UIAction.Identifier("highlight-" + color.rawValue),
                            discoverabilityTitle: color.title,
                            attributes: state.isSaving || !state.annotationEditingEnabled ? .disabled : [],
                            state: highlightStatus.color == color ? .on : .off) { _ in
                Task { await state.saveExact(passage, color: color) }
            }
            action.accessibilityLabel = color.title
            return action
        }
        let palette = UIMenu(title: String(localized: "Highlight selected words"), options: [.displayInline, .displayAsPalette], children: colors)
        let bookmarked = state.isExactlyBookmarked(passage)
        let bookmark = UIAction(title: bookmarked ? String(localized: "Remove Bookmark") : String(localized: "Bookmark"), image: UIImage(systemName: bookmarked ? "bookmark.slash" : "bookmark"), attributes: state.isSaving || !state.annotationEditingEnabled ? .disabled : []) { _ in
            Task { await state.saveExact(passage, color: nil, bookmarkAction: !bookmarked) }
        }
        let remove = UIAction(title: String(localized: "Remove Highlight"), image: UIImage(systemName: "highlighter"), attributes: state.isSaving || !state.annotationEditingEnabled ? .disabled : []) { _ in
            Task { await state.saveExact(passage, color: nil) }
        }
        let share = UIAction(title: String(localized: "Share Passage"), image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
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


    @objc private func accessibilityStatusChanged() {
        accessibilityNeedsUpdate = true
        setNeedsLayout()
        selectionDidChange?()
    }

    func prepareVerseAccessibility() {
        guard let map, let document else { return }
        let rebuildGeometry = accessibilityNeedsUpdate
        accessibilityNeedsUpdate = false
        isAccessibilityElement = false
        verseAccessibility = map.entries.compactMap { entry in
            if !rebuildGeometry, !accessibilityDirtyVerses.contains(entry.verse.id), let existing = accessibilityByVerse[entry.verse.id] { return existing }
            guard let start = position(from: beginningOfDocument, offset: entry.range.location),
                  let end = position(from: start, offset: entry.range.length), let range = textRange(from: start, to: end) else { return nil }
            let existing = accessibilityByVerse[entry.verse.id]
            let element = existing ?? VerseAccessibilityElement(accessibilityContainer: self)
            element.accessibilityLabel = "\(document.reference):\(entry.verse.label). \(entry.verse.text)"
            var annotations: [String] = []
            if let color = readerState?.highlights[entry.verse.id] { annotations.append(color.accessibilityDescription) }
            if readerState?.bookmarks.contains(entry.verse.id) == true { annotations.append(String(localized: "Bookmarked")) }
            if appliedParts[entry.verse.id]?.isEmpty == false {
                annotations.append(String(localized: "Contains highlighted words"))
            }
            element.accessibilityValue = annotations.joined(separator: ", ")
            element.accessibilityTraits = .staticText
            if rebuildGeometry || existing == nil {
                (element as? VerseAccessibilityElement)?.rectProvider = { [weak self] in
                    self?.selectionRects(for: range).reduce(CGRect.null) { rect, selection in
                        selection.rect.isEmpty ? rect : rect.union(selection.rect)
                    } ?? .zero
                }
                #if DEBUG
                accessibilityFrameUpdateCount += 1
                #endif
            }
            if let passage = map.exactPassage(range: entry.range, document: document), let state = readerState, state.annotationEditingEnabled {
                element.accessibilityCustomActions = HighlightColor.allCases.map { color in
                    UIAccessibilityCustomAction(name: color.verseActionTitle) { _ in
                        Task { await state.saveExact(passage, color: color) }
                        return true
                    }
                } + [UIAccessibilityCustomAction(name: state.isExactlyBookmarked(passage) ? String(localized: "Remove verse bookmark") : String(localized: "Bookmark verse")) { _ in
                    Task { await state.saveExact(passage, color: nil, bookmarkAction: !state.isExactlyBookmarked(passage)) }
                    return true
                }, UIAccessibilityCustomAction(name: String(localized: "Remove verse highlights")) { _ in
                    Task { await state.saveExact(passage, color: nil) }
                    return true
                }]
            }
            accessibilityByVerse[entry.verse.id] = element
            return element
        }
        accessibilityDirtyVerses.removeAll()
        accessibilityElements = [header] + verseAccessibility
    }
}

private extension NSAttributedString.Key {
    static let readerHighlightColor = NSAttributedString.Key("BibleReader.HighlightColor")
}

/// Geometry is requested only for the verse an accessibility client inspects.
/// Keeping semantic elements cheap avoids laying out an entire long chapter up front.
private final class VerseAccessibilityElement: UIAccessibilityElement {
    var rectProvider: (() -> CGRect)?
    override var accessibilityFrameInContainerSpace: CGRect {
        get { let rect = rectProvider?() ?? .zero; return rect.isNull ? .zero : rect }
        set { }
    }
    override var accessibilityFrame: CGRect {
        get {
            guard let view = accessibilityContainer as? UIView else { return .zero }
            return UIAccessibility.convertToScreenCoordinates(accessibilityFrameInContainerSpace, in: view)
        }
        set { }
    }
}
