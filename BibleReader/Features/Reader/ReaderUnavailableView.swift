import SwiftUI

/// Explicit missing-content state: never placeholder Scripture.
struct ReaderUnavailableView: View {
    /// Offered when the failure may be temporary, such as a locked device.
    var retry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("Scripture Unavailable")
                    .accessibilityIdentifier("readerUnavailableTitle")
            } icon: {
                Image(systemName: "book.closed")
            }
        } description: {
            Text("The Bible text could not be loaded from this installation.")
        } actions: {
            if let retry {
                Button("Try Again", action: retry)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("readerUnavailableRetry")
            }
        }
        .background(Color(.readingCanvas))
    }
}
