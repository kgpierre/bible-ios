import SwiftUI

struct AppearanceView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var preferences: ReaderPreferences
    /// Two Pages needs a display that can fit facing pages (iPad or a foldable's inner display).
    var showsPageLayout = false
    /// Book layout applies only to devices with a hinge.
    var showsFoldOptions = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Theme") {
                    Picker("Theme", selection: $preferences.theme) {
                        ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityIdentifier("themePicker")
                }
                if showsPageLayout || showsFoldOptions {
                    Section {
                        if showsPageLayout {
                            Picker("Landscape Pages", selection: $preferences.pageLayout) {
                                ForEach(ReadingPageLayout.allCases) { Text($0.title).tag($0) }
                            }
                            .accessibilityIdentifier("pageLayoutPicker")
                        }
                        if showsFoldOptions {
                            Toggle("Book Layout When Folded", isOn: $preferences.automaticBookLayout)
                                .accessibilityIdentifier("automaticBookLayoutToggle")
                        }
                    } header: {
                        Text("Pages")
                    } footer: {
                        Text(pagesFooter)
                    }
                }
                Section {
                    Picker("Reading Font", selection: $preferences.typography.face) {
                        ForEach(ReadingFace.allCases) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("readingFacePicker")
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent("Text Size", value: sizeLabel)
                            .accessibilityHidden(true)
                        // Whole steps only: each one is a 2-point change on top of Dynamic Type.
                        Slider(value: sizeStep, in: -2...4, step: 1) {
                            Text("Text Size")
                        } minimumValueLabel: {
                            Image(systemName: "textformat.size.smaller").accessibilityHidden(true)
                        } maximumValueLabel: {
                            Image(systemName: "textformat.size.larger").accessibilityHidden(true)
                        }
                        .accessibilityValue(sizeLabel)
                        .accessibilityIdentifier("readingSizeSlider")
                    }
                    Picker("Line Spacing", selection: $preferences.typography.spacing) {
                        ForEach(ReadingSpacing.allCases) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("readingSpacingPicker")
                } header: {
                    Text("Reading")
                } footer: {
                    Text("Follows your device’s Text Size setting. These adjustments change Scripture text on top of that setting and are saved on this device.")
                }
                Section {
                    Toggle("Show Source Notes", isOn: $preferences.typography.showsNotes)
                        .accessibilityIdentifier("sourceNotesToggle")
                } footer: {
                    Text("Marks verses that have marginal notes from the source edition. Tap a marked verse number to read them.")
                }
                Section {
                    Button("Reset Reading Style") { preferences.resetReadingStyle() }
                        .accessibilityIdentifier("resetReadingStyle")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(.readingCanvas))
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { dismiss() }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("appearanceDoneButton")
                }
            }
        }
        .tint(Color(.accent))
        .preferredColorScheme(preferences.theme.colorScheme)
    }

    private var pagesFooter: String {
        var parts: [String] = []
        if showsPageLayout {
            parts.append(String(localized: "Two Pages shows facing pages that turn like a book when the window is wide enough."))
        }
        if showsFoldOptions {
            parts.append(String(localized: "Book layout automatically uses facing pages when folded like a book. Turn it off to keep continuous scrolling while folded."))
        }
        parts.append(String(localized: "Narrow windows and accessibility text sizes use scrolling. A selection stays within one page."))
        return parts.joined(separator: " ")
    }

    private var sizeStep: Binding<Double> {
        Binding(get: { Double(preferences.typography.sizeAdjustment) },
                set: { preferences.typography.sizeAdjustment = Int($0.rounded()) })
    }

    private var sizeLabel: String {
        let value = preferences.typography.sizeAdjustment
        return value == 0 ? "Default" : (value > 0 ? "+\(value)" : "\(value)")
    }
}
