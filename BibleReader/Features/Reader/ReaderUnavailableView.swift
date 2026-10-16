import SwiftUI

/// Explicit missing-content state: never placeholder Scripture.
struct ReaderUnavailableView: View {
    /// The specific open failure, when known; otherwise a general message is shown.
    var failure: ReaderOpenFailure?
    /// Offered when the failure may be temporary, such as a locked device.
    var retry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(failure?.title ?? String(localized: "Scripture Unavailable"))
                    .accessibilityIdentifier("readerUnavailableTitle")
            } icon: {
                Image(systemName: failure?.kind == .locked ? "lock" : "book.closed")
            }
        } description: {
            Text(failure?.message ?? String(localized: "The Bible text could not be loaded from this installation."))
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
