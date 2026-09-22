import SwiftUI

struct AppearanceView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var preferences: ReaderPreferences

    var body: some View {
        NavigationStack {
            Form {
                Section("Theme") {
                    Picker("Theme", selection: $preferences.theme) {
                        ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                }
                Section {
                    Picker("Reading font", selection: $preferences.typography.face) {
                        ForEach(ReadingFace.allCases) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("readingFacePicker")
                    Stepper(value: $preferences.typography.sizeAdjustment, in: -2...4) {
                        LabeledContent("Text size", value: sizeLabel)
                    }
                    .accessibilityIdentifier("readingSizeStepper")
                    Picker("Line spacing", selection: $preferences.typography.spacing) {
                        ForEach(ReadingSpacing.allCases) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("readingSpacingPicker")
                    Button("Reset reading style") { preferences.resetReadingStyle() }
                } header: {
                    Text("Reading")
                } footer: {
                    Text("Follows your device’s Text Size setting. These adjustments change Scripture text on top of that setting and are saved on this device.")
                }
            }
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("appearanceDoneButton")
                }
            }
        }
        .preferredColorScheme(preferences.theme.colorScheme)
    }

    private var sizeLabel: String {
        let value = preferences.typography.sizeAdjustment
        return value == 0 ? "Default" : (value > 0 ? "+\(value)" : "\(value)")
    }
}
