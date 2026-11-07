import SwiftUI
import UIKit

struct CompactReaderNavigation: View {
    @Bindable var state: AppState
    @Environment(\.dynamicTypeSize) private var dynamicType

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var collapsed: Bool {
        state.destination == .read && state.reader.navigationCollapsed && !dynamicType.isAccessibilitySize
    }

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 8) {
                // Above the passage selector on every destination, inside the bottom inset, so
                // final verses and chapter controls still scroll clear.
                if state.narration.status.isActive {
                    NarrationMiniPlayer(narration: state.narration, isElsewhere: state.isNarrationElsewhere, collapsed: collapsed,
                                        showReference: { state.showNarratedVerse() },
                                        openSettings: { state.isReadAloudSettingsPresented = true })
                        .frame(maxWidth: .infinity, alignment: collapsed ? .leading : .center)
                }
                ReaderNavigationLayout(stack: dynamicType.isAccessibilitySize, compactHeight: verticalSizeClass == .compact) {
                    PassageButton(state: state)
                    destinations
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: collapsed)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .onChange(of: state.destination) { _, _ in state.reader.navigationCollapsed = false }
    }

    private var destinations: some View {
        NativeReaderTabs(selection: $state.destination, collapsed: collapsed)
            .frame(minWidth: 156, idealWidth: 168, maxWidth: .infinity)
            .frame(height: verticalSizeClass == .compact ? ReaderNavigationLayout.compactHeightBarHeight : 64)
    }
}

/// Native item tracking and selection feedback, within the owner's adjacent-control layout.
private struct NativeReaderTabs: UIViewRepresentable {
    @Binding var selection: AppDestination
    let collapsed: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> ReaderTabBarContainer {
        let container = ReaderTabBarContainer()
        let bar = container.bar
        bar.delegate = context.coordinator
        bar.itemPositioning = .fill
        bar.tintColor = UIColor(resource: .accent)
        bar.unselectedItemTintColor = UIColor(resource: .readingSecondary)
        bar.items = AppDestination.allCases.enumerated().map { index, destination in
            let item = UITabBarItem(title: destination.localizedTitle,
                image: UIImage(systemName: destination.symbol),
                selectedImage: UIImage(systemName: destination.symbol + (destination == .search ? "" : ".fill")))
            item.tag = index
            item.accessibilityLabel = destination.localizedTitle
            item.accessibilityIdentifier = "destination-" + destination.rawValue
            return item
        }
        return container
    }
    func updateUIView(_ container: ReaderTabBarContainer, context: Context) {
        let bar = container.bar
        context.coordinator.parent = self
        bar.accessibilityValue = collapsed ? String(localized: "Collapsed") : String(localized: "Expanded")
        if container.collapsed != collapsed {
            let update = {
                for (index, item) in (bar.items ?? []).enumerated() {
                    item.title = collapsed ? nil : AppDestination.allCases[index].localizedTitle
                }
                bar.layoutIfNeeded()
            }
            if container.collapsed != nil && !UIAccessibility.isReduceMotionEnabled {
                UIView.transition(with: bar, duration: 0.22,
                                  options: [.transitionCrossDissolve, .beginFromCurrentState, .allowUserInteraction],
                                  animations: update)
            } else { update() }
            container.collapsed = collapsed
        }
        bar.selectedItem = bar.items?[AppDestination.allCases.firstIndex(of: selection) ?? 0]
    }
    final class Coordinator: NSObject, UITabBarDelegate {
        var parent: NativeReaderTabs
        init(_ parent: NativeReaderTabs) { self.parent = parent }
        func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            parent.selection = AppDestination.allCases[item.tag]
        }
    }
}

private final class ReaderTabBarContainer: UIView {
    let bar = UITabBar()
    var collapsed: Bool?
    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(bar)
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    override var safeAreaInsets: UIEdgeInsets { .zero }
    override func layoutSubviews() {
        super.layoutSubviews()
        // UITabBar reserves horizontal floating-bar margins of its own. Keep them
        // inside this control's layout rather than squeezing its three native items.
        let margin: CGFloat = 20
        let size = bar.sizeThatFits(CGSize(width: bounds.width + margin * 2, height: bounds.height))
        let frame = CGRect(x: -margin, y: 0, width: bounds.width + margin * 2, height: max(bounds.height, size.height))
        if bar.frame != frame { bar.frame = frame }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        // Items configured before the bar joins a window keep a provisional layout: at launch the
        // selected "Read" rode higher than Saved/Search until titles next changed. Re-apply titles
        // and selection once the bar has its window traits and final size.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            let bar = self.bar, selected = bar.selectedItem
            for item in bar.items ?? [] {
                let title = item.title
                item.title = nil
                item.title = title
            }
            bar.selectedItem = nil
            bar.selectedItem = selected
            bar.layoutIfNeeded()
        }
    }
}

struct PassageButton: View {
    @Bindable var state: AppState
    /// A narrow stacked label for the side rail (book, chapter, chevron).
    var vertical = false

    private var passageLabel: String { state.reader.document?.reference ?? String(localized: "Chapters") }
    private var shortPassageLabel: String {
        guard let document = state.reader.document,
              let book = state.reader.books.first(where: { $0.id == document.bookID }) else { return passageLabel }
        return "\(book.shortName) \(document.label)"
    }

    var body: some View {
        Button {
            state.isChapterPickerPresented = true
        } label: {
            if vertical { verticalLabel } else {
            // Each option is a complete label, so ViewThatFits compares against the proposed
            // width directly. Nesting it in an HStack re-proposed its own measured width,
            // where rounding could reject a label that fits ("Jhn 3" beside empty space).
            ViewThatFits(in: .horizontal) {
                label(Text(passageLabel).fixedSize())
                label(Text(shortPassageLabel).fixedSize())
                label(Text("Chapters").lineLimit(1))
            }
            .contentShape(.capsule)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(.readingPrimary))
        .glassEffect(.regular.interactive(), in: vertical ? AnyShape(.rect(cornerRadius: 28)) : AnyShape(.capsule))
        .accessibilityLabel("Choose chapter, \(state.reader.document?.reference ?? "Bible")")
        .accessibilityIdentifier("passageButton")
        .popover(isPresented: $state.isChapterPickerPresented) {
            PrototypeChapterPicker(state: state.reader, onClose: { state.isChapterPickerPresented = false }) { state.destination = .read }
                .presentationCompactAdaptation(.sheet)
        }
    }
}

extension PassageButton {
    private var verticalLabel: some View {
        let book = state.reader.document.flatMap { document in state.reader.books.first { $0.id == document.bookID } }
        return VStack(spacing: 2) {
            Text(book?.shortName ?? String(localized: "Chapters"))
                .font(.footnote.weight(.semibold))
            if let label = state.reader.document?.label {
                Text(label).font(.title3.weight(.semibold))
            }
            Image(systemName: "chevron.down").font(.caption.weight(.semibold))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        // Fills the rail's width so it matches the destinations and the system toolbar column.
        .frame(minWidth: ReaderLayout.minimumControlTarget, maxWidth: .infinity, minHeight: 64)
        .contentShape(.rect(cornerRadius: 28))
    }

    private func label(_ title: some View) -> some View {
        HStack(spacing: 6) {
            title.font(.body.weight(.semibold))
            Image(systemName: "chevron.down").font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
    }
}

#if DEBUG
/// Comparison fixture: verify the system accessory's actual arrangement before choosing custom chrome.
struct NativeTabsProbe: View {
    var body: some View {
        TabView {
            Tab("Read", systemImage: "book") { Color(.readingCanvas) }
            Tab("Saved", systemImage: "bookmark") { Text("Saved") }
            Tab("Search", systemImage: "magnifyingglass") { Text("Search") }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewBottomAccessory { Text("John 3").padding() }
    }
}
#endif

/// Keep a single identity for each control when chrome expands or reflows.
/// Reserving bar height also avoids changing the text viewport during a drag.
/// The passage label is proposed the space the tabs leave, so its `ViewThatFits`
/// chooses the longest label that fits instead of an exact, rounding-sensitive ideal width.
private struct ReaderNavigationLayout: Layout {
    var stack: Bool
    /// Landscape phones: the tab capsule lays its labels beside the icons and is wider, so it gets a
    /// bounded region (not all remaining width) and both controls share one baseline.
    var compactHeight = false
    static let compactHeightBarHeight: CGFloat = 56
    private let spacing: CGFloat = 10
    private var tabsWidth: CGFloat { compactHeight ? 280 : 168 }
    private var barHeight: CGFloat { compactHeight ? Self.compactHeightBarHeight : 64 }

    private func metrics(_ proposal: ProposedViewSize, _ views: Subviews)
        -> (passage: CGSize, available: CGFloat, width: CGFloat, stacked: Bool) {
        let width = proposal.width ?? views[0].sizeThatFits(.unspecified).width + spacing + tabsWidth
        if !stack {
            let available = max(0, width - spacing - tabsWidth)
            let passage = views[0].sizeThatFits(ProposedViewSize(width: available, height: nil))
            // Stack only when even the shortest label cannot sit beside the tabs.
            if passage.width <= available + 0.5 { return (passage, available, width, false) }
        }
        return (views[0].sizeThatFits(ProposedViewSize(width: width, height: nil)), width, width, true)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let (passage, _, width, stacked) = metrics(proposal, subviews)
        return CGSize(width: width, height: stacked ? passage.height + spacing + barHeight : barHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (passage, available, _, stacked) = metrics(ProposedViewSize(width: bounds.width, height: bounds.height), subviews)
        if stacked {
            subviews[0].place(at: CGPoint(x: bounds.midX, y: bounds.minY), anchor: .top,
                              proposal: ProposedViewSize(width: bounds.width, height: passage.height))
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + passage.height + spacing),
                              proposal: ProposedViewSize(width: bounds.width, height: barHeight))
        } else {
            subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                              proposal: ProposedViewSize(width: available, height: passage.height))
            subviews[1].place(at: CGPoint(x: bounds.minX + passage.width + spacing, y: bounds.midY), anchor: .leading,
                              proposal: ProposedViewSize(width: compactHeight ? min(tabsWidth, bounds.width - passage.width - spacing) : bounds.width - passage.width - spacing, height: barHeight))
        }
    }
}

/// Duo outer display: Read/Saved/Search as a vertical glass capsule beneath the system's vertical
/// toolbar, with the passage control above it. Lives in the trailing safe-area column the system
/// reserves for the status bar and toolbar, so reading text never runs under it.
struct SideReaderNavigation: View {
    @Bindable var state: AppState
    let columnWidth: CGFloat
    @Namespace private var glass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One width for the passage control and destinations, matching the system's vertical toolbar
    /// pill above them (owner request, 7 November 2026). Destinations keep 44-point targets.
    private var railWidth: CGFloat { min(ReaderLayout.sideRailControlWidth, max(ReaderLayout.minimumControlTarget + 3, columnWidth - 8)) }

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 10) {
                PassageButton(state: state, vertical: true)
                    .frame(width: railWidth)
                VStack(spacing: 2) {
                    ForEach(AppDestination.allCases) { destination in
                        SideTabButton(destination: destination, selected: state.destination == destination, glass: glass) {
                            state.destination = destination
                        }
                    }
                }
                .padding(2)
                .frame(width: railWidth)
                // Not interactive as a whole: each destination answers touch on its own lens, so a
                // press never lights up all three (owner feedback, 7 November 2026).
                .glassEffect(.regular, in: .rect(cornerRadius: 28))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("sideDestinations")
            }
        }
        // The selection lens morphs between destinations, from taps and keyboard shortcuts alike;
        // Reduce Motion moves it without animation.
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: state.destination)
        // Centered on the system toolbar column above, which sits left of the safe-area column's middle.
        .padding(.leading, max(0, ReaderLayout.sideRailCenterInset - railWidth / 2))
        .frame(width: columnWidth, alignment: .leading)
        .padding(.bottom, 8)
    }
}

/// Icon-only on the Duo outer display (owner refinement, 7 November 2026): the narrow rail has no
/// room for labels. VoiceOver and Large Content Viewer still name each destination. The rail only
/// appears below accessibility sizes, where the bottom bars keep visible labels.
private struct SideTabButton: View {
    let destination: AppDestination
    let selected: Bool
    let glass: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: destination.symbol + (selected && destination != .search ? ".fill" : ""))
                .font(.title3)
                .foregroundStyle(selected ? Color(.accent) : Color(.readingSecondary))
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(SideTabButtonStyle(selected: selected, glass: glass))
        .accessibilityLabel(destination.localizedTitle)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityShowsLargeContentViewer {
            Image(systemName: destination.symbol)
            Text(destination.localizedTitle)
        }
        .help(destination.localizedTitle)
        .accessibilityIdentifier("destination-" + destination.rawValue)
    }
}

/// The selection is a tinted glass lens, like the system tab bar's; one ID across destinations lets
/// the container morph it from the old tab to the new one. A pressed destination gets its own clear
/// lens, so touch feedback stays on the item under the finger.
private struct SideTabButtonStyle: ButtonStyle {
    let selected: Bool
    let glass: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if selected {
                    Capsule()
                        .fill(.clear)
                        .glassEffect(.regular.tint(Color(.accent).opacity(0.28)), in: .capsule)
                        .glassEffectID("selection", in: glass)
                } else if configuration.isPressed {
                    Capsule()
                        .fill(.clear)
                        .glassEffect(.regular, in: .capsule)
                }
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: configuration.isPressed)
            .contentShape(.capsule)
    }
}

/// The bottom band reserved for Read Aloud's mini player when navigation moves to the side rail.
struct SideNarrationInset: View {
    @Bindable var state: AppState
    @Environment(\.dynamicTypeSize) private var dynamicType

    var body: some View {
        if state.narration.status.isActive {
            NarrationMiniPlayer(narration: state.narration, isElsewhere: state.isNarrationElsewhere,
                                collapsed: state.destination == .read && state.reader.navigationCollapsed && !dynamicType.isAccessibilitySize,
                                showReference: { state.showNarratedVerse() },
                                openSettings: { state.isReadAloudSettingsPresented = true })
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)
        }
    }
}
