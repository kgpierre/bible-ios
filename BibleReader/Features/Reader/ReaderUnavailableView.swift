import SwiftUI

/// Explicit missing-content state until the validated bundled corpus is introduced.
struct ReaderUnavailableView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ReaderLayout.sectionSpacing) {
                Text("Scripture unavailable")
                    .readerTypography(.bookTitle)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("readerUnavailableTitle")
                Text("The Bible text could not be loaded from this installation.")
                    .font(.body)
                    .foregroundStyle(Color(.readingSecondary))
            }
            .frame(maxWidth: ReaderLayout.maximumColumnWidth, alignment: .leading)
            .padding(ReaderLayout.outerMargin)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .foregroundStyle(Color(.readingPrimary))
        .background(Color(.readingCanvas))
    }
}
