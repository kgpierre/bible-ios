import SwiftUI

struct CompactReaderNavigation: View {
    @Bindable var state: AppState
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var collapsed: Bool {
        state.destination == .read && state.reader.navigationCollapsed && !dynamicType.isAccessibilitySize
    }

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            ReaderNavigationLayout(stack: dynamicType.isAccessibilitySize) {
                PassageButton(state: state, compact: true)
                destinations
                books
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: collapsed)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var books: some View {
        Button { state.isBooksPresented = true } label: {
            VStack(spacing: 3) {
                Image(systemName: "books.vertical").font(.system(size: 20))
                if !collapsed { Text("Books").font(.caption2.weight(.medium)) }
            }
            .frame(minWidth: 52, minHeight: collapsed ? 52 : 64)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(.accent))
        .background(reduceTransparency ? Color(.readingCanvas) : .clear, in: .capsule)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel("Books")
        .accessibilityIdentifier("booksButton")
    }

    private var destinations: some View {
        HStack(spacing: 0) {
            ForEach(AppDestination.allCases) { destination in
                DestinationButton(destination: destination, selected: state.destination == destination, collapsed: collapsed) {
                    state.destination = destination
                    state.reader.navigationCollapsed = false
                }
            }
        }
        .padding(6)
        .background(reduceTransparency ? Color(.readingCanvas) : .clear, in: .capsule)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Reader destinations")
    }
}

private struct DestinationButton: View {
    let destination: AppDestination
    let selected: Bool
    let collapsed: Bool
    let action: () -> Void

    private var symbol: String {
        destination.symbol + (selected && destination != .search ? ".fill" : "")
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 20))
                if !collapsed { Text(destination.title).font(.caption2.weight(.medium)) }
            }
            .frame(minWidth: 44, maxWidth: .infinity, minHeight: collapsed ? 44 : 52)
            .padding(.horizontal, 2)
            .contentShape(.rect)
            .foregroundStyle(selected ? Color(.accent) : Color(.readingSecondary))
            .background(selected ? Color(.accent).opacity(0.12) : .clear, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(destination.title))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("destination-\(destination.rawValue)")
    }
}

struct PassageButton: View {
    @Bindable var state: AppState
    let compact: Bool

    private var passageLabel: String {
        guard let document = state.reader.document else { return "Chapters" }
        if compact, document.bookName.count > 8,
           let book = state.reader.books.first(where: { $0.id == document.bookID }) {
            return "\(book.shortName) \(document.label)"
        }
        return document.reference
    }

    var body: some View {
        Button {
            state.isChapterPickerPresented = true
        } label: {
            HStack(spacing: 6) {
                Text(passageLabel)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .font(.body.weight(.semibold))
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
            PrototypeChapterPicker(state: state.reader) { if compact { state.destination = .read } }
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
        let ideal = sizes.reduce(20) { $0 + $1.width }
        let width = proposal.width ?? ideal
        return (sizes, width, stack || ideal > width)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let (sizes, width, stacked) = metrics(proposal, subviews)
        let height = stacked ? max(64, max(sizes[0].height, sizes[2].height)) + 10 + max(64, sizes[1].height) : max(64, sizes.map(\.height).max() ?? 64)
        return CGSize(width: width, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (sizes, _, stacked) = metrics(proposal, subviews)
        if stacked {
            let topHeight = max(64, max(sizes[0].height, sizes[2].height))
            let groupWidth = sizes[0].width + 10 + sizes[2].width
            let start = bounds.midX - groupWidth / 2
            subviews[0].place(at: CGPoint(x: start, y: bounds.minY + topHeight / 2), anchor: .leading, proposal: ProposedViewSize(sizes[0]))
            subviews[2].place(at: CGPoint(x: start + sizes[0].width + 10, y: bounds.minY + topHeight / 2), anchor: .leading, proposal: ProposedViewSize(sizes[2]))
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + topHeight + 10), proposal: ProposedViewSize(width: bounds.width, height: max(64, sizes[1].height)))
        } else {
            subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(sizes[0]))
            subviews[1].place(at: CGPoint(x: bounds.minX + sizes[0].width + 10, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(width: bounds.width - sizes[0].width - sizes[2].width - 20, height: sizes[1].height))
            subviews[2].place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing, proposal: ProposedViewSize(sizes[2]))
        }
    }
}
