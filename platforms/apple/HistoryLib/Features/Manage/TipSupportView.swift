import SwiftUI
import StoreKit

struct TipSupportView: View {
    @Environment(\.openURL) private var openURL
    @State private var store = TipStore()
    @State private var selectedProduct: Product?
    @State private var showingConfirmation = false
    @State private var showingStatus = false

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
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section {
                Text("Payment is processed by Apple. If you need a refund, contact Apple through its refund support. HistoryLib cannot directly issue or guarantee a refund.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Request a Refund from Apple") {
                    guard let url = URL(string: "https://reportaproblem.apple.com") else { return }
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
            Text("This tip is completely voluntary and only supports the developer. It will not unlock anything, and not giving a tip will not restrict your use of HistoryLib. Apple processes the payment and decides refunds. HistoryLib cannot directly issue or guarantee a refund. Have you read, understood, and agreed to this information and still want to give a tip?")
        }
        .alert("Tip Status", isPresented: $showingStatus) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(store.statusMessage ?? "")
        }
        .onChange(of: store.statusMessage) { _, message in
            showingStatus = message != nil && selectedProduct != nil
        }
    }
}
