import SwiftUI
import UIKit

/// Owner-supplied identity. Keep links user-initiated; the app never fetches them itself.
enum AppInfo {
    static let name = "Bible"
    static let author = "Kyle Pierre"
    static let authorURL = URL(string: "https://kpierre.dev")!
    /// Set to the donation page (for example Ko-fi, Buy Me a Coffee, or GitHub Sponsors).
    /// While nil, the Support button stays visible but disabled.
    static let donationURL: URL? = nil
    static let scriptureSourceURL = URL(string: "https://ebible.org/find/show.php?id=eng-kjv")!
    static let grdbURL = URL(string: "https://github.com/groue/GRDB.swift")!

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return String(localized: "Version \(short) (\(build))")
    }
}

struct AboutView: View {
    let editionNotice: String
    let close: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        AppIconMark()
                        Text(AppInfo.name)
                            .readerTypography(.bookTitle)
                            .foregroundStyle(Color(.readingPrimary))
                            .accessibilityAddTraits(.isHeader)
                        Text(AppInfo.version)
                            .font(.subheadline).foregroundStyle(Color(.readingSecondary))
                        Text("A quiet, private King James Bible. Every book is on your device and works offline, with no accounts, ads, or tracking.")
                            .font(.body).multilineTextAlignment(.center)
                            .foregroundStyle(Color(.readingPrimary))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section {
                    ExternalLinkRow(title: "Made by \(AppInfo.author)", systemImage: "person.crop.circle",
                                    destination: AppInfo.authorURL)
                        .accessibilityHint("Opens the author’s website")
                }

                // Shown only once a donation page exists; a permanently disabled button offers nothing.
                if let donationURL = AppInfo.donationURL {
                    Section {
                        Button {
                            openURL(donationURL)
                        } label: {
                            Label("Support Development", systemImage: "heart.fill")
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 36)
                        }
                        .buttonStyle(.borderedProminent)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .accessibilityIdentifier("donateButton")
                    } footer: {
                        Text("\(AppInfo.name) is free. If it helps you, you can support its development. Donations are optional and unlock nothing.")
                    }
                }

                Section("Scripture") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("King James Version").font(.headline)
                        Text("Standardized 1769 text, 66 books. Provided by CrossWire Bible Society and eBible.org. Source files dated 17 September 2026, retrieved 21 September 2026.")
                            .font(.subheadline).foregroundStyle(Color(.readingSecondary))
                    }
                    ExternalLinkRow(title: "eBible.org Source", systemImage: "globe", destination: AppInfo.scriptureSourceURL)
                    NavigationLink {
                        NoticePage(title: "Edition Notice", text: editionNotice)
                    } label: {
                        Label("Edition Notice", systemImage: "doc.text")
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("GRDB.swift").font(.headline)
                        Text("SQLite toolkit by Gwendal Roué. MIT License.")
                            .font(.subheadline).foregroundStyle(Color(.readingSecondary))
                    }
                    ExternalLinkRow(title: "GRDB.swift on GitHub", systemImage: "globe", destination: AppInfo.grdbURL)
                    NavigationLink {
                        NoticePage(title: "GRDB License", text: Self.bundledText("GRDB-LICENSE"))
                    } label: {
                        Label("GRDB License", systemImage: "doc.text")
                    }
                } header: {
                    Text("Software")
                } footer: {
                    Text("Chapter summaries are generated on this device by Apple Intelligence when available. They are not Scripture and may contain mistakes.")
                }

                Section("Privacy") {
                    Text("Highlights, bookmarks, and reading position are saved on this device. No accounts, tracking, or app-operated sync. Device backups may include your saved data.")
                        .font(.subheadline)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(.readingCanvas))
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .tint(Color(.accent))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close, action: close)
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("aboutCloseButton")
                }
            }
        }
    }

    private static func bundledText(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }
}

/// A row that leaves the app: leading symbol, primary title, trailing outbound arrow.
private struct ExternalLinkRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let destination: URL
    var body: some View {
        Link(destination: destination) {
            HStack {
                Label {
                    Text(title).foregroundStyle(Color(.readingPrimary))
                } icon: {
                    Image(systemName: systemImage)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(.readingSecondary))
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct NoticePage: View {
    let title: LocalizedStringKey
    let text: String
    var body: some View {
        ScrollView {
            Text(text)
                .font(.footnote)
                .foregroundStyle(Color(.readingPrimary))
                .textSelection(.enabled)
                .frame(maxWidth: 640, alignment: .leading)
                .padding(20)
                .frame(maxWidth: .infinity)
        }
        .background(Color(.readingCanvas))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Shows the "AboutIcon" image once the final app icon artwork is added to the asset catalog;
/// until then, a neutral placeholder in the app's accent color.
private struct AppIconMark: View {
    @ScaledMetric(relativeTo: .largeTitle) private var size = 88.0
    var body: some View {
        Group {
            if let icon = UIImage(named: "AboutIcon") {
                Image(uiImage: icon).resizable().scaledToFill()
            } else {
                ZStack {
                    Color(.accent)
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: size * 0.42, weight: .medium))
                        .foregroundStyle(Color(.readingCanvas))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.225, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .strokeBorder(Color(.readingSecondary).opacity(0.2), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}
