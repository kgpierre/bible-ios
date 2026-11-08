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
    /// Inside another glass capsule (beside Read Aloud's player), so it draws no glass of its own.
    var embedded = false

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
        .buttonStyle(.plain)
        .foregroundStyle(Color(.readingPrimary))
        .modifier(PassageGlass(enabled: !embedded))
        .accessibilityLabel("Choose chapter, \(state.reader.document?.reference ?? "Bible")")
        .accessibilityIdentifier("passageButton")
        .popover(isPresented: $state.isChapterPickerPresented) {
            PrototypeChapterPicker(state: state.reader, onClose: { state.isChapterPickerPresented = false }) { state.destination = .read }
                .presentationCompactAdaptation(.sheet)
        }
    }
}

extension PassageButton {
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

private struct PassageGlass: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.glassEffect(.regular.interactive(), in: .capsule) } else { content }
    }
}

/// The bottom-trailing chapter control beside the system tab bar (regular width and the iPhone Duo),
/// with Read Aloud's player while it's active. Where there's room they share one glass capsule;
/// accessibility sizes stack the player above it (owner direction, 7 November 2026).
struct PassageControls: View {
    @Bindable var state: AppState
    /// One capsule beside each other when true; otherwise stacked.
    let mergesPlayer: Bool
    var collapsed = false
    /// A stacked player's widest extent; nil fills the band.
    var playerMaxWidth: CGFloat?
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            if !state.narration.status.isActive {
                PassageButton(state: state)
            } else if mergesPlayer && !dynamicType.isAccessibilitySize {
                HStack(spacing: 0) {
                    // The chapter keeps its full label; the player drops controls into its menu instead.
                    PassageButton(state: state, embedded: true)
                        .fixedSize()
                    Divider().frame(height: 28)
                    player(embedded: true)
                }
                .glassEffect(.regular, in: .capsule)
            } else {
                VStack(alignment: .trailing, spacing: 8) {
                    player(embedded: false)
                        .frame(maxWidth: collapsed ? nil : playerMaxWidth ?? .infinity, alignment: .trailing)
                    PassageButton(state: state)
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: collapsed)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: state.narration.status.isActive)
    }

    private func player(embedded: Bool) -> some View {
        NarrationMiniPlayer(narration: state.narration, isElsewhere: state.isNarrationElsewhere,
                            collapsed: collapsed, embedded: embedded,
                            showReference: { state.showNarratedVerse() },
                            openSettings: { state.isReadAloudSettingsPresented = true })
    }
}

/// A vertical glass capsule of controls in the Duo's vertical bar, with a lens
/// like the system tab bar's (owner requests, 7 November 2026): touching lifts a clear glass lens
/// behind the control under the finger, the lens follows a drag, and releasing over a control
/// reports its index. A plain tap is left to the control itself; releasing well outside the capsule
/// cancels. With `selectedIndex`, a tinted lens rests on the selection and the drag lens morphs
/// from and back into it. Taps, VoiceOver, and keyboard use the controls themselves.
struct SideLensStack<Content: View>: View {
    let count: Int
    var selectedIndex: Int?
    /// Touches starting here belong to the control (a menu opens on press), not the lens.
    var passthroughIndex: Int?
    let onRelease: (Int) -> Void
    /// Receives the index under the finger while pressing or dragging.
    @ViewBuilder let content: (Int?) -> Content
    /// Resets on its own when the system cancels the touch, so the lens can't stick.
    @GestureState private var touchY: CGFloat?
    @Namespace private var glass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static var itemHeight: CGFloat { 48 }
    private static var itemSpacing: CGFloat { 2 }
    private static var inset: CGFloat { 2 }
    /// How far past the capsule a release still counts, like the system tab bar's slop.
    private static var releaseSlop: CGFloat { 28 }
    private var width: CGFloat { ReaderLayout.sideRailControlWidth }
    private var height: CGFloat {
        Self.inset * 2 + CGFloat(count) * Self.itemHeight + CGFloat(max(0, count - 1)) * Self.itemSpacing
    }
    private var hoveredIndex: Int? { touchY.map(index(at:)) }

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: Self.itemSpacing) {
                Group(subviews: content(hoveredIndex)) { subviews in
                    ForEach(subviews) { subview in
                        subview
                            .frame(maxWidth: .infinity, minHeight: Self.itemHeight, maxHeight: Self.itemHeight)
                            .contentShape(.capsule)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(Self.inset)
            .frame(width: width)
            // Behind the controls, so the icon under the finger stays visible through the lens.
            .background(alignment: .top) { lens }
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
            .simultaneousGesture(gesture)
            .sensoryFeedback(.selection, trigger: hoveredIndex) { old, new in old != nil && new != nil }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: touchY == nil)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: selectedIndex)
    }

    @ViewBuilder private var lens: some View {
        if let touchY {
            let size = CGSize(width: width + 10, height: Self.itemHeight + 8)
            Capsule()
                .fill(.clear)
                .glassEffect(.regular.tint(Color(.accent).opacity(0.14)).interactive(), in: .capsule)
                .glassEffectID("lens", in: glass)
                .frame(width: size.width, height: size.height)
                .offset(y: lensCenter(for: touchY) - size.height / 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else if let selectedIndex {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular.tint(Color(.accent).opacity(0.28)), in: .capsule)
                .glassEffectID("lens", in: glass)
                .frame(width: width - Self.inset * 2, height: Self.itemHeight)
                .offset(y: itemCenter(selectedIndex) - Self.itemHeight / 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var gesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($touchY) { value, touchY, _ in
                if let passthroughIndex, index(at: value.startLocation.y) == passthroughIndex { return }
                touchY = value.location.y
            }
            .onEnded { value in
                if let passthroughIndex, index(at: value.startLocation.y) == passthroughIndex { return }
                // A tap belongs to the control under it.
                guard hypot(value.translation.width, value.translation.height) >= 6 else { return }
                let slop = Self.releaseSlop
                guard value.location.x > -slop, value.location.x < width + slop,
                      value.location.y > -slop, value.location.y < height + slop else { return }
                onRelease(index(at: value.location.y))
            }
    }

    private func index(at y: CGFloat) -> Int {
        let index = Int(((y - Self.inset) / (Self.itemHeight + Self.itemSpacing)).rounded(.down))
        return min(max(index, 0), count - 1)
    }

    private func itemCenter(_ index: Int) -> CGFloat {
        Self.inset + CGFloat(index) * (Self.itemHeight + Self.itemSpacing) + Self.itemHeight / 2
    }

    /// Follows the finger within the capsule; Reduce Motion snaps it to the control under it.
    private func lensCenter(for y: CGFloat) -> CGFloat {
        if reduceMotion { return itemCenter(index(at: y)) }
        return min(max(y, itemCenter(0)), itemCenter(count - 1))
    }
}
