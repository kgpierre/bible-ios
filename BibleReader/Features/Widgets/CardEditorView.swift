import ImagePlayground
import PhotosUI
import SwiftUI

/// Designs one widget card: background (preset, Image Playground, or photo), ink, and typeface.
/// The Scripture text is fixed; only presentation changes here.
struct CardEditorView: View {
    let model: CardsModel
    let isRoot: Bool
    let onFinish: () -> Void
    @State private var card: ScriptureCard
    @State private var family: CardFamily = .medium
    @State private var pendingBackground: PreparedBackground?
    @State private var pendingImage: Image?
    @State private var savedImage: Image?
    @State private var isPlaygroundPresented = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isPreparingImage = false
    @State private var imageError: String?
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss

    init(card: ScriptureCard, model: CardsModel, isRoot: Bool, onFinish: @escaping () -> Void) {
        _card = State(initialValue: card)
        self.model = model
        self.isRoot = isRoot
        self.onFinish = onFinish
    }

    var body: some View {
        Form {
            Section {
                preview
                    .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0))
                    .listRowBackground(Color.clear)
                Picker("Size", selection: $family) {
                    ForEach([CardFamily.small, .medium, .large]) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("cardSizePicker")
            }
            Section {
                presets
                playgroundButton
                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    Label("Choose Photo", systemImage: "photo.on.rectangle")
                }
                .accessibilityIdentifier("cardPhotoButton")
                if isPreparingImage { ProgressView("Preparing image…") }
                if let imageError { Text(imageError).foregroundStyle(Color(.readingSecondary)) }
            } header: {
                Text("Background")
            } footer: {
                if supportsImagePlayground {
                    Text("Scripture on the card is copied exactly from \(card.editionLabel). Image Playground creates only the background, on this device.")
                } else {
                    Text("Scripture on the card is copied exactly from \(card.editionLabel). Image Playground backgrounds need Apple Intelligence on this device.")
                }
            }
            Section("Text") {
                Picker("Text Color", selection: $card.style.ink) {
                    Text("Automatic").tag(CardStyle.Ink.automatic)
                    Text("Light").tag(CardStyle.Ink.light)
                    Text("Dark").tag(CardStyle.Ink.dark)
                }
                Picker("Typeface", selection: $card.style.typeface) {
                    Text("Serif").tag(CardStyle.Typeface.serif)
                    Text("System Sans").tag(CardStyle.Typeface.sans)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.readingCanvas))
        .navigationTitle(card.reference)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isRoot {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { onFinish() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", role: .confirm) {
                    // A pushed editor returns to the card list; a new card's root editor closes the sheet.
                    if model.save(card, newBackground: pendingBackground) { isRoot ? onFinish() : dismiss() }
                }
                .disabled(isPreparingImage)
                .accessibilityIdentifier("cardSaveButton")
            }
        }
        // An empty prompt: people describe their own background, and the sheet opens without
        // first waiting on concept extraction from the passage.
        .imagePlaygroundSheet(isPresented: $isPlaygroundPresented) { url in
            prepare(source: .imagePlayground) { try Data(contentsOf: url) }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            prepare(source: .photo) {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw PreparedBackground.Failure.unreadable }
                return data
            }
            photoItem = nil
        }
        .task {
            guard let url = model.backgroundURL(for: card) else { return }
            let image = await Task.detached { UIImage(contentsOfFile: url.path) }.value
            savedImage = image.map(Image.init(uiImage:))
        }
    }

    private var preview: some View {
        GeometryReader { proxy in
            let size = family.previewSize
            let scale = min(1, proxy.size.width / size.width)
            ScriptureCardPreview(card: card, family: family, image: currentImage)
                .scaleEffect(scale)
                .frame(width: proxy.size.width, height: size.height * scale)
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        }
        .frame(height: family.previewSize.height)
        .accessibilityIdentifier("cardPreview")
    }

    private var currentImage: Image? {
        guard case .image = card.style.background else { return nil }
        return pendingImage ?? savedImage
    }

    private var presets: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 140 : 88), spacing: 12)], spacing: 12) {
            ForEach(CardPreset.allCases) { preset in
                let selected = card.style.background == .preset(preset)
                Button {
                    card.style.background = .preset(preset)
                    pendingBackground = nil
                    pendingImage = nil
                } label: {
                    VStack(spacing: 6) {
                        CardBackgroundView(style: CardStyle(background: .preset(preset)), image: nil)
                            .frame(height: 52)
                            .clipShape(.rect(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(selected ? Color(.accent) : Color(.readingSecondary).opacity(0.3), lineWidth: selected ? 3 : 1)
                            }
                            .overlay(alignment: .topTrailing) {
                                if selected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.white, Color(.accent))
                                        .padding(4)
                                }
                            }
                        Text(preset.title).font(.caption).foregroundStyle(Color(.readingPrimary))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(preset.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("cardPreset-\(preset.rawValue)")
            }
        }
        .padding(.vertical, 4)
    }

    /// Hidden where Image Playground is unavailable; the section footer explains why.
    @ViewBuilder private var playgroundButton: some View {
        if supportsImagePlayground {
            Button {
                isPlaygroundPresented = true
            } label: {
                Label("Create with Image Playground", systemImage: "apple.image.playground")
            }
            .disabled(isPreparingImage)
            .accessibilityIdentifier("cardPlaygroundButton")
        }
    }

    private func prepare(source: CardStyle.ImageSource, data: @escaping @Sendable () async throws -> Data) {
        isPreparingImage = true
        imageError = nil
        Task {
            defer { isPreparingImage = false }
            do {
                let raw = try await data()
                let prepared = try await Task.detached(priority: .userInitiated) {
                    try PreparedBackground.prepare(raw, source: source)
                }.value
                pendingBackground = prepared
                pendingImage = UIImage(data: prepared.jpeg).map(Image.init(uiImage:))
                // The file name is assigned on Save; the luminance drives the live preview now.
                card.style.background = .image(file: "", source: source, luminance: prepared.luminance)
            } catch {
                imageError = String(localized: "That image could not be used. Choose another.")
            }
        }
    }
}
