import SwiftUI

struct AppearanceView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var preferences: ReaderPreferences
    /// Two Pages needs a window that can fit facing pages; see `offersPageLayout`.
    var showsPageLayout = false
    /// Facing pages in a book pose apply only to devices with a hinge.
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
                if showsPageLayout {
                    Section {
                        Picker("Landscape Pages", selection: $preferences.pageLayout) {
                            ForEach(ReadingPageLayout.allCases) { Text($0.title).tag($0) }
                        }
                        .accessibilityIdentifier("pageLayoutPicker")
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
                        Slider(value: sizeStep, in: Double(ReadingTypography.sizeRange.lowerBound)...Double(ReadingTypography.sizeRange.upperBound), step: 1) {
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

    /// Whether to offer the page layout, from live traits rather than the device idiom. Regular
    /// width is the reader's own precondition for facing pages, and a hinge keeps the choice
    /// available on a closed foldable. Two Pages is the default, so compact windows, which
    /// always scroll, need no control.
    static func offersPageLayout(horizontalSizeClass: UserInterfaceSizeClass?, hasHinge: Bool) -> Bool {
        horizontalSizeClass == .regular || hasHinge
    }

    private var pagesFooter: String {
        var parts = [String(localized: "Two Pages shows facing pages that turn like a book when the window is wide enough.")]
        if showsFoldOptions {
            parts.append(String(localized: "Facing pages always open when folded like a book."))
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
