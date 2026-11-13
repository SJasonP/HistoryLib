import SwiftUI
import StoreKit

struct TipSupportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var store = TipStore()
    @State private var selectedProduct: Product?
    @State private var showingConfirmation = false
    @State private var showingStatus = false
    @State private var showingThankYou = false

    private var confirmationMessage: String {
        [
            String(localized: "This tip is completely voluntary and only supports the developer."),
            String(localized: "It will not unlock anything, and not giving a tip will not restrict your use of HistoryLib."),
            String(localized: "Payment is processed by Apple. For payment-related questions, contact Apple."),
            String(localized: "Have you read, understood, and agreed to this information and still want to give a tip?")
        ].joined(separator: "\n\n")
    }

    var body: some View {
        List {
            Section {
                Text("HistoryLib is completely open source, ad-free, and free to use.")
                Text("Tips are completely voluntary and only support the developer. A tip does not unlock features, change access, or limit anything if you do not give one.")
                    .foregroundStyle(.secondary)
            }

            Section("Choose a Tip") {
                if store.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if store.products.isEmpty {
                    Text(store.statusMessage ?? String(localized: "Purchases are currently unavailable. Try again later."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.products) { product in
                        Button {
                            selectedProduct = product
                            showingConfirmation = true
                        } label: {
                            HStack {
                                Text(product.displayName)
                                    .font(.headline)
                                Spacer()
                                Text(product.displayPrice)
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section {
                Text("Payment is processed by Apple. For payment-related questions, contact Apple. HistoryLib cannot process App Store payments.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Contact Apple About Payment") {
                    guard let url = URL(string: "https://support.apple.com/billing") else { return }
                    openURL(url)
                }
            }
        }
        .navigationTitle("Support Us")
        .task {
            await store.loadProducts()
        }
        .alert("Confirm Tip", isPresented: $showingConfirmation, presenting: selectedProduct) { product in
            Button("No", role: .cancel) { }
            Button("Yes") {
                Task { await store.purchase(product) }
            }
        } message: { _ in
            Text(confirmationMessage)
        }
#if os(macOS)
        .sheet(isPresented: $showingThankYou) {
            TipThankYouView {
                showingThankYou = false
                dismiss()
            }
        }
#else
        .fullScreenCover(isPresented: $showingThankYou) {
            TipThankYouView {
                showingThankYou = false
                dismiss()
            }
        }
#endif
        .alert("Tip Status", isPresented: $showingStatus) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(store.statusMessage ?? "")
        }
        .onChange(of: store.statusMessage) { _, message in
            showingStatus = message != nil && selectedProduct != nil
        }
        .onChange(of: store.successfulPurchase) { _, success in
            if success { showingThankYou = true }
        }
    }
}

private struct TipThankYouView: View {
    let onDone: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.pink.opacity(0.18), .accentColor.opacity(0.12), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.pink)
                    .symbolEffect(.bounce, value: true)
                Text("Thank You")
                    .font(.largeTitle.bold())
                Text("Your support helps keep HistoryLib open source, ad-free, and free for everyone.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(24)
        }
        .interactiveDismissDisabled()
    }
}
