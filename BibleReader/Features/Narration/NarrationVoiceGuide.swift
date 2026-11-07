import SwiftUI

/// A checklist for downloading a natural voice (owner request, 7 November 2026). Apps can't download
/// voices or open that screen, so each step is guidance the reader can tick off; the last step
/// completes on its own when a new Enhanced or Premium voice arrives.
struct NarrationVoiceGuide: View {
    let narration: NarrationController
    @State private var done: Set<Step> = []

    enum Step: Int, CaseIterable, Identifiable {
        case accessibility, speech, choose, download
        var id: Self { self }
        var title: LocalizedStringKey {
            switch self {
            case .accessibility: "Open Settings, then Accessibility"
            case .speech: "Tap VoiceOver, then Speech, then Voice"
            case .choose: "Choose English, then a voice like Ava or Zoe"
            case .download: "Download its Premium or Enhanced version"
            }
        }
    }

    /// The best newly available natural voice, once there is one.
    private var naturalVoice: NarrationVoice? {
        narration.voices.voices.first { $0.quality == .premium || $0.quality == .enhanced }
    }

    var body: some View {
        Section {
            ForEach(Step.allCases) { step in
                let checked = step == .download ? naturalVoice != nil : done.contains(step)
                Button {
                    guard step != .download else { return }
                    if done.contains(step) { done.remove(step) } else { done.insert(step) }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(checked ? Color(.accent) : Color(.readingSecondary))
                            .contentTransition(.symbolEffect(.replace))
                            .accessibilityHidden(true)
                        Text(step.title)
                            .foregroundStyle(Color(.readingPrimary))
                            .strikethrough(checked && step != .download, color: Color(.readingSecondary))
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(step == .download)
                .accessibilityValue(checked ? String(localized: "Done") : String(localized: "Not done"))
                .accessibilityHint(step == .download ? "Completes when the voice finishes downloading" : "Marks this step done")
                .accessibilityIdentifier("voiceGuideStep-\(step.rawValue)")
            }
            if let voice = naturalVoice {
                let selected = narration.voices.resolve(narration.preferences.voiceID).voice?.id == voice.id
                Button(selected ? "Using \(voice.name) (\(voice.quality.title))" : "Use \(voice.name) (\(voice.quality.title))") {
                    narration.preferences.voiceID = voice.id
                }
                .disabled(selected)
                .accessibilityIdentifier("voiceGuideUseVoice")
            }
        } header: {
            Text("Get More Natural Voices")
        } footer: {
            Text("You don’t need to turn VoiceOver on. Downloaded voices work in every app, and new ones appear here when they finish.")
        }
        .animation(.default, value: done)
        .animation(.default, value: naturalVoice?.id)
    }
}
