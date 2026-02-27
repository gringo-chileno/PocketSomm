import SwiftUI
import SwiftData

struct WineSearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var catalogResults: [CatalogWine] = []
    @State private var isSearching = false
    @State private var shouldDismiss = false
    @State private var showingAddWine = false
    @State private var selectedWine: Wine?
    @State private var pendingWine: Wine?

    var body: some View {
        NavigationStack {
            VStack {
                if searchText.isEmpty {
                    SearchEmptyState()
                } else if isSearching {
                    ProgressView("Searching...")
                        .frame(maxHeight: .infinity)
                } else if catalogResults.isEmpty {
                    NoResultsView(searchText: searchText, onAddWine: {
                        showingAddWine = true
                    })
                } else {
                    List {
                        ForEach(catalogResults) { catalogWine in
                            Button {
                                selectWine(catalogWine)
                            } label: {
                                CatalogWineRowView(wine: catalogWine, modelContext: modelContext)
                            }
                        }

                        // Option to add wine if not found in results
                        Section {
                            Button(action: { showingAddWine = true }) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.wineRed)
                                    Text("Add \"\(searchText)\" manually")
                                        .foregroundColor(.primary)
                                }
                                .font(.nyBody)
                            }
                        } header: {
                            Text("Not finding what you're looking for?")
                                .font(.nyCaption)
                        }
                    }
                }
            }
            .navigationTitle("Search Wines")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Wine name, winery, variety, or region")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onChange(of: searchText) { _, newValue in
                performSearch(query: newValue)
            }
            .onChange(of: shouldDismiss) { _, newValue in
                if newValue {
                    dismiss()
                }
            }
            .sheet(isPresented: $showingAddWine, onDismiss: {
                // Navigate after sheet fully dismisses
                if let wine = pendingWine {
                    selectedWine = wine
                    pendingWine = nil
                }
            }) {
                AddWineView(initialName: searchText) { wine in
                    pendingWine = wine
                }
            }
            .navigationDestination(item: $selectedWine) { wine in
                WineDetailView(wine: wine, onRatingSaved: { shouldDismiss = true })
            }
        }
    }

    private func performSearch(query: String) {
        guard !query.isEmpty else {
            catalogResults = []
            return
        }

        isSearching = true

        // Debounce search
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard query == searchText else { return }

            // Search the SQLite catalog (instant!)
            catalogResults = WineCatalog.shared.search(query: query, limit: 50)
            isSearching = false
        }
    }

    private func selectWine(_ catalogWine: CatalogWine) {
        // Find or create SwiftData Wine from catalog wine
        let wine = findOrCreateWine(from: catalogWine)
        selectedWine = wine
    }

    private func findOrCreateWine(from catalog: CatalogWine) -> Wine {
        // Check if wine already exists in SwiftData
        let name = catalog.name
        let descriptor = FetchDescriptor<Wine>(
            predicate: #Predicate<Wine> { wine in
                wine.name == name
            }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }

        // Create new SwiftData Wine from catalog
        let wine = Wine(
            name: catalog.name,
            vintage: catalog.vintage,
            region: catalog.region,
            grapeVariety: catalog.variety,
            averageRating: catalog.rating,
            winery: catalog.winery,
            country: catalog.country,
            priceUSD: catalog.price,
            wineType: catalog.wineType,
            body: catalog.body,
            acidity: catalog.acidity,
            foodPairings: catalog.foodPairings
        )

        modelContext.insert(wine)
        return wine
    }
}

struct CatalogWineRowView: View {
    let wine: CatalogWine
    let modelContext: ModelContext

    // Check if user has rated this wine
    private var hasUserRating: Bool {
        let name = wine.name
        let descriptor = FetchDescriptor<Wine>(
            predicate: #Predicate<Wine> { w in
                w.name == name
            }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing.userRatings?.isEmpty == false
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(wine.displayName)
                    .font(.nyHeadline)
                    .foregroundColor(.primary)

                Spacer()

                if hasUserRating {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .fontWeight(.bold)
                        Text("Rated")
                    }
                    .font(.nyCaption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green)
                    .cornerRadius(4)
                }
            }

            HStack {
                if let winery = wine.winery {
                    Text(winery)
                        .font(.nyCaption)
                        .foregroundColor(.secondary)
                }

                if let variety = wine.variety {
                    if wine.winery != nil {
                        Text("•")
                            .foregroundColor(.secondary)
                    }
                    Text(variety)
                        .font(.nyCaption)
                        .foregroundColor(.secondary)
                }
            }

            if let rating = wine.rating {
                HStack {
                    StarRatingView(rating: rating, size: 12)
                    Text(String(format: "%.1f", rating))
                        .font(.nyCaption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct SearchEmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.wineRed.opacity(0.5))

            Text("Search \(WineCatalog.shared.totalWines.formatted()) Wines")
                .font(.nyTitle2)
                .fontWeight(.semibold)

            Text("Search by wine name, winery, grape variety, or region.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 32)
        }
        .frame(maxHeight: .infinity)
    }
}

struct NoResultsView: View {
    let searchText: String
    var onAddWine: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wineglass")
                .font(.system(size: 50))
                .foregroundColor(.gray)

            Text("No Results")
                .font(.nyTitle2)
                .fontWeight(.semibold)

            Text("No wines found matching \"\(searchText)\"")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 32)

            if let onAddWine = onAddWine {
                Button(action: onAddWine) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add This Wine")
                    }
                    .font(.nyHeadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.wineRed)
                    .cornerRadius(10)
                }
                .padding(.top, 8)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

#Preview {
    WineSearchView()
        .modelContainer(for: [Wine.self, UserRating.self], inMemory: true)
}
