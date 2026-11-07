import SwiftUI

/// Read Aloud controls, shown on every destination while narration is active because audio
/// continues across tabs.
struct NarrationMiniPlayer: View {
    let narration: NarrationController
    /// Whether the reader shows a different chapter than the one being read aloud.
    var isElsewhere = false
    /// Icon and reference only, like collapsed tab labels while reading.
    var collapsed = false
    let showReference: () -> Void
    let openSettings: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicType
    /// Icons stop growing here, like system bar items; Large Content Viewer shows them enlarged.
    private static let iconSizeLimit = DynamicTypeSize.xxxLarge

    private var isPlaying: Bool { narration.status == .playing || narration.status == .preparing }

    var body: some View {
        Group {
            if dynamicType.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) { controls; Spacer(minLength: 0); menu }
                    referenceButton
                }
                .padding(12)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
            } else if collapsed {
                HStack(spacing: 2) { playPause; referenceButton }
                    .padding(.horizontal, 6)
                    .frame(minHeight: 52)
                    .glassEffect(.regular, in: .capsule)
            } else {
                HStack(spacing: 2) { referenceButton; Spacer(minLength: 0); controls; menu }
                    .padding(.horizontal, 6)
                    .frame(minHeight: 52)
                    .glassEffect(.regular, in: .capsule)
            }
        }
        .foregroundStyle(Color(.readingPrimary))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Read Aloud")
        .accessibilityIdentifier("narrationMiniPlayer")
    }

    private var controls: some View {
        HStack(spacing: 0) {
            iconButton("Previous Verse", "backward.fill", id: "narrationPreviousVerse") { narration.skipVerse(by: -1) }
            playPause
            iconButton("Next Verse", "forward.fill", id: "narrationNextVerse") { narration.skipVerse(by: 1) }
            iconButton("Stop Reading Aloud", "stop.fill", id: "narrationStop") { narration.stop() }
        }
    }

    private var playPause: some View {
        iconButton(isPlaying ? "Pause" : "Resume", isPlaying ? "pause.fill" : "play.fill", id: "narrationPlayPause") {
            narration.togglePlayPause()
        }
    }

    private var referenceButton: some View {
        Button(action: showReference) {
            Text(referenceText)
                .font(.subheadline.weight(.semibold))
                .lineLimit(dynamicType.isAccessibilitySize ? nil : 1)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 8)
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows this verse in the reader")
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("narrationReference")
    }

    private var referenceText: String {
        let reference = narration.reference ?? String(localized: "Preparing…")
        return isElsewhere ? String(localized: "Reading Aloud: \(reference)") : reference
    }

    private var menu: some View {
        Menu {
            Picker("Speed", systemImage: "gauge.with.dots.needle.67percent", selection: Binding(get: { narration.preferences.rate }, set: {
                narration.preferences.rate = $0
                narration.speechSettingsChanged()
            })) {
                ForEach(NarrationRate.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("narrationSpeed")
            Picker("Sleep Timer", systemImage: "moon.zzz", selection: Binding(get: { narration.sleepTimer }, set: { narration.setSleepTimer($0) })) {
                ForEach(NarrationSleepTimer.choices, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("narrationSleepTimer")
            Button("Read Aloud Settings…", systemImage: "gearshape", action: openSettings)
        } label: {
            Image(systemName: "ellipsis")
                .dynamicTypeSize(...Self.iconSizeLimit)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .accessibilityLabel("Read Aloud Options")
        .accessibilityIdentifier("narrationMenu")
        .accessibilityShowsLargeContentViewer { Label("Read Aloud Options", systemImage: "ellipsis") }
    }

    private func iconButton(_ title: LocalizedStringKey, _ symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .dynamicTypeSize(...Self.iconSizeLimit)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
        .accessibilityShowsLargeContentViewer { Label(title, systemImage: symbol) }
    }
}

extension NarrationSleepTimer {
    var title: String {
        switch self {
        case .off: String(localized: "Off")
        case .endOfChapter: String(localized: "End of Chapter")
        case .minutes(let minutes): String(localized: "\(minutes) Minutes")
        }
    }
}
