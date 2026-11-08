import SwiftUI

/// Read Aloud controls, shown on every destination while narration is active because audio
/// continues across tabs.
struct NarrationMiniPlayer: View {
    let narration: NarrationController
    /// Whether the reader shows a different chapter than the one being read aloud.
    var isElsewhere = false
    /// Icon and reference only, like collapsed tab labels while reading.
    var collapsed = false
    /// Inside another glass capsule beside the passage control (the Duo outer display): no glass or
    /// spacer of its own, the verse alone when the chapter beside it already names the book and
    /// chapter, and controls that don't fit move into the options menu.
    var embedded = false
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
            } else if embedded {
                Group {
                    if collapsed {
                        HStack(spacing: 2) { playPause; referenceButton }
                    } else {
                        // Widest first; every visible control keeps a 44-point target.
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 2) { referenceButton; controls; menu() }
                            HStack(spacing: 0) { controls; menu([.showVerse]) }
                            HStack(spacing: 0) { playPause; nextVerse; stop; menu([.showVerse, .previous]) }
                            HStack(spacing: 0) { playPause; stop; menu([.showVerse, .previous, .next]) }
                        }
                    }
                }
                .padding(.trailing, 6)
                .frame(minHeight: 52)
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
        // The spoken reference, even where a narrow capsule leaves no room to show it.
        .accessibilityValue(narration.reference == nil ? "" : fullReferenceText)
        .accessibilityIdentifier("narrationMiniPlayer")
    }

    private var controls: some View {
        HStack(spacing: 0) {
            iconButton("Previous Verse", "backward.fill", id: "narrationPreviousVerse") { narration.skipVerse(by: -1) }
            playPause
            nextVerse
            stop
        }
    }

    private var nextVerse: some View {
        iconButton("Next Verse", "forward.fill", id: "narrationNextVerse") { narration.skipVerse(by: 1) }
    }

    private var stop: some View {
        iconButton("Stop Reading Aloud", "stop.fill", id: "narrationStop") { narration.stop() }
    }

    /// Actions moved into the options menu when the embedded player is too narrow for them.
    private enum MenuExtra { case showVerse, previous, next }

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
        // The full reference even where the passage control beside it shows the chapter.
        .accessibilityLabel(fullReferenceText)
        .accessibilityHint("Shows this verse in the reader")
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("narrationReference")
    }

    private var referenceText: String {
        if embedded, !isElsewhere, narration.reference != nil {
            return narration.verseLabel.map { String(localized: "Verse \($0)") } ?? String(localized: "Read Aloud")
        }
        return fullReferenceText
    }

    private var fullReferenceText: String {
        let reference = narration.reference ?? String(localized: "Preparing…")
        return isElsewhere ? String(localized: "Reading Aloud: \(reference)") : reference
    }

    private var menu: some View { menu() }

    private func menu(_ extras: [MenuExtra] = []) -> some View {
        Menu {
            if !extras.isEmpty {
                Section {
                    if extras.contains(.showVerse) {
                        Button("Show Current Verse", systemImage: "text.viewfinder", action: showReference)
                    }
                    if extras.contains(.previous) {
                        Button("Previous Verse", systemImage: "backward.fill") { narration.skipVerse(by: -1) }
                    }
                    if extras.contains(.next) {
                        Button("Next Verse", systemImage: "forward.fill") { narration.skipVerse(by: 1) }
                    }
                }
            }
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
