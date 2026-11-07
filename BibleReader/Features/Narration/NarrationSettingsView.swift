import SwiftUI

/// Read Aloud settings: voice, speed, announcements, and continuation. Separate from Appearance,
/// which controls how text looks.
struct NarrationSettingsView: View {
    let narration: NarrationController
    /// Shown when presented as its own sheet rather than pushed from Appearance.
    var showsCloseButton = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var preferences = narration.preferences
        Form {
            if let reason = narration.unavailableReason {
                Section { Text(reason) }
            }
            Section {
                Picker("Speed", selection: $preferences.rate) {
                    ForEach(NarrationRate.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("narrationSpeed")
            }
            Section {
                Toggle("Announce Chapters", isOn: $preferences.announcesChapters)
                Toggle("Announce Verse Numbers", isOn: $preferences.announcesVerseNumbers)
                Toggle("Continue to Next Chapter", isOn: $preferences.continuesToNextChapter)
            } footer: {
                Text("Announcements apply from the next chapter you start.")
            }
            Section {
                Toggle("Use VoiceOver Voice Settings", isOn: $preferences.usesVoiceOverSettings)
            } footer: {
                Text("When VoiceOver is on, Read Aloud uses your VoiceOver voice and speaking rate.")
            }
            ForEach(NarrationVoice.Quality.allCases.reversed(), id: \.self) { quality in
                let voices = narration.voices.voices.filter { $0.quality == quality }
                if !voices.isEmpty {
                    Section(quality == .personal ? quality.title : String(localized: "\(quality.title) Voices")) {
                        ForEach(voices) { voice in row(voice) }
                    }
                }
            }
            Section {
            } footer: {
                Text("Read Aloud speaks with voices on this device, with no internet connection, and plays even when your device is set to silent. Download higher-quality voices in Settings → Accessibility → Spoken Content → Voices.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.readingCanvas))
        .navigationTitle("Read Aloud")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { dismiss() }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("narrationSettingsDone")
                }
            }
        }
        .onChange(of: preferences.rate) { _, _ in narration.speechSettingsChanged() }
        .onChange(of: preferences.voiceID) { _, _ in narration.speechSettingsChanged() }
        .onChange(of: preferences.usesVoiceOverSettings) { _, _ in narration.speechSettingsChanged() }
        .onDisappear { narration.voices.stopSample() }
    }

    private func row(_ voice: NarrationVoice) -> some View {
        let selected = narration.voices.resolve(narration.preferences.voiceID).voice?.id == voice.id
        return HStack {
            Button {
                narration.preferences.voiceID = voice.id
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(voice.name)
                        Text(Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language)
                            .font(.footnote)
                            .foregroundStyle(Color(.readingSecondary))
                    }
                    Spacer(minLength: 8)
                    if selected {
                        Image(systemName: "checkmark").foregroundStyle(Color(.accent)).accessibilityHidden(true)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            Button {
                if narration.status == .playing { narration.pause(.user) }
                narration.voices.playSample(voice, rate: narration.preferences.rate)
            } label: {
                Image(systemName: "play.circle").frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Play Sample of \(voice.name)")
        }
    }
}
