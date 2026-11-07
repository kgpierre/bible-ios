import SwiftUI
import UIKit
import os

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
    /// Book-page mode: one page of a two-page spread. The spread owns the reading anchor and
    /// turning, so the page never scrolls or captures position.
    var paged = false {
        didSet { if paged != oldValue { alwaysBounceVertical = !paged; setNeedsLayout() } }
    }
    /// The band of the chapter a book page shows. The page holds the whole chapter, laid out
    /// exactly as it was measured, and shows only these lines; a verse continues on the next page.
    var pageWindow: ChapterPagination.Page? {
        didSet {
            guard pageWindow != oldValue else { return }
            windowLaidOut = false
            shownBand = nil
            accessibilityNeedsUpdate = true
            setNeedsLayout()
        }
    }
    private var windowLaidOut = false
    /// The band this page actually shows, in container coordinates, from its own layout.
    private var shownBand: (top: CGFloat, bottom: CGFloat)?
    /// Paper over the lines that belong to the previous and next pages.
    private let pageCovers = [UIView(), UIView()]
    private var windowed: ChapterPagination.Page? { paged ? pageWindow : nil }
    private var pinnedOffset: CGPoint? { windowed.map { CGPoint(x: 0, y: $0.top) } }
    var pageInnerInset: CGFloat = 0 {
        didSet { if pageInnerInset != oldValue { setNeedsLayout() } }
    }
    /// A book page clear of the floating bottom controls: its text runs down to this inset
    /// (the screen's own safe area) instead of `chromeInsets.bottom`.
    var pageBottomInset: CGFloat? {
        didSet { if pageBottomInset != oldValue { setNeedsLayout() } }
    }
    /// The bottom band this view leaves to floating chrome.
    private var bottomChrome: CGFloat { paged ? pageBottomInset ?? chromeInsets.bottom : chromeInsets.bottom }
    var isLeftSpreadPage = true {
        didSet { if isLeftSpreadPage != oldValue { setNeedsLayout() } }
    }
    /// The chapter's opening page shows its full title; later pages show a small running head.
    var showsHeader = true {
        didSet { if showsHeader != oldValue { applyHeaderMode(); measuredHeaderWidth = -1; setNeedsLayout() } }
    }
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
    /// Source-note markers: a small dot beside the verse number and a gutter-only tap target.
    /// Neither is part of the text, so selection, copy, and anchors never include them.
    private var noteMarkers: [String: (dot: UIView, button: UIButton)] = [:]
    private var showsNotes = true
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
    /// Source headings and trailing blocks, keyed by their UTF-16 location in the current map.
    private var accessibilityByHeading: [Int: UIAccessibilityElement] = [:]
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
    /// The words being read aloud (0023). Drawn in views beside the text, never in `textStorage`,
    /// so the document, highlights, selection, and copy are untouched while narration plays.
    var narrationFocus: NarrationFocus? {
        didSet { if narrationFocus != oldValue { narrationDirty = true; setNeedsLayout() } }
    }
    /// The scrolling reader keeps the spoken line in view; a book page leaves turning to its spread.
    var followsNarration = false
    /// Starts Read Aloud in a chapter: "Read Aloud from Here" and the VoiceOver verse action.
    var readAloud: ((String, VerseAnchor) -> Void)? {
        didSet { if (readAloud == nil) != (oldValue == nil) { accessibilityNeedsUpdate = true; setNeedsLayout() } }
    }
    /// A tint behind the spoken verse and an underline under the spoken word, so the indicator
    /// does not rely on color alone.
    private let narrationVerseMark = NarrationMarkView()
    private let narrationWordMark = NarrationMarkView()
    private var narrationDirty = false
    private var followedRevision = -1
    /// Following pauses for a few seconds after the reader scrolls, and stays off while the
    /// spoken line is far from where they scrolled.
    private var lastUserScroll: CFTimeInterval?
    private var scrolledAwayFromNarration = false

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
        for cover in pageCovers {
            cover.isHidden = true
            cover.isUserInteractionEnabled = false
            cover.isAccessibilityElement = false
            addSubview(cover)
        }
        addSubview(header)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitAccessibilityContrast.self]) { (view: ChapterTextView, _) in
            guard let document = view.document, let state = view.readerState else { return }
            view.configure(document: document, state: state, wide: view.wide, scheme: view.lastScheme ?? .light)
        }
    }

    override var undoManager: UndoManager? { readerState?.systemUndoManager ?? super.undoManager }

    // A book page stays on its band; selection and restoration never scroll it.
    override var contentOffset: CGPoint {
        get { super.contentOffset }
        set { super.contentOffset = pinnedOffset ?? newValue }
    }

    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        if let pinnedOffset { super.setContentOffset(pinnedOffset, animated: false) }
        else { super.setContentOffset(contentOffset, animated: animated) }
    }

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
        let changedStyle = self.wide != wide || lastCategory != traitCollection.preferredContentSizeCategory || lastScheme != scheme || lastTypography.layout != state.typography.layout || lastContrast != traitCollection.accessibilityContrast
        self.readerState = state
        let changedAnnotations = lastAnnotationsRevision != state.annotationsRevision || changedNavigation
        let changedNotes = showsNotes != state.typography.showsNotes
        guard changedChapter || changedStyle || changedNavigation || changedAnnotations || changedNotes || appliedCue != state.navigationCue else { return }
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
            let buildInterval = ReaderPerformance.signposter.beginInterval("Document build", id: ReaderPerformance.signposter.makeSignpostID())
            defer { ReaderPerformance.signposter.endInterval("Document build", buildInterval) }
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
                string.addAttributes([.font: scaledFont(size: max(12, 16 + state.typography.pointAdjustment), style: .subheadline, serif: state.typography.face == .serif), .foregroundColor: UIColor(resource: .readingSecondary)], range: range)
            }
            let italic = font.fontDescriptor.withSymbolicTraits(.traitItalic).map { UIFont(descriptor: $0, size: font.pointSize) }
            let storage = string.string as NSString
            for entry in map.entries {
                var offset = entry.range.location
                for run in entry.verse.runs {
                    let length = run.text.utf16.count
                    if run.italic, let italic, length > 0 {
                        string.addAttribute(.font, value: italic, range: NSRange(location: offset, length: length))
                        // Serif italics overhang into a following roman space ("of the" reads as "ofthe").
                        // Presentation-only kerning restores the gap; text, copy, and anchors are unchanged.
                        if run.text.last?.isWhitespace == false {
                            let last = storage.rangeOfComposedCharacterSequence(at: offset + length - 1)
                            string.addAttribute(.kern, value: font.pointSize * 0.08, range: last)
                        }
                    }
                    offset += length
                }
            }
            attributedText = string
            windowLaidOut = false
            shownBand = nil
            eyebrow.text = document.eyebrow
            eyebrow.font = scaledFont(size: wide ? 14 : 13, style: .caption1, weight: .semibold)
            eyebrow.textColor = UIColor(resource: .readingSecondary)
            bookTitle.text = document.bookName
            bookTitle.font = scaledFont(size: wide ? 46 : 40, style: .largeTitle, serif: true, weight: .semibold)
            bookTitle.textColor = UIColor(resource: .readingPrimary)
            chapterTitle.text = String(localized: "Chapter \(document.label)")
            chapterTitle.font = scaledFont(size: wide ? 24 : 22, style: .title2, serif: true)
            chapterTitle.textColor = UIColor(resource: .readingSecondary)
            applyHeaderMode()
            gutterLabels.values.forEach { $0.removeFromSuperview() }
            gutterLabels.removeAll()
            bookmarkIndicators.values.forEach { $0.removeFromSuperview() }
            bookmarkIndicators.removeAll()
            noteMarkers.values.forEach { $0.dot.removeFromSuperview(); $0.button.removeFromSuperview() }
            noteMarkers.removeAll()
            showsNotes = state.typography.showsNotes
            appliedHighlights = [:]
            appliedParts = [:]
            appliedBookmarks = []
            appliedCue = []
            accessibilityNeedsUpdate = true
            accessibilityByVerse.removeAll()
            accessibilityByHeading.removeAll()
            gutterFont = scaledFont(size: wide ? 15 : 14, style: .caption1, weight: .medium)
            visibleGutterIDs.removeAll()
            guttersDirty = true
            gutterViewport = nil
            refreshPalette()
            needsAnchorRestore = true
            narrationDirty = true
            if changedChapter, state.anchor == nil { setContentOffset(.zero, animated: false) }
        }
        if changedNotes && !changedChapter && !changedStyle {
            // Markers only: hide or re-place them in the gutter without rebuilding the text.
            showsNotes = state.typography.showsNotes
            noteMarkers.values.forEach { $0.dot.isHidden = true; $0.button.isHidden = true }
            guttersDirty = true
            setNeedsLayout()
        }
        if changedChapter || changedStyle || changedAnnotations {
            applyHighlights(state.highlights, exact: state.exactAnnotations(in: document.id))
            accessibilityDirtyVerses.formUnion(appliedBookmarks.symmetricDifference(state.bookmarks))
            appliedBookmarks = state.bookmarks
            guttersDirty = true
        }
        if changedNavigation {
            needsAnchorRestore = true
            // Navigating, including to the verse being read aloud, resumes following.
            scrolledAwayFromNarration = false
            lastUserScroll = nil
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

    private func applyHeaderMode() {
        bookTitle.isHidden = !showsHeader
        chapterTitle.isHidden = !showsHeader
        eyebrow.text = showsHeader ? document?.eyebrow : document?.reference.localizedUppercase
        eyebrow.accessibilityTraits = showsHeader ? .staticText : .header
    }

    /// Paged layout: every line of the chapter, in text-container coordinates. Lays out the
    /// whole chapter; measure offscreen.
    func measuredLines() -> [ChapterPagination.Line] {
        guard let manager = textLayoutManager, let content = manager.textContentManager, let map else { return [] }
        manager.ensureLayout(for: content.documentRange)
        var lines: [ChapterPagination.Line] = []
        manager.enumerateTextLayoutFragments(from: content.documentRange.location, options: [.ensuresLayout]) { fragment in
            let start = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
            let origin = fragment.layoutFragmentFrame.minY
            for line in fragment.textLineFragments where line.characterRange.length > 0 {
                let offset = start + line.characterRange.location
                let heading = map.sourceHeadingRanges.contains { NSLocationInRange(offset, $0) }
                lines.append(ChapterPagination.Line(offset: offset, top: origin + line.typographicBounds.minY,
                                                    bottom: origin + line.typographicBounds.maxY, keepsWithNext: heading))
            }
            return true
        }
        return lines
    }

    /// Text height available between the header (or top chrome) and the bottom chrome.
    var pageTextHeight: CGFloat { bounds.height - textContainerInset.top - textContainerInset.bottom }

    private func scaledFont(size: CGFloat, style: UIFont.TextStyle, serif: Bool = false, weight: UIFont.Weight = .regular) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let descriptor = serif ? (base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor) : base.fontDescriptor
        return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: descriptor, size: size), compatibleWith: traitCollection)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // Text draws behind floating chrome, but must not steal its taps after scrolling.
        guard point.y >= bounds.minY + chromeInsets.top, point.y < bounds.maxY - bottomChrome else { return false }
        // A book page answers only within its own lines, never the covered ones. While text is
        // selected, the margin just outside the band stays live so the selection handles' knobs
        // above the first line and below the last line can be grabbed.
        if let band = pageBand {
            let reach = selectedRange.length > 0 ? Self.handleReach : 0
            if point.y < band.minY - reach || point.y >= band.maxY + reach { return false }
        }
        return super.point(inside: point, with: event)
    }

    /// How far a selection handle's knob and touch target extend past its line.
    static let handleReach: CGFloat = 22

    /// A book page's visible lines, in content coordinates.
    private var pageBand: CGRect? {
        guard let window = windowed else { return nil }
        let band = shownBand ?? (window.top, window.bottom)
        return CGRect(x: 0, y: textContainerInset.top + band.top, width: bounds.width, height: band.bottom - band.top)
    }

    /// The typographic frame of the line holding a UTF-16 offset, in container coordinates.
    private func lineFrame(at offset: Int) -> CGRect? {
        guard let map, offset >= 0, offset < map.text.utf16.count,
              let manager = textLayoutManager, let content = manager.textContentManager,
              let location = content.location(content.documentRange.location, offsetBy: offset),
              let fragment = manager.textLayoutFragment(for: location) else { return nil }
        let local = offset - content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
        guard let line = fragment.textLineFragments.first(where: { NSLocationInRange(local, $0.characterRange) })
                ?? fragment.textLineFragments.last else { return nil }
        return line.typographicBounds.offsetBy(dx: 0, dy: fragment.layoutFragmentFrame.minY)
    }

    /// The page's lines as this view laid them out, which can differ slightly from the
    /// offscreen measurement. Each edge sits midway into the gap beside the neighboring line,
    /// so accents and italic overhangs are never cut by the paper covers.
    private func measureShownBand(_ window: ChapterPagination.Page) -> (top: CGFloat, bottom: CGFloat) {
        guard let first = lineFrame(at: window.start), let last = lineFrame(at: max(window.start, window.end - 1)) else {
            return (window.top, window.bottom)
        }
        var top = first.minY, bottom = last.maxY
        if window.start > 0, let previous = lineFrame(at: window.start - 1), previous.maxY <= top {
            top = (previous.maxY + top) / 2
        }
        if let next = lineFrame(at: window.end), next.minY >= bottom {
            bottom = (bottom + next.minY) / 2
        } else {
            bottom += Self.overhang
        }
        return (top, bottom)
    }

    /// Room past a final line's typographic bounds for glyphs that overhang it.
    private static let overhang: CGFloat = 4

    private var pageRange: NSRange? {
        windowed.map { NSRange(location: $0.start, length: $0.end - $0.start) }
    }

    /// Lay out the chapter through this page's band so its line positions are exact, not
    /// estimated, then show the band and cover the lines of other pages.
    private func layoutPageWindow() {
        guard let window = windowed, let manager = textLayoutManager, let content = manager.textContentManager else {
            pageCovers.forEach { $0.isHidden = true }
            return
        }
        // Through the line after the page too, so the band's lower edge can sit in the gap before it.
        if !windowLaidOut, let length = map?.text.utf16.count,
           let end = content.location(content.documentRange.location, offsetBy: min(window.end + 1, length)),
           let range = NSTextRange(location: content.documentRange.location, end: end) {
            manager.ensureLayout(for: range)
            windowLaidOut = true
            shownBand = measureShownBand(window)
        }
        if super.contentOffset.y != window.top { super.contentOffset = CGPoint(x: 0, y: window.top) }
        let band = shownBand ?? (window.top, window.bottom)
        let canvas = UIColor(resource: .readingCanvas)
        // Above the band: the lines of earlier pages (the first page has none; its title shows).
        let above = CGRect(x: 0, y: window.top, width: bounds.width,
                           height: window.start == 0 ? 0 : max(0, textContainerInset.top + band.top - window.top))
        let below = CGRect(x: 0, y: textContainerInset.top + band.bottom, width: bounds.width, height: bounds.height)
        for (cover, frame) in zip(pageCovers, [above, below]) {
            cover.backgroundColor = canvas
            cover.isHidden = frame.height <= 0
            if cover.frame != frame { cover.frame = frame }
            bringSubviewToFront(cover)
        }
        bringSubviewToFront(header)
        raiseSelectionHandles()
    }

    /// Selection handles stay above the paper covers: a knob on the band's first or last line
    /// reaches past the band, and must remain visible and draggable there. Uses UIKit's public
    /// selection display interaction to find the handles; the covered text stays hidden.
    private func raiseSelectionHandles() {
        guard windowed != nil else { return }
        for case let display as UITextSelectionDisplayInteraction in interactions {
            for handle in display.handleViews {
                var view: UIView = handle
                while let parent = view.superview, parent !== self { view = parent }
                if view.superview === self, subviews.last !== view { bringSubviewToFront(view) }
            }
        }
    }

    override func layoutSubviews() {
        let widthChanged = abs(lastWidth - bounds.width) > 0.5
        if widthChanged { needsAnchorRestore = true; accessibilityNeedsUpdate = true; guttersDirty = true; narrationDirty = true; lastWidth = bounds.width }
        let innerInset = paged ? max(0, pageInnerInset) : 0
        let column = min(max(0, bounds.width - 40 - innerInset), 640)
        let outer = max(20, (bounds.width - column - innerInset) / 2)
        let leading = outer + (isLeftSpreadPage ? 0 : innerInset)
        let trailing = outer + (isLeftSpreadPage ? innerInset : 0)
        let trailingExtra: CGFloat = wide ? 0 : 8
        let textWidth = max(1, column - gutterWidth - trailingExtra)
        if measuredHeaderWidth != textWidth {
            measuredHeaderWidth = textWidth
            measuredHeaderHeight = header.systemLayoutSizeFitting(CGSize(width: textWidth, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        }
        // A book page never scrolls, so it needs no clearance beyond the chrome itself: tighter
        // margins fit more of the chapter on each page.
        let headerTop = chromeInsets.top + (paged && !showsHeader ? 10 : (wide ? 20 : 8))
        // A book page's running head stays at the top of the page, above its band.
        header.frame = CGRect(x: leading + gutterWidth, y: headerTop + (pinnedOffset?.y ?? 0), width: textWidth, height: measuredHeaderHeight)
        let headerGap: CGFloat = showsHeader ? (wide ? 30 : 26) : (paged ? 12 : 16)
        let inset = UIEdgeInsets(top: headerTop + measuredHeaderHeight + headerGap, left: leading + gutterWidth,
                                 bottom: bottomChrome + (paged ? 8 : ReaderLayout.chapterEndClearance), right: trailing + trailingExtra)
        if textContainerInset != inset { textContainerInset = inset; guttersDirty = true; accessibilityNeedsUpdate = true; narrationDirty = true }
        verticalScrollIndicatorInsets = UIEdgeInsets(top: chromeInsets.top, left: 0, bottom: chromeInsets.bottom, right: 0)
        super.layoutSubviews()
        // Scrolling stays enabled so the text container keeps the chapter's full height (a
        // non-scrolling text view lays out only what fits its bounds). A book page is pinned to
        // its band instead, with no drag or indicator.
        if !isScrollEnabled { isScrollEnabled = true }
        if panGestureRecognizer.isEnabled == paged { panGestureRecognizer.isEnabled = !paged }
        if showsVerticalScrollIndicator == paged { showsVerticalScrollIndicator = !paged }
        if needsAnchorRestore, bounds.width > 0, bounds.height > 0 {
            needsAnchorRestore = false
            restorePosition()
            restoreSelection()
        }
        if window != nil, map != nil, bounds.height > 0 { ReaderPerformance.markFirstScriptureLaidOut() }
        if needsSelectionFocusRestore, window != nil, selectedRange.length > 0 {
            // Restoring offsets alone leaves an inactive selection after a destination round trip.
            // Wait for attachment and layout before restoring native text-interaction focus.
            needsSelectionFocusRestore = !becomeFirstResponder()
        }
        layoutGutters()
        layoutNarration()
        layoutPageWindow()
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
                textStorage.addAttributes([.backgroundColor: color.fill, .readerHighlightColor: color.rawValue], range: entry.range)
            }
            for colored in partsByVerse[id] ?? [] {
                guard let local = colored.part.resolvedRange(in: entry.verse.text) else { continue }
                textStorage.addAttributes([.backgroundColor: colored.color.fill, .readerHighlightColor: colored.color.rawValue],
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
                if self.showsNotes, !entry.verse.notes.isEmpty {
                    let marker = self.noteMarkers[id] ?? self.makeNoteMarker(verseID: id)
                    marker.dot.isHidden = false
                    marker.button.isHidden = false
                    let dot = CGRect(x: frame.maxX + 2, y: frame.minY + 1, width: 5, height: 5)
                    if marker.dot.frame != dot { marker.dot.frame = dot }
                    // A 44-point square over the number and dot, extending into the leading margin;
                    // it stops short of the text column so it never intercepts text selection.
                    let trailing = self.textContainerInset.left - 2
                    let left = min(frame.minX - 4, trailing - 44)
                    let target = CGRect(x: left, y: frame.midY - 22, width: trailing - left, height: 44)
                    if marker.button.frame != target { marker.button.frame = target }
                }
                return true
            }
            for id in visibleGutterIDs.subtracting(visible) {
                gutterLabels[id]?.isHidden = true
                bookmarkIndicators[id]?.isHidden = true
                noteMarkers[id]?.dot.isHidden = true
                noteMarkers[id]?.button.isHidden = true
            }
            visibleGutterIDs = visible
        }
        if accessibilityNeedsUpdate || !accessibilityDirtyVerses.isEmpty { prepareVerseAccessibility() }
    }

    private func makeNoteMarker(verseID: String) -> (dot: UIView, button: UIButton) {
        let dot = UIView()
        dot.backgroundColor = UIColor(resource: .accent)
        dot.layer.cornerRadius = 2.5
        dot.isUserInteractionEnabled = false
        dot.isAccessibilityElement = false
        let button = UIButton(type: .custom)
        // Assistive technologies reach notes through the verse element's "Show notes" action.
        button.isAccessibilityElement = false
        button.addAction(UIAction { [weak self] _ in self?.showNotes(verseID: verseID) }, for: .touchUpInside)
        addSubview(dot)
        addSubview(button)
        let marker = (dot: dot, button: button)
        noteMarkers[verseID] = marker
        return marker
    }

    private func showNotes(verseID: String) {
        guard let document, let verse = document.verses.first(where: { $0.id == verseID }), !verse.notes.isEmpty else { return }
        readerState?.notesRequest = .verse(verse, in: document)
    }

    // MARK: Read Aloud follow-along

    /// Positions the verse tint and word underline for `narrationFocus`, then follows it in the
    /// scrolling reader. Runs only when the focus or the layout changed.
    private func layoutNarration() {
        guard narrationDirty, map != nil else { return }
        narrationDirty = false
        guard let focus = narrationFocus, focus.chapterID == document?.id, let map,
              let located = NarrationFollow.location(of: focus, in: map) else {
            narrationVerseMark.isHidden = true
            narrationWordMark.isHidden = true
            return
        }
        // Added on first use, above UIKit's own text content (which must stay its first subview for
        // text accessibility) and below the book-page covers, gutter numbers, and handles.
        if narrationVerseMark.superview == nil {
            insertSubview(narrationVerseMark, belowSubview: pageCovers[0])
            insertSubview(narrationWordMark, aboveSubview: narrationVerseMark)
        }
        let verse = focus.segmentRange ?? located
        let verseRects = lineRects(for: verse)
        let wordRects = focus.wordRange.map { lineRects(for: $0) } ?? []
        let accent = UIColor(resource: .accent).resolvedColor(with: traitCollection)
        let contrast = traitCollection.accessibilityContrast == .high
        narrationVerseMark.draw(verseRects.map { $0.insetBy(dx: -4, dy: 0) }) { rect in
            UIBezierPath(roundedRect: rect, cornerRadius: 6)
        }
        narrationVerseMark.shape.fillColor = accent.withAlphaComponent(contrast ? 0.24 : 0.13).cgColor
        let thickness: CGFloat = contrast ? 3 : 2
        narrationWordMark.draw(wordRects) { rect in
            UIBezierPath(roundedRect: CGRect(x: rect.minX, y: rect.maxY - thickness, width: rect.width, height: thickness),
                         cornerRadius: thickness / 2)
        }
        narrationWordMark.shape.fillColor = accent.cgColor
        if focus.revision != followedRevision {
            followedRevision = focus.revision
            if let line = (wordRects.first ?? verseRects.first) { followNarration(to: line) }
        }
    }

    /// The text's line rectangles for a range, in content coordinates, each ending at its text
    /// line's descent rather than including the spacing below it.
    private func lineRects(for range: NSRange) -> [CGRect] {
        guard let map, range.length > 0, NSMaxRange(range) <= map.text.utf16.count,
              let start = position(from: beginningOfDocument, offset: range.location),
              let end = position(from: start, offset: range.length),
              let textRange = textRange(from: start, to: end) else { return [] }
        // Lay out from the chapter start: a range laid out alone sits at an estimated position
        // that moves once the text before it is laid out. Layout persists, so narration's
        // forward progress adds only the new lines.
        if let manager = textLayoutManager, let content = manager.textContentManager,
           let endLocation = content.location(content.documentRange.location, offsetBy: NSMaxRange(range)),
           let layoutRange = NSTextRange(location: content.documentRange.location, end: endLocation) {
            manager.ensureLayout(for: layoutRange)
        }
        return selectionRects(for: textRange).compactMap { selection in
            let rect = selection.rect
            guard !rect.isNull, rect.width > 0.5, rect.height > 0 else { return nil }
            // A selection rectangle includes line spacing; keep the underline at the glyphs.
            let offset = closestPosition(to: CGPoint(x: rect.midX, y: rect.midY)).map { self.offset(from: beginningOfDocument, to: $0) }
            guard let offset, let line = lineFrame(at: min(offset, map.text.utf16.count - 1)) else { return rect }
            let bottom = min(rect.maxY, textContainerInset.top + line.maxY + 2)
            return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(1, bottom - rect.minY))
        }
    }

    /// Scrolls so the spoken line stays readable, unless the reader is busy with the text:
    /// touching or scrolling it (and for 5 seconds after), selecting, or reading it with VoiceOver.
    private func followNarration(to line: CGRect) {
        guard followsNarration, !paged, window != nil, !applying, !needsAnchorRestore, bounds.height > 0,
              !isTracking, !isDragging, !isDecelerating, selectedRange.length == 0 else { return }
        if let lastUserScroll, CACurrentMediaTime() - lastUserScroll < 5 { return }
        if UIAccessibility.isVoiceOverRunning,
           let focused = UIAccessibility.focusedElement(using: .notificationVoiceOver) as? UIAccessibilityElement,
           focused.accessibilityContainer as? ChapterTextView === self { return }
        let top = contentOffset.y + chromeInsets.top, bottom = contentOffset.y + bounds.height - bottomChrome
        if scrolledAwayFromNarration {
            guard NarrationFollow.isNear(line, top: top, bottom: bottom) else { return }
            scrolledAwayFromNarration = false
        }
        guard let y = NarrationFollow.scrollOffset(for: line, top: top, bottom: bottom, currentOffset: contentOffset.y,
                                                   maxOffset: contentSize.height - bounds.height) else { return }
        let animated = !UIAccessibility.isReduceMotionEnabled
        setContentOffset(CGPoint(x: 0, y: y), animated: animated)
        // An animated follow records the reading anchor when it ends, like any scroll.
        if !animated { capturePosition() }
    }

    #if DEBUG
    /// The rectangles of the Read Aloud verse tint and word underline, for tests.
    var narrationMarkFrames: (verse: CGRect?, word: CGRect?) {
        (narrationVerseMark.drawnFrame, narrationWordMark.drawnFrame)
    }
    #endif

    func capturePosition() {
        // A page's selection is tracked as it changes; its spread records the reading anchor.
        guard !paged else { return }
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
        guard !paged, let state = readerState, let anchor = state.anchor, let map,
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
        // A book page restores only a selection on its own lines; selections stay within one page.
        if let page = pageRange, NSIntersectionRange(page, range) != range { return }
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
        lastUserScroll = CACurrentMediaTime()
        if !decelerate { capturePosition() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        lastUserScroll = CACurrentMediaTime()
        capturePosition()
    }
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { capturePosition() }
    func scrollViewDidScrollToTop(_ scrollView: UIScrollView) { capturePosition() }

    private var scrollDirectionStart: CGFloat = 0
    private var lastScrollY: CGFloat = 0
    private var scrollingDown = false

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        lastUserScroll = CACurrentMediaTime()
        if narrationFocus != nil { scrolledAwayFromNarration = true }
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
        // The facing page resigning must not erase a selection just made on this one.
        if paged, selectedRange.length == 0, !isFirstResponder { selectionDidChange?(); return }
        // A selection stays on the page's own lines, never the covered ones.
        if let page = pageRange, selectedRange.length > 0 {
            let clamped = NSIntersectionRange(page, selectedRange)
            if clamped != selectedRange {
                selectedRange = clamped.length > 0 ? clamped : NSRange(location: page.location, length: 0)
                return
            }
        }
        if windowed != nil {
            // UIKit may create the handles for this selection after this callback; recheck on layout.
            raiseSelectionHandles()
            setNeedsLayout()
        }
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
        resolvedPalette = HighlightColor.allCases.map { ($0, $0.fill.resolvedColor(with: traitCollection)) }
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
        // Starts at the selected words' verse and keeps the selection.
        var readAloudActions: [UIMenuElement] = []
        if let readAloud, let start = map.selection(for: range)?.start {
            readAloudActions = [UIAction(title: String(localized: "Read Aloud from Here"), image: UIImage(systemName: "speaker.wave.2"),
                                         identifier: UIAction.Identifier("readAloudFromHere")) { _ in readAloud(document.id, start) }]
        }
        // "Share Passage" replaces the system Share, which would send the words without their reference.
        return UIMenu(children: annotationActions + [share] + readAloudActions + Self.removingSystemShare(suggestedActions))
    }

    /// The system text menu groups Share in the public `.share` menu; drop that group wherever it is nested.
    private static func removingSystemShare(_ elements: [UIMenuElement]) -> [UIMenuElement] {
        elements.compactMap { element in
            guard let menu = element as? UIMenu else { return element }
            if menu.identifier == .share { return nil }
            return menu.replacingChildren(removingSystemShare(menu.children))
        }
    }


    /// The union of a range's line rectangles; on a book page, only the lines it shows.
    private func visibleFrame(of range: UITextRange) -> CGRect {
        let band = pageBand
        return selectionRects(for: range).reduce(CGRect.null) { rect, selection in
            guard !selection.rect.isEmpty, band.map({ $0.contains(CGPoint(x: $0.midX, y: selection.rect.midY)) }) ?? true else { return rect }
            return rect.union(selection.rect)
        }
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
        // A book page reads only the text it shows: verses and headings outside its band get no
        // elements at all, and a verse split across pages is read as the part on this page.
        let page = pageRange
        func shown(_ range: NSRange) -> NSRange? {
            guard let page else { return range }
            if range.length == 0 { return NSLocationInRange(range.location, page) ? range : nil }
            let visible = NSIntersectionRange(page, range)
            return visible.length > 0 ? visible : nil
        }
        let verses: [(location: Int, element: UIAccessibilityElement)] = map.entries.compactMap { entry in
            guard let visible = shown(entry.range) else { return nil }
            if !rebuildGeometry, !accessibilityDirtyVerses.contains(entry.verse.id), let existing = accessibilityByVerse[entry.verse.id] {
                return (visible.location, existing)
            }
            guard let start = position(from: beginningOfDocument, offset: visible.location),
                  let end = position(from: start, offset: visible.length), let range = textRange(from: start, to: end) else { return nil }
            let existing = accessibilityByVerse[entry.verse.id]
            let element = existing ?? VerseAccessibilityElement(accessibilityContainer: self)
            if visible == entry.range {
                element.accessibilityLabel = "\(document.reference):\(entry.verse.label). \(entry.verse.text)"
            } else {
                let words = (entry.verse.text as NSString).substring(with: NSRange(location: visible.location - entry.range.location, length: visible.length))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                element.accessibilityLabel = visible.location > entry.range.location
                    ? String(localized: "\(document.reference):\(entry.verse.label), continued. \(words)",
                             comment: "VoiceOver label for the rest of a verse that began on the previous book page")
                    : "\(document.reference):\(entry.verse.label). \(words)"
            }
            var annotations: [String] = []
            if let color = readerState?.highlights[entry.verse.id] { annotations.append(color.accessibilityDescription) }
            if readerState?.bookmarks.contains(entry.verse.id) == true { annotations.append(String(localized: "Bookmarked")) }
            if appliedParts[entry.verse.id]?.isEmpty == false {
                annotations.append(String(localized: "Contains highlighted words"))
            }
            if !entry.verse.notes.isEmpty { annotations.append(String(localized: "Has source notes")) }
            element.accessibilityValue = annotations.joined(separator: ", ")
            element.accessibilityTraits = .staticText
            if rebuildGeometry || existing == nil {
                (element as? VerseAccessibilityElement)?.rectProvider = { [weak self] in
                    self?.visibleFrame(of: range) ?? .zero
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
            if !entry.verse.notes.isEmpty {
                let verseID = entry.verse.id
                element.accessibilityCustomActions = (element.accessibilityCustomActions ?? []).filter { $0.name != String(localized: "Show notes") } + [
                    UIAccessibilityCustomAction(name: String(localized: "Show notes")) { [weak self] _ in
                        self?.showNotes(verseID: verseID)
                        return true
                    }]
            }
            let readAloudName = String(localized: "Read aloud from this verse")
            let actions = element.accessibilityCustomActions ?? []
            if readAloud != nil {
                if !actions.contains(where: { $0.name == readAloudName }) {
                    let verseID = entry.verse.id, chapterID = document.id
                    element.accessibilityCustomActions = actions + [UIAccessibilityCustomAction(name: readAloudName) { [weak self] _ in
                        guard let readAloud = self?.readAloud else { return false }
                        readAloud(chapterID, VerseAnchor(verseID: verseID, utf16Offset: 0))
                        return true
                    }]
                }
            } else if actions.contains(where: { $0.name == readAloudName }) {
                element.accessibilityCustomActions = actions.filter { $0.name != readAloudName }
            }
            accessibilityByVerse[entry.verse.id] = element
            return (visible.location, element)
        }
        verseAccessibility = verses.map(\.element)
        accessibilityDirtyVerses.removeAll()
        // Source headings and trailing blocks are read in document order but carry no verse
        // annotation actions; they are source text, not annotation targets.
        let text = map.text as NSString
        let headings: [(location: Int, element: UIAccessibilityElement)] = map.sourceHeadingRanges.compactMap { range in
            guard shown(range) != nil else { return nil }
            if !rebuildGeometry, let existing = accessibilityByHeading[range.location] { return (range.location, existing) }
            guard NSMaxRange(range) <= text.length, let start = position(from: beginningOfDocument, offset: range.location),
                  let end = position(from: start, offset: range.length), let textRange = textRange(from: start, to: end) else { return nil }
            let element = accessibilityByHeading[range.location] ?? VerseAccessibilityElement(accessibilityContainer: self)
            element.accessibilityLabel = text.substring(with: range)
            element.accessibilityTraits = .staticText
            (element as? VerseAccessibilityElement)?.rectProvider = { [weak self] in
                self?.visibleFrame(of: textRange) ?? .zero
            }
            accessibilityByHeading[range.location] = element
            return (range.location, element)
        }
        let ordered = (headings + verses).sorted { $0.location < $1.location }.map(\.element)
        accessibilityElements = [header] + ordered
    }
}

private extension NSAttributedString.Key {
    static let readerHighlightColor = NSAttributedString.Key("BibleReader.HighlightColor")
}

private extension HighlightColor {
    private static let fills: [HighlightColor: UIColor] = Dictionary(uniqueKeysWithValues: allCases.map {
        ($0, UIColor(named: $0.assetName) ?? .clear)
    })
    /// Dynamic asset colors, resolved once instead of per highlighted verse.
    var fill: UIColor { Self.fills[self] ?? .clear }
}

/// A filled shape in the text view's content, behind or in front of the text, that never takes
/// touches and is never read by assistive technologies.
private final class NarrationMarkView: UIView {
    override class var layerClass: AnyClass { CAShapeLayer.self }
    var shape: CAShapeLayer { layer as! CAShapeLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        isHidden = true
    }
    required init?(coder: NSCoder) { fatalError("Not used from a coder") }

    /// What the shape covers, in the text view's content coordinates.
    var drawnFrame: CGRect? {
        guard !isHidden, let bounds = shape.path?.boundingBox, !bounds.isNull else { return nil }
        return bounds.offsetBy(dx: frame.minX, dy: frame.minY)
    }

    /// Sizes the view to the rectangles' union and draws each with `path`.
    func draw(_ rects: [CGRect], path: (CGRect) -> UIBezierPath) {
        let union = rects.reduce(CGRect.null) { $0.union($1) }
        guard !union.isNull, !union.isEmpty else { isHidden = true; return }
        isHidden = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame = union
        let combined = UIBezierPath()
        for rect in rects { combined.append(path(rect.offsetBy(dx: -union.minX, dy: -union.minY))) }
        shape.path = combined.cgPath
        CATransaction.commit()
    }
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
