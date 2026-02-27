import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct VivinoImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isImporting = false
    @State private var showingFilePicker = false
    @State private var importResult: ImportResult?
    @State private var isProcessing = false

    struct ImportResult {
        let totalRows: Int
        let matchedWines: Int
        let importedRatings: Int
        let skippedDuplicates: Int
        let errors: [String]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.down.on.square")
                            .font(.system(size: 60))
                            .foregroundColor(.wineRed)

                        Text("Import Ratings")
                            .font(.nyTitle2)
                            .fontWeight(.bold)

                        Text("Import your wine ratings from a CSV file (Vivino export, spreadsheet, etc.)")
                            .font(.nyBody)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 20)

                    // Instructions
                    VStack(alignment: .leading, spacing: 16) {
                        Text("CSV Format")
                            .font(.nyHeadline)

                        Text("Your CSV should have columns for wine name, winery, and rating. Country/region columns help with matching.")
                            .font(.nyBody)
                            .foregroundColor(.secondary)

                        Text("Expected columns: Wine name, winery, rating, year (optional), origin_country (optional)")
                            .font(.nyCaption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // Import Button
                    if isProcessing {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Importing wines...")
                                .font(.nyBody)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 20)
                    } else if importResult == nil {
                        Button(action: { showingFilePicker = true }) {
                            HStack {
                                Image(systemName: "doc.badge.plus")
                                Text("Select CSV File")
                            }
                            .font(.nyHeadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.wineRed)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }

                    // Import Result
                    if let result = importResult {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: result.importedRatings > 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                    .foregroundColor(result.importedRatings > 0 ? .green : .orange)
                                Text(result.importedRatings > 0 ? "Import Complete" : "Import Issues")
                                    .font(.nyHeadline)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                ResultRow(label: "Total rows in file", value: "\(result.totalRows)")
                                ResultRow(label: "Wines matched", value: "\(result.matchedWines)")
                                ResultRow(label: "Ratings imported", value: "\(result.importedRatings)")
                                if result.skippedDuplicates > 0 {
                                    ResultRow(label: "Skipped (already rated)", value: "\(result.skippedDuplicates)")
                                }
                            }

                            if !result.errors.isEmpty {
                                Text("Wines not found in catalog:")
                                    .font(.nyCaption)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 8)

                                ForEach(result.errors.prefix(5), id: \.self) { error in
                                    Text("• \(error)")
                                        .font(.nyCaption)
                                        .foregroundColor(.secondary)
                                }

                                if result.errors.count > 5 {
                                    Text("...and \(result.errors.count - 5) more")
                                        .font(.nyCaption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)

                        // Done button after import
                        Button(action: { dismiss() }) {
                            Text("Done")
                                .font(.nyHeadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.wineRed)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 50)
                }
            }
            .navigationTitle("Import Ratings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(importResult != nil ? "Done" : "Cancel") {
                        dismiss()
                    }
                    .font(.nyBody)
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        processFile(url)
                    }
                case .failure(let error):
                    print("File picker error: \(error)")
                }
            }
        }
    }

    private func processFile(_ url: URL) {
        isProcessing = true

        // Read file content first (can be done off main thread)
        guard url.startAccessingSecurityScopedResource() else {
            importResult = ImportResult(totalRows: 0, matchedWines: 0, importedRatings: 0, skippedDuplicates: 0, errors: ["Could not access file"])
            isProcessing = false
            return
        }

        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            url.stopAccessingSecurityScopedResource()
            importResult = ImportResult(totalRows: 0, matchedWines: 0, importedRatings: 0, skippedDuplicates: 0, errors: ["Error reading file: \(error.localizedDescription)"])
            isProcessing = false
            return
        }
        url.stopAccessingSecurityScopedResource()

        // Parse CSV and import - all on main actor
        importResult = importVivinoCSV(content: content)
        isProcessing = false
    }

    // All SwiftData work happens on main actor
    private func importVivinoCSV(content: String) -> ImportResult {
        var totalRows = 0
        var matchedWines = 0
        var importedRatings = 0
        var skippedDuplicates = 0
        var errors: [String] = []

        let lines = content.components(separatedBy: .newlines)

        guard let headerLine = lines.first else {
            return ImportResult(totalRows: 0, matchedWines: 0, importedRatings: 0, skippedDuplicates: 0, errors: ["Empty file"])
        }

        let headers = parseCSVLine(headerLine).map { $0.lowercased() }

        // Find column indices
        let nameIndex = headers.firstIndex(where: { $0.contains("name") })
        // User's personal rating - look for "rating" but NOT "average"
        let ratingIndex = headers.firstIndex(where: { ($0.contains("rating") || $0.contains("score")) && !$0.contains("average") })
        // Community/average rating - look for "average" in the column name
        let avgRatingIndex = headers.firstIndex(where: { $0.contains("average") })
        let vintageIndex = headers.firstIndex(where: { $0.contains("vintage") || $0.contains("year") })
        let wineryIndex = headers.firstIndex(where: { $0.contains("winery") || $0.contains("producer") })
        let countryIndex = headers.firstIndex(where: { $0.contains("country") })

        guard let nameIdx = nameIndex else {
            return ImportResult(totalRows: 0, matchedWines: 0, importedRatings: 0, skippedDuplicates: 0, errors: ["Could not find wine name column"])
        }

        // Process data rows
        for line in lines.dropFirst() {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            totalRows += 1

            let fields = parseCSVLine(line)
            guard fields.count > nameIdx else { continue }

            let wineName = fields[nameIdx].trimmingCharacters(in: .whitespaces)
            guard !wineName.isEmpty else { continue }

            let rating = ratingIndex.flatMap { idx in
                fields.count > idx ? Double(fields[idx].trimmingCharacters(in: .whitespaces)) : nil
            }
            // Community/average rating from CSV (e.g., Vivino's average rating)
            let avgRating = avgRatingIndex.flatMap { idx in
                fields.count > idx ? Double(fields[idx].trimmingCharacters(in: .whitespaces)) : nil
            }
            let vintage = vintageIndex.flatMap { idx in
                fields.count > idx ? Int(fields[idx].trimmingCharacters(in: .whitespaces)) : nil
            }
            let winery = wineryIndex.flatMap { idx in
                fields.count > idx ? fields[idx].trimmingCharacters(in: .whitespaces) : nil
            }
            let country = countryIndex.flatMap { idx in
                fields.count > idx ? fields[idx].trimmingCharacters(in: .whitespaces) : nil
            }

            // Search catalog for matching wine
            if let catalogWine = findCatalogMatch(name: wineName, winery: winery, country: country) {
                matchedWines += 1

                // Create rating if we have one
                if let ratingValue = rating, ratingValue > 0 {
                    // Get or create SwiftData Wine (use CSV vintage for uniqueness)
                    // Pass avgRating from CSV if available; otherwise use catalog rating
                    let wine = getOrCreateWine(from: catalogWine, csvVintage: vintage, csvAvgRating: avgRating)

                    // Check if rating already exists for this wine
                    if wine.userRatings?.isEmpty == false {
                        skippedDuplicates += 1
                        continue
                    }

                    // Create the rating
                    let userRating = UserRating(
                        wine: wine,
                        rating: min(5.0, ratingValue),
                        notes: "Imported",
                        vintage: vintage ?? catalogWine.vintage
                    )
                    modelContext.insert(userRating)

                    // Ensure the relationship array is set up
                    if wine.userRatings == nil {
                        wine.userRatings = []
                    }
                    wine.userRatings?.append(userRating)
                    importedRatings += 1
                } else {
                    errors.append("\(wineName) - no rating value")
                }
            } else {
                errors.append("\(wineName) - \(winery ?? "unknown winery") (not found)")
            }
        }

        // Save all at once
        do {
            try modelContext.save()
            print("Successfully saved \(importedRatings) ratings")

            // Verify
            let ratingDescriptor = FetchDescriptor<UserRating>()
            let wineDescriptor = FetchDescriptor<Wine>()
            let ratingCount = (try? modelContext.fetchCount(ratingDescriptor)) ?? -1
            let wineCount = (try? modelContext.fetchCount(wineDescriptor)) ?? -1
            print("VERIFY: Database now has \(ratingCount) ratings and \(wineCount) wines")
        } catch {
            print("Error saving ratings: \(error)")
        }

        return ImportResult(totalRows: totalRows, matchedWines: matchedWines, importedRatings: importedRatings, skippedDuplicates: skippedDuplicates, errors: errors)
    }

    private func findCatalogMatch(name: String, winery: String?, country: String?) -> CatalogWine? {
        // Strategy 1: Search by exact wine name
        let nameResults = WineCatalog.shared.search(query: name, limit: 20)

        // If we have winery, find best match
        if let winery = winery, !winery.isEmpty {
            // Look for match with same winery
            if let match = nameResults.first(where: {
                $0.winery?.localizedCaseInsensitiveCompare(winery) == .orderedSame ||
                $0.winery?.localizedCaseInsensitiveContains(winery) == true ||
                winery.localizedCaseInsensitiveContains($0.winery ?? "---")
            }) {
                return match
            }
        }

        // If we have country, filter by country
        if let country = country, !country.isEmpty {
            if let match = nameResults.first(where: {
                $0.country?.localizedCaseInsensitiveCompare(country) == .orderedSame ||
                $0.country?.localizedCaseInsensitiveContains(country) == true
            }) {
                return match
            }
        }

        // Strategy 2: Search by winery + partial name
        if let winery = winery, !winery.isEmpty {
            let wineryResults = WineCatalog.shared.search(query: winery, limit: 50)
            let nameLower = name.lowercased()

            if let match = wineryResults.first(where: {
                $0.name.lowercased().contains(nameLower) ||
                nameLower.contains($0.name.lowercased())
            }) {
                return match
            }
        }

        // Strategy 3: Return first result only if it's a very close match
        if let first = nameResults.first {
            let nameLower = name.lowercased()
            let matchLower = first.name.lowercased()

            // Only accept if names are very similar
            if nameLower.contains(matchLower) || matchLower.contains(nameLower) {
                return first
            }
        }

        return nil
    }

    private func getOrCreateWine(from catalog: CatalogWine, csvVintage: Int?, csvAvgRating: Double?) -> Wine {
        // Use CSV vintage if provided, otherwise use catalog vintage
        let vintageToUse = csvVintage ?? catalog.vintage
        let name = catalog.name

        // Check if already exists in SwiftData with same name
        let descriptor = FetchDescriptor<Wine>(
            predicate: #Predicate<Wine> { wine in
                wine.name == name
            }
        )

        // Filter by vintage in code (SwiftData predicates don't handle optionals well)
        if let existing = try? modelContext.fetch(descriptor).first(where: { $0.vintage == vintageToUse }) {
            // Update community rating from CSV if we have one and existing doesn't
            if existing.averageRating == nil, let csvRating = csvAvgRating {
                existing.averageRating = csvRating
            }
            return existing
        }

        // Use CSV average rating if available, otherwise use catalog rating
        // If neither available, leave it nil (don't show community rating)
        let communityRating = csvAvgRating ?? catalog.rating

        // Create new Wine from catalog with the CSV vintage
        let wine = Wine(
            name: catalog.name,
            vintage: vintageToUse,
            region: catalog.region,
            grapeVariety: catalog.variety,
            averageRating: communityRating,
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

    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var currentField = ""
        var insideQuotes = false

        for char in line {
            if char == "\"" {
                insideQuotes.toggle()
            } else if char == "," && !insideQuotes {
                fields.append(currentField.trimmingCharacters(in: .whitespaces))
                currentField = ""
            } else {
                currentField.append(char)
            }
        }

        fields.append(currentField.trimmingCharacters(in: .whitespaces))
        return fields
    }
}

struct InstructionRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.nyCaption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Color.wineRed)
                .clipShape(Circle())

            Text(text)
                .font(.nyBody)
                .foregroundColor(.primary)
        }
    }
}

struct ResultRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.nyBody)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.nyBody)
                .fontWeight(.semibold)
        }
    }
}

#Preview {
    VivinoImportView()
        .modelContainer(for: [Wine.self, UserRating.self], inMemory: true)
}
