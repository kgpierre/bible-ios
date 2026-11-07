import SwiftUI

/// Read Aloud settings: voice, speed, announcements, and continuation. Separate from Appearance,
/// which controls how text looks.
struct NarrationSettingsView: View {
    let narration: NarrationController
    /// Shown when presented as its own sheet rather than pushed from Appearance.
    var showsCloseButton = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    /// Shown while only basic voices are installed, and kept for the rest of the visit once shown,
    /// so the finished checklist can offer the new voice.
    @State private var showsVoiceGuide = false

    var body: some View {
        @Bindable var preferences = narration.preferences
        Form {
            if let reason = narration.unavailableReason {
                Section { Text(reason) }
            } else if showsVoiceGuide {
                NarrationVoiceGuide(narration: narration)
            }
            Section {
                Picker("Speed", selection: $preferences.rate) {
                    ForEach(NarrationRate.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("narrationSpeed")
                Picker("Pause Between Verses", selection: $preferences.versePause) {
                    ForEach(NarrationVersePause.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("narrationVersePause")
                if narration.hasPronunciationHints {
                    Toggle("Use Pronunciation Hints", isOn: $preferences.usesPronunciationHints)
                }
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
            personalVoiceSection
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
                Text("Read Aloud speaks with voices on this device, with no internet connection, and plays even when your device is set to silent. Download higher-quality voices in Settings → Accessibility → VoiceOver → Speech → Voice.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.readingCanvas))
        .tint(Color(.accent))
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
        .onChange(of: preferences.versePause) { _, _ in narration.speechSettingsChanged() }
        .onChange(of: preferences.usesPronunciationHints) { _, _ in narration.speechSettingsChanged() }
        .onDisappear { narration.voices.stopSample() }
        .onAppear { if !narration.voices.hasNaturalVoice { showsVoiceGuide = true } }
    }

    /// Personal Voice is used only with the user's permission, and only when they pick it (0023, Q5).
    @ViewBuilder private var personalVoiceSection: some View {
        switch narration.voices.personalVoiceAccess {
        case .notDetermined:
            Section {
                Button("Use My Personal Voice…") { Task { await narration.voices.requestPersonalVoice() } }
                    .accessibilityIdentifier("narrationRequestPersonalVoice")
            } footer: {
                Text("Read Aloud can speak with the Personal Voice you created on this device. It stays on this device.")
            }
        case .denied:
            Section {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } header: {
                Text("Personal Voice")
            } footer: {
                Text("Bible doesn’t have access to your Personal Voice. You can allow it in Settings.")
            }
        case .authorized where !narration.voices.hasPersonalVoice:
            Section("Personal Voice") {
                Text("No Personal Voice is set up on this device. You can create one in Settings → Accessibility → Personal Voice.")
                    .font(.subheadline)
            }
        case .authorized, .unsupported:
            EmptyView()
        }
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
