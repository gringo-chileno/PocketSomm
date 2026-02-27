import SwiftUI
import SwiftData

struct ScanResultsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let scan: ScanHistory
    var isNewScan: Bool = false
    var onDone: (() -> Void)?

    @Query private var allRatings: [UserRating]
    @State private var wineMatches: [WineMatch] = []
    @State private var isLoading = true
    @State private var shouldDismiss = false

    struct WineMatch: Identifiable {
        let id = UUID()
        let detectedName: String
        var matchedWine: Wine?
        var predictedScore: Double?
        var isTopPick: Bool = false
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Scan Info Header
                if let photoData = scan.photoData,
                   let uiImage = UIImage(data: photoData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                        .cornerRadius(12)
                }

                Text("Scanned \(scan.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.nySubheadline)
                    .foregroundColor(.secondary)

                if isLoading {
                    ProgressView("Matching wines...")
                        .padding(.top, 40)
                } else if wineMatches.isEmpty {
                    NoWinesDetectedView()
                } else {
                    // Top Pick (if we have one with a score)
                    if let topPick = wineMatches.first(where: { $0.isTopPick && $0.matchedWine != nil }) {
                        TopPickCard(match: topPick, onRatingSaved: { shouldDismiss = true })
                            .padding(.horizontal)
                    }

                    // Results List
                    VStack(alignment: .leading, spacing: 16) {
                        Text("\(wineMatches.count) Wines Detected")
                            .font(.nyHeadline)
                            .padding(.horizontal)

                        ForEach(wineMatches.filter { !$0.isTopPick }) { match in
                            WineMatchCard(match: match, allRatings: allRatings, onRatingSaved: { shouldDismiss = true })
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(isNewScan ? "Scan Results" : "Past Scan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isNewScan {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onDone?()
                    }
                }
            }
        }
        .onChange(of: shouldDismiss) { _, newValue in
            if newValue {
                onDone?()
            }
        }
        .onAppear {
            loadMatches()
        }
    }

    private func loadMatches() {
        Task {
            let preferences = UserPreferences.calculate(from: Array(allRatings))

            // Create matches from detected wine names
            var matches: [WineMatch] = []

            for entry in scan.detectedWineNames {
                // Parse variety context if encoded (format: "name\tvariety")
                let parts = entry.components(separatedBy: ScannerView.varietySeparator)
                let name = parts[0]
                let variety = parts.count > 1 ? parts[1] : nil

                var match = WineMatch(detectedName: name)

                // Try to find matching wine in database
                if let matchedWine = findWineMatch(for: name, variety: variety) {
                    match.matchedWine = matchedWine
                    match.predictedScore = preferences.predictScore(for: matchedWine)
                }

                matches.append(match)
            }

            // Sort by predicted score (highest first), then by community rating
            matches.sort { m1, m2 in
                // Prioritize wines with predicted scores
                if let s1 = m1.predictedScore, let s2 = m2.predictedScore {
                    return s1 > s2
                }
                if m1.predictedScore != nil { return true }
                if m2.predictedScore != nil { return false }

                // Fall back to community rating
                if let r1 = m1.matchedWine?.averageRating, let r2 = m2.matchedWine?.averageRating {
                    return r1 > r2
                }
                if m1.matchedWine?.averageRating != nil { return true }
                if m2.matchedWine?.averageRating != nil { return false }

                return m1.detectedName < m2.detectedName
            }

            // Mark top pick (highest predicted score with a matched wine)
            if let topIndex = matches.firstIndex(where: { $0.matchedWine != nil && $0.predictedScore != nil }) {
                matches[topIndex].isTopPick = true
            }

            await MainActor.run {
                wineMatches = matches
                isLoading = false
            }
        }
    }

    private func findWineMatch(for name: String, variety: String? = nil) -> Wine? {
        // First check if already matched in SwiftData
        if let matched = scan.matchedWines?.first(where: {
            $0.name.localizedCaseInsensitiveContains(name) ||
            name.localizedCaseInsensitiveContains($0.name)
        }) {
            return matched
        }

        // Check SwiftData for existing wine
        let cleanedName = name.filter { $0.isLetter || $0.isNumber || $0 == " " }
        let descriptor = FetchDescriptor<Wine>(
            predicate: #Predicate<Wine> { wine in
                wine.name.localizedStandardContains(name)
            }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }

        // Build search query — append variety from menu section header if available
        let searchQuery = variety != nil ? "\(cleanedName) \(variety!)" : cleanedName

        // Search the catalog with full detected name (+ variety context)
        let catalogResults = WineCatalog.shared.search(query: searchQuery, limit: 1)
        if let catalogWine = catalogResults.first {
            return createWineFromCatalog(catalogWine)
        }

        // If comma-separated (common menu format: "Winery, Wine Name"),
        // try searching with parts reordered and separately
        if name.contains(",") {
            let parts = name.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if parts.count >= 2 {
                // Try "WineName Winery" order (catalog stores wine name first)
                let reordered = (Array(parts[1...]) + [parts[0]]).joined(separator: " ")
                let reorderedQuery = variety != nil ? "\(reordered) \(variety!)" : reordered
                let reorderedResults = WineCatalog.shared.search(query: reorderedQuery, limit: 1)
                if let catalogWine = reorderedResults.first {
                    return createWineFromCatalog(catalogWine)
                }

                // Try just the winery name (before the comma) + variety
                let wineryQuery = variety != nil ? "\(parts[0]) \(variety!)" : parts[0]
                let wineryResults = WineCatalog.shared.search(query: wineryQuery, limit: 1)
                if let catalogWine = wineryResults.first {
                    return createWineFromCatalog(catalogWine)
                }
            }
        }

        return nil
    }

    private func createWineFromCatalog(_ catalog: CatalogWine) -> Wine {
        // Check if already exists
        let name = catalog.name
        let descriptor = FetchDescriptor<Wine>(
            predicate: #Predicate<Wine> { wine in
                wine.name == name
            }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }

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

struct TopPickCard: View {
    let match: ScanResultsView.WineMatch
    var onRatingSaved: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "star.circle.fill")
                    .font(.title2)
                    .foregroundColor(.wineRed)
                Text("Top Pick For You")
                    .font(.nyTitle3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }

            if let wine = match.matchedWine {
                VStack(alignment: .leading, spacing: 8) {
                    Text(wine.displayName)
                        .font(.nyTitle3)
                        .fontWeight(.bold)

                    HStack {
                        if let winery = wine.winery {
                            Text(winery)
                                .font(.nySubheadline)
                                .foregroundColor(.secondary)
                        }
                        if let variety = wine.grapeVariety {
                            if wine.winery != nil {
                                Text("•")
                                    .foregroundColor(.secondary)
                            }
                            Text(variety)
                                .font(.nySubheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                HStack(spacing: 24) {
                    // Show user's rating if they've rated it, otherwise show predicted
                    if let userRating = wine.userRating {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your Rating")
                                .font(.nyCaption)
                                .foregroundColor(.secondary)
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.wineRed)
                                Text(String(format: "%.1f", userRating.rating))
                                    .font(.nyTitle2)
                                    .fontWeight(.bold)
                            }
                        }
                    } else if let predicted = match.predictedScore {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Predicted")
                                .font(.nyCaption)
                                .foregroundColor(.secondary)
                            HStack(spacing: 4) {
                                Image(systemName: "heart.fill")
                                    .foregroundColor(.wineRed)
                                Text(String(format: "%.1f", predicted))
                                    .font(.nyTitle2)
                                    .fontWeight(.bold)
                            }
                        }
                    }

                    if let avgRating = wine.averageRating {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Community")
                                .font(.nyCaption)
                                .foregroundColor(.secondary)
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.wineRed)
                                Text(String(format: "%.1f", avgRating))
                                    .font(.nyTitle2)
                                    .fontWeight(.bold)
                            }
                        }
                    }
                }

                NavigationLink(destination: WineDetailView(wine: wine, onRatingSaved: onRatingSaved)) {
                    Text(wine.userRating != nil ? "View Details" : "View & Rate")
                        .font(.nyHeadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.wineRed)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.wineRed.opacity(0.3), lineWidth: 2)
                )
        )
    }
}

struct WineMatchCard: View {
    let match: ScanResultsView.WineMatch
    let allRatings: [UserRating]
    var onRatingSaved: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Detected Name
            Text(match.detectedName)
                .font(.nyHeadline)

            if let wine = match.matchedWine {
                // Matched wine info - winery then varietal
                HStack {
                    if let winery = wine.winery {
                        Text(winery)
                            .font(.nyCaption)
                            .foregroundColor(.secondary)
                    }
                    if let variety = wine.grapeVariety {
                        if wine.winery != nil {
                            Text("•")
                                .foregroundColor(.secondary)
                        }
                        Text(variety)
                            .font(.nyCaption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 16) {
                    // Show user's rating if they've rated it, otherwise show predicted
                    if let userRating = wine.userRating {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Your Rating")
                                .font(.nyCaption2)
                                .foregroundColor(.secondary)
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.wineRed)
                                    .font(.nyCaption)
                                Text(String(format: "%.1f", userRating.rating))
                                    .font(.nyBody)
                                    .fontWeight(.semibold)
                            }
                        }
                    } else if let predicted = match.predictedScore {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Predicted")
                                .font(.nyCaption2)
                                .foregroundColor(.secondary)
                            HStack(spacing: 4) {
                                Image(systemName: "heart.fill")
                                    .foregroundColor(.wineRed)
                                    .font(.nyCaption)
                                Text(String(format: "%.1f", predicted))
                                    .font(.nyBody)
                                    .fontWeight(.semibold)
                            }
                        }
                    }

                    // Community Rating
                    if let avgRating = wine.averageRating {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Community")
                                .font(.nyCaption2)
                                .foregroundColor(.secondary)
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.wineRed)
                                    .font(.nyCaption)
                                Text(String(format: "%.1f", avgRating))
                                    .font(.nyBody)
                                    .fontWeight(.semibold)
                            }
                        }
                    }

                    Spacer()
                }

                NavigationLink(destination: WineDetailView(wine: wine, onRatingSaved: onRatingSaved)) {
                    Text(wine.userRating != nil ? "View Details" : "View & Rate")
                        .font(.nySubheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground))
                        .foregroundColor(.primary)
                        .cornerRadius(8)
                }
            } else {
                // No match found
                HStack {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.orange)
                    Text("Not found in database")
                        .font(.nyCaption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct NoWinesDetectedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.orange)

            Text("No Wines Detected")
                .font(.nyTitle2)
                .fontWeight(.semibold)

            Text("We couldn't find any wine names in this image. Try scanning a clearer photo of a wine menu.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 32)
        }
        .padding(.top, 40)
    }
}

#Preview {
    NavigationStack {
        ScanResultsView(
            scan: ScanHistory(
                date: Date(),
                detectedWineNames: ["Château Margaux 2015", "Opus One 2018", "Penfolds Grange"]
            )
        )
    }
    .modelContainer(for: [Wine.self, UserRating.self, ScanHistory.self], inMemory: true)
}
