import SwiftUI
import UIKit

struct CompactReaderNavigation: View {
    @Bindable var state: AppState
    @Environment(\.dynamicTypeSize) private var dynamicType

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var collapsed: Bool {
        state.destination == .read && state.reader.navigationCollapsed && !dynamicType.isAccessibilitySize
    }

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            ReaderNavigationLayout(stack: dynamicType.isAccessibilitySize) {
                PassageButton(state: state, compact: true)
                destinations
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
            .frame(height: 64)
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
        bar.accessibilityValue = collapsed ? "Collapsed" : "Expanded"
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
        bar.frame = CGRect(x: -margin, y: 0, width: bounds.width + margin * 2, height: max(bounds.height, size.height))
    }
}

struct PassageButton: View {
    @Bindable var state: AppState
    let compact: Bool

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
            HStack(spacing: 6) {
                ViewThatFits(in: .horizontal) {
                    Text(passageLabel).fixedSize()
                    Text(shortPassageLabel).fixedSize()
                    Text("Chapters").lineLimit(1)
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: compact ? 150 : nil)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            }
            .padding(.horizontal, compact ? 16 : 8)
            .frame(minHeight: compact ? 56 : 44)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(.readingPrimary))
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel("Choose chapter, \(state.reader.document?.reference ?? "Bible")")
        .accessibilityIdentifier("passageButton")
        .popover(isPresented: $state.isChapterPickerPresented) {
            PrototypeChapterPicker(state: state.reader, onClose: { state.isChapterPickerPresented = false }) { if compact { state.destination = .read } }
                .presentationCompactAdaptation(.sheet)
        }
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
private struct ReaderNavigationLayout: Layout {
    var stack: Bool
    private func metrics(_ proposal: ProposedViewSize, _ views: Subviews) -> ([CGSize], CGFloat, Bool) {
        let sizes = views.map { $0.sizeThatFits(.unspecified) }
        let ideal = sizes.reduce(10) { $0 + $1.width }
        let width = proposal.width ?? ideal
        return (sizes, width, stack || ideal > width)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let (sizes, width, stacked) = metrics(proposal, subviews)
        return CGSize(width: width, height: stacked ? sizes[0].height + 10 + 64 : 64)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (sizes, _, stacked) = metrics(proposal, subviews)
        if stacked {
            subviews[0].place(at: CGPoint(x: bounds.midX, y: bounds.minY), anchor: .top,
                              proposal: ProposedViewSize(sizes[0]))
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + sizes[0].height + 10),
                              proposal: ProposedViewSize(width: bounds.width, height: 64))
        } else {
            subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                              proposal: ProposedViewSize(sizes[0]))
            subviews[1].place(at: CGPoint(x: bounds.minX + sizes[0].width + 10, y: bounds.midY), anchor: .leading,
                              proposal: ProposedViewSize(width: bounds.width - sizes[0].width - 10, height: 64))
        }
    }
}
