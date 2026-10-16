import SwiftUI

struct TipJarView: View {
    let store: TipStore
    let close: () -> Void

    var body: some View {
        Form {
            // Introduced like About's header: plain text on the canvas, not a card.
            Section {
                Text("If Bible is part of your day, an optional tip helps support its development.")
                    .foregroundStyle(Color(.readingPrimary))
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowBackground(Color.clear)
            }

            Section {
                if !store.paymentsAllowed {
                    Text("In-app purchases are not allowed on this device. You can still use every feature of Bible.")
                } else {
                    ForEach(store.products) { product in
                        Button {
                            // A purchase must outlive navigation away from this screen.
                            Task { await store.purchase(product) }
                        } label: {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 16) {
                                    Text(product.name)
                                    Spacer(minLength: 12)
                                    price(product)
                                }
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(product.name)
                                    price(product)
                                }
                            }
                            .foregroundStyle(Color(.readingPrimary))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .disabled(store.purchasingID != nil)
                        .accessibilityLabel("\(product.name), \(product.displayPrice)")
                        .accessibilityHint("One-time tip. Unlocks nothing.")
                        .accessibilityIdentifier(product.id)
                    }

                    if store.isLoading && store.products.isEmpty {
                        ProgressView("Loading tips…").frame(maxWidth: .infinity, minHeight: 44)
                    } else if !store.isLoading && (store.products.count < TipCatalog.identifiers.count || store.loadFailed) {
                        Text(store.products.isEmpty
                             ? String(localized: "Tips are unavailable right now. Check your connection and try again. Bible still works offline.")
                             : String(localized: "Some tip options are unavailable right now. You can try loading them again."))
                            .foregroundStyle(Color(.readingSecondary))
                        Button("Try Again", systemImage: "arrow.clockwise") { Task { await store.loadProducts() } }
                            .disabled(store.purchasingID != nil)
                            .accessibilityIdentifier("retryTipsButton")
                    }
                }

                if let message = store.message {
                    Label {
                        Text(message.text).foregroundStyle(Color(.readingPrimary))
                    } icon: {
                        Image(systemName: message == .thanks ? "heart.fill" : "info.circle")
                            .foregroundStyle(Color(.accent))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("tipStatus")
                }
            } footer: {
                Text("Tips are one-time purchases handled by the App Store. They unlock nothing, can be given again, and are not charitable donations.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.readingCanvas))
        .navigationTitle("Support Development")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Color(.accent))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(role: .close, action: close)
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("tipsCloseButton")
            }
        }
        .task { await store.loadProducts() }
        .onDisappear { store.dismissMessage() }
    }

    private func price(_ product: TipProduct) -> some View {
        HStack(spacing: 8) {
            if store.purchasingID == product.id { ProgressView().accessibilityLabel("Completing your tip") }
            Text(product.displayPrice).fontWeight(.semibold).monospacedDigit()
        }
        .fixedSize()
        .foregroundStyle(Color(.accent))
    }
}
