import SwiftUI
import SwiftData
import Vision

struct WineSearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var catalogResults: [CatalogWine] = []
    @State private var userWineResults: [Wine] = []
    @State private var vivinoResults: [VivinoWine] = []

    // One pass over saved wines instead of a SwiftData fetch per result row
    @Query private var savedWines: [Wine]
    private var ratedWineNames: Set<String> {
        Set(savedWines.filter { $0.userRatings?.isEmpty == false }.map { $0.name })
    }
    @State private var isSearching = false
    @State private var isSearchingVivino = false
    @State private var shouldDismiss = false
    @State private var showingAddWine = false
    @State private var selectedWine: Wine?
    @State private var pendingWine: Wine?
    @State private var showingCamera = false
    @State private var capturedImage: UIImage?
    @State private var isScanningLabel = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack {
                if searchText.isEmpty && !isScanningLabel {
                    SearchEmptyState(onCameraTap: { showingCamera = true })
                } else if isScanningLabel {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Reading label...")
                            .font(.nyBody)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else if isSearching {
                    ProgressView("Searching...")
                        .frame(maxHeight: .infinity)
                } else if catalogResults.isEmpty && userWineResults.isEmpty && vivinoResults.isEmpty && !isSearchingVivino {
                    NoResultsView(searchText: searchText, onAddWine: {
                        showingAddWine = true
                    })
                } else {
                    List {
                        // User's saved wines (manually added, from scans, etc.)
                        if !userWineResults.isEmpty {
                            Section {
                                ForEach(userWineResults) { wine in
                                    Button {
                                        selectedWine = wine
                                    } label: {
                                        UserWineRowView(wine: wine)
                                    }
                                }
                            } header: {
                                Text("Your Wines")
                                    .font(.nyCaption)
                            }
                        }

                        if !catalogResults.isEmpty {
                            Section {
                                ForEach(catalogResults) { catalogWine in
                                    Button {
                                        selectWine(catalogWine)
                                    } label: {
                                        CatalogWineRowView(wine: catalogWine,
                                                           hasUserRating: ratedWineNames.contains(catalogWine.name))
                                    }
                                }
                            } header: {
                                if !userWineResults.isEmpty {
                                    Text("From Catalog")
                                        .font(.nyCaption)
                                }
                            }
                        }

                        // Vivino results section
                        if !vivinoResults.isEmpty {
                            Section {
                                ForEach(Array(vivinoResults.enumerated()), id: \.offset) { _, vivinoWine in
                                    Button {
                                        selectVivinoWine(vivinoWine)
                                    } label: {
                                        VivinoWineRowView(wine: vivinoWine)
                                    }
                                }
                            } header: {
                                Text("From Vivino")
                                    .font(.nyCaption)
                            }
                        } else if isSearchingVivino {
                            Section {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Searching Vivino...")
                                        .font(.nyCaption)
                                        .foregroundColor(.secondary)
                                }
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingCamera = true }) {
                        Image(systemName: "camera")
                            .foregroundColor(.white)
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
            .sheet(isPresented: $showingCamera) {
                CameraView(image: $capturedImage)
            }
            .onChange(of: capturedImage) { _, newImage in
                guard let image = newImage else { return }
                capturedImage = nil
                scanLabel(image: image)
            }
        }
    }

    private func performSearch(query: String) {
        searchTask?.cancel()

        guard !query.isEmpty, query.count >= 2 else {
            catalogResults = []
            userWineResults = []
            vivinoResults = []
            isSearching = false
            return
        }

        isSearching = true

        searchTask = Task {
            // Debounce — wait for typing to pause
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, query == searchText else { return }

            // Search the SQLite catalog
            catalogResults = WineCatalog.shared.search(query: query, limit: 50)

            // Also search user's SwiftData wines
            let searchQuery = query
            let descriptor = FetchDescriptor<Wine>(
                predicate: #Predicate<Wine> { wine in
                    wine.name.localizedStandardContains(searchQuery)
                }
            )
            userWineResults = (try? modelContext.fetch(descriptor)) ?? []

            isSearching = false

            // Only search Vivino after 3+ characters
            guard !Task.isCancelled, query.count >= 3 else { return }
            isSearchingVivino = true
            let results = await VivinoService.shared.search(query: query, limit: 5)
            guard !Task.isCancelled, query == searchText else { return }
            vivinoResults = results
            isSearchingVivino = false
        }
    }

    private func selectVivinoWine(_ vivinoWine: VivinoWine) {
        // Reuse an existing wine — picking the same result twice used to
        // insert a duplicate row
        let name = vivinoWine.name
        let winery = vivinoWine.winery
        let descriptor = FetchDescriptor<Wine>(
            predicate: #Predicate<Wine> { wine in
                wine.name == name && wine.winery == winery
            }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            selectedWine = existing
            return
        }
        let wine = Wine(
            name: vivinoWine.name,
            region: vivinoWine.region,
            winery: vivinoWine.winery,
            country: vivinoWine.country,
            vivinoRating: vivinoWine.rating,
            vivinoRatingsCount: vivinoWine.ratingsCount,
            vivinoURL: vivinoWine.vivinoURL,
            vivinoImageURL: vivinoWine.imageURL
        )
        modelContext.insert(wine)
        try? modelContext.save()
        selectedWine = wine
    }

    private func selectWine(_ catalogWine: CatalogWine) {
        // Find or create SwiftData Wine from catalog wine
        let wine = findOrCreateWine(from: catalogWine)
        selectedWine = wine
    }

    private func scanLabel(image: UIImage) {
        isScanningLabel = true
        Task {
            let searchQuery = await extractLabelSearchQuery(from: image)
            await MainActor.run {
                isScanningLabel = false
                if !searchQuery.isEmpty {
                    searchText = searchQuery
                }
            }
        }
    }

    private func extractLabelSearchQuery(from image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }

        let texts: [String] = await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let cgOrientation: CGImagePropertyOrientation
            switch image.imageOrientation {
            case .up: cgOrientation = .up
            case .down: cgOrientation = .down
            case .left: cgOrientation = .left
            case .right: cgOrientation = .right
            case .upMirrored: cgOrientation = .upMirrored
            case .downMirrored: cgOrientation = .downMirrored
            case .leftMirrored: cgOrientation = .leftMirrored
            case .rightMirrored: cgOrientation = .rightMirrored
            @unknown default: cgOrientation = .up
            }
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: cgOrientation, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }

        guard !texts.isEmpty else { return "" }

        // Filter out noise common on wine labels
        let noisePatterns: [String] = [
            "750", "375", "1500", "ml", "vol", "alc", "alcohol",
            "contains sulfites", "sulphites", "government warning",
            "surgeon general", "drink responsibly", "product of",
            "imported by", "bottled by", "produced by", "distributed by",
            "www.", ".com", ".net", "http", "estate bottled",
            "appellation", "denominación", "denominacion",
            "vino de", "wine of", "vin de",
            "registered trademark", "all rights reserved",
            "lot ", "l.", "cellared", "sustainable", "organic", "biodynamic",
            "unfiltered", "unfined", "vegan"
        ]

        let filteredTexts = texts.filter { line in
            let lower = line.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            // Skip very short lines
            guard lower.count >= 3 else { return false }
            // Skip lines that are just numbers/percentages
            if lower.allSatisfy({ $0.isNumber || $0 == "." || $0 == "%" || $0 == "," || $0.isWhitespace }) {
                return false
            }
            // Skip noise
            for noise in noisePatterns {
                if lower.contains(noise) { return false }
            }
            return true
        }

        // Strategy: look for known winery names and vintage years
        var wineryMatch: String?
        var vintageYear: String?
        var bestLines: [String] = []

        for line in filteredTexts {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Check for vintage year
            if vintageYear == nil, let match = trimmed.firstMatch(of: /\b(19|20)\d{2}\b/) {
                vintageYear = String(match.0)
            }

            // Check if this line is a known winery
            if wineryMatch == nil && WineCatalog.shared.isKnownWinery(trimmed) {
                wineryMatch = trimmed
                continue
            }

            bestLines.append(trimmed)
        }

        // Build search query: prioritize winery + first meaningful line
        var queryParts: [String] = []
        if let winery = wineryMatch {
            queryParts.append(winery)
        }
        // Add the first 1-2 non-winery lines (likely the wine name)
        for line in bestLines.prefix(2) {
            // Skip if it's just the vintage year
            if line == vintageYear { continue }
            queryParts.append(line)
        }

        // If we found nothing useful, just use the first couple of OCR lines
        if queryParts.isEmpty {
            queryParts = Array(filteredTexts.prefix(2))
        }

        return queryParts.joined(separator: " ")
    }

    private func findOrCreateWine(from catalog: CatalogWine) -> Wine {
        // Check if wine already exists in SwiftData (match by name AND winery)
        let name = catalog.name
        let wineryName = catalog.winery ?? ""
        let descriptor = FetchDescriptor<Wine>(
            predicate: #Predicate<Wine> { wine in
                wine.name == name && wine.winery == wineryName
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
    let hasUserRating: Bool

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
    var onCameraTap: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.wineRed.opacity(0.5))

            Text("Search \(WineCatalog.shared.totalWines.formatted()) Wines")
                .font(.nyTitle2)
                .fontWeight(.semibold)

            VStack(spacing: 12) {
                Text("Search by wine name, winery, grape variety, or region.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)

                Button(action: onCameraTap) {
                    Text("Or take a photo of the label.")
                    .foregroundColor(.secondary)
                }

                Text("Add your own if you can't find a match.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            .font(.nyBody)
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

struct UserWineRowView: View {
    let wine: Wine

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(wine.name)
                    .font(.nyHeadline)
                    .foregroundColor(.primary)

                Spacer()

                if let ratings = wine.userRatings, !ratings.isEmpty {
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
                if let winery = wine.winery, !winery.isEmpty {
                    Text(winery)
                        .font(.nyCaption)
                        .foregroundColor(.secondary)
                }
                if let variety = wine.grapeVariety, !variety.isEmpty {
                    if wine.winery != nil {
                        Text("•")
                            .foregroundColor(.secondary)
                    }
                    Text(variety)
                        .font(.nyCaption)
                        .foregroundColor(.secondary)
                }
            }

            if let vivinoRating = wine.vivinoRating, vivinoRating > 0 {
                HStack {
                    StarRatingView(rating: vivinoRating, size: 12)
                    Text(String(format: "%.1f", vivinoRating))
                        .font(.nyCaption)
                        .foregroundColor(.secondary)
                    Text("Vivino")
                        .font(.nyCaption)
                        .foregroundColor(.secondary)
                }
            } else if let avgRating = wine.averageRating {
                HStack {
                    StarRatingView(rating: avgRating, size: 12)
                    Text(String(format: "%.1f", avgRating))
                        .font(.nyCaption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct VivinoWineRowView: View {
    let wine: VivinoWine

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(wine.winery.isEmpty ? wine.name : "\(wine.name)")
                .font(.nyHeadline)
                .foregroundColor(.primary)

            HStack {
                if !wine.winery.isEmpty {
                    Text(wine.winery)
                        .font(.nyCaption)
                        .foregroundColor(.secondary)
                }
                if let variety = wine.variety {
                    if !wine.winery.isEmpty {
                        Text("•")
                            .foregroundColor(.secondary)
                    }
                    Text(variety)
                        .font(.nyCaption)
                        .foregroundColor(.secondary)
                }
            }

            if wine.rating > 0 {
                HStack {
                    StarRatingView(rating: wine.rating, size: 12)
                    Text(String(format: "%.1f", wine.rating))
                        .font(.nyCaption)
                        .foregroundColor(.secondary)
                    Text("(\(wine.ratingsCount.formatted()))")
                        .font(.nyCaption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    WineSearchView()
        .modelContainer(for: [Wine.self, UserRating.self], inMemory: true)
}
