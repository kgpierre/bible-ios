import SwiftUI

/// Source-edition marginal notes on the reading canvas, visibly separate from Scripture.
struct SourceNotesView: View {
    let request: SourceNotesRequest
    @Environment(\.dismiss) private var dismiss
    /// Measured notes height and the chrome above and below it, so the sheet opens at the notes'
    /// own height instead of a fixed half-screen detent with empty space beneath a short note.
    @State private var contentHeight: CGFloat?
    @State private var chromeHeight: CGFloat = 0
    @State private var detent: PresentationDetent = .medium
    private var fitted: PresentationDetent? { contentHeight.map { .height(($0 + chromeHeight).rounded(.up)) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if request.groups.isEmpty {
                        Text("This chapter has no source notes.")
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(Color(.readingSecondary))
                    }
                    ForEach(request.groups) { group in
                        VStack(alignment: .leading, spacing: 14) {
                            if request.showsVerseLabels {
                                Text("Verse \(group.verseLabel)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color(.accent))
                                    .accessibilityAddTraits(.isHeader)
                            }
                            ForEach(group.notes) { note in
                                VStack(alignment: .leading, spacing: 4) {
                                    if let catchphrase = note.catchphrase {
                                        Text(catchphrase)
                                            .font(.system(.subheadline, design: .serif).italic())
                                            .foregroundStyle(Color(.readingSecondary))
                                    }
                                    Text(note.text)
                                        .font(.system(.body, design: .serif))
                                        .foregroundStyle(Color(.readingPrimary))
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    Text("Marginal notes from the source edition. They are not part of the verse text and are not included when you copy or search.")
                        .font(.footnote)
                        .foregroundStyle(Color(.readingSecondary))
                        .padding(.top, 8)
                }
                .textSelection(.enabled)
                .frame(maxWidth: 640, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    contentHeight = height
                    if let fitted { detent = fitted }
                }
                .frame(maxWidth: .infinity)
            }
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { chrome in
                chromeHeight = chrome
                if let fitted { detent = fitted }
            }
            .background(Color(.readingCanvas))
            .navigationTitle(String(localized: "Notes on \(request.title)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { dismiss() }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("sourceNotesCloseButton")
                }
            }
        }
        .presentationDetents(fitted.map { [$0, .large] } ?? [.medium, .large], selection: $detent)
        .accessibilityIdentifier("sourceNotes")
    }
}
