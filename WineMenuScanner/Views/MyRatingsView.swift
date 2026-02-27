import SwiftUI
import SwiftData

struct MyRatingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserRating.dateRated, order: .reverse) private var ratings: [UserRating]

    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .dateDesc
    @State private var showingFilters = false

    // Filters
    @State private var selectedWineType: String?
    @State private var selectedCountry: String?
    @State private var selectedGrapeVariety: String?

    enum SortOrder: String, CaseIterable {
        case dateDesc = "Newest First"
        case dateAsc = "Oldest First"
        case ratingDesc = "Highest Rated"
        case ratingAsc = "Lowest Rated"
        case communityDesc = "Community Rating ↓"
        case communityAsc = "Community Rating ↑"
        case priceDesc = "Price ↓"
        case priceAsc = "Price ↑"
        case name = "Name"
    }

    // Available filter options based on user's rated wines
    var availableWineTypes: [String] {
        let types = ratings.compactMap { $0.wine?.wineType }.filter { !$0.isEmpty }
        return Array(Set(types)).sorted()
    }

    var availableCountries: [String] {
        let countries = ratings.compactMap { $0.wine?.country }.filter { !$0.isEmpty }
        return Array(Set(countries)).sorted()
    }

    var availableGrapeVarieties: [String] {
        let varieties = ratings.compactMap { $0.wine?.grapeVariety }.filter { !$0.isEmpty }
        return Array(Set(varieties)).sorted()
    }

    var activeFilterCount: Int {
        var count = 0
        if selectedWineType != nil { count += 1 }
        if selectedCountry != nil { count += 1 }
        if selectedGrapeVariety != nil { count += 1 }
        return count
    }

    var filteredRatings: [UserRating] {
        var result = ratings

        // Text search - matches any word in any order across name, winery, variety, region, country
        if !searchText.isEmpty {
            let searchTerms = searchText.lowercased().split(separator: " ").map { String($0) }
            result = result.filter { rating in
                guard let wine = rating.wine else { return false }
                // Combine all searchable fields
                let searchableText = [
                    wine.name,
                    wine.winery ?? "",
                    wine.grapeVariety ?? "",
                    wine.region ?? "",
                    wine.country ?? ""
                ].joined(separator: " ").lowercased()

                // All search terms must match somewhere
                return searchTerms.allSatisfy { searchableText.contains($0) }
            }
        }

        // Wine type filter
        if let wineType = selectedWineType {
            result = result.filter { $0.wine?.wineType == wineType }
        }

        // Country filter
        if let country = selectedCountry {
            result = result.filter { $0.wine?.country == country }
        }

        // Grape variety filter
        if let variety = selectedGrapeVariety {
            result = result.filter { $0.wine?.grapeVariety == variety }
        }

        // Sorting
        switch sortOrder {
        case .dateDesc:
            result.sort { $0.dateRated > $1.dateRated }
        case .dateAsc:
            result.sort { $0.dateRated < $1.dateRated }
        case .ratingDesc:
            result.sort { $0.rating > $1.rating }
        case .ratingAsc:
            result.sort { $0.rating < $1.rating }
        case .communityDesc:
            result.sort { ($0.wine?.averageRating ?? 0) > ($1.wine?.averageRating ?? 0) }
        case .communityAsc:
            result.sort { ($0.wine?.averageRating ?? 0) < ($1.wine?.averageRating ?? 0) }
        case .priceDesc:
            result.sort { ($0.wine?.priceUSD ?? 0) > ($1.wine?.priceUSD ?? 0) }
        case .priceAsc:
            result.sort { ($0.wine?.priceUSD ?? 0) < ($1.wine?.priceUSD ?? 0) }
        case .name:
            result.sort { ($0.wine?.name ?? "") < ($1.wine?.name ?? "") }
        }

        return result
    }

    var body: some View {
        NavigationStack {
            Group {
                if ratings.isEmpty {
                    EmptyRatingsView()
                } else {
                    List {
                        Section {
                            ForEach(filteredRatings) { rating in
                                if let wine = rating.wine {
                                    NavigationLink(destination: WineDetailView(wine: wine)) {
                                        RatingRowView(rating: rating, wine: wine)
                                    }
                                }
                            }
                            .onDelete(perform: deleteRatings)
                        } header: {
                            if activeFilterCount > 0 {
                                Text("\(filteredRatings.count) of \(ratings.count) wines")
                                    .font(.nyCaption)
                                    .foregroundColor(.secondary)
                                    .textCase(nil)
                            } else {
                                Text("\(ratings.count) wine\(ratings.count == 1 ? "" : "s") rated")
                                    .font(.nyCaption)
                                    .foregroundColor(.secondary)
                                    .textCase(nil)
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search your ratings")
                }
            }
            .navigationTitle("My Ratings")
            .toolbar {
                if !ratings.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showingFilters = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                if activeFilterCount > 0 {
                                    Text("\(activeFilterCount)")
                                        .font(.nyCaption)
                                }
                            }
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("Sort By", selection: $sortOrder) {
                                ForEach(SortOrder.allCases, id: \.self) { order in
                                    Text(order.rawValue).tag(order)
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down.circle")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingFilters) {
                FilterSheet(
                    selectedWineType: $selectedWineType,
                    selectedCountry: $selectedCountry,
                    selectedGrapeVariety: $selectedGrapeVariety,
                    availableWineTypes: availableWineTypes,
                    availableCountries: availableCountries,
                    availableGrapeVarieties: availableGrapeVarieties
                )
            }
        }
    }

    private func deleteRatings(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filteredRatings[index])
        }
    }
}

struct RatingRowView: View {
    let rating: UserRating
    let wine: Wine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(wine.displayName)
                .font(.nyHeadline)

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

            HStack {
                StarRatingView(rating: rating.rating, size: 14)

                Text(String(format: "%.1f", rating.rating))
                    .font(.nySubheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer()

                Text(rating.dateRated.formatted(date: .abbreviated, time: .omitted))
                    .font(.nyCaption)
                    .foregroundColor(.secondary)
            }

            if let notes = rating.notes, !notes.isEmpty, notes != "Imported" {
                Text(notes)
                    .font(.nyCaption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

struct StarRatingView: View {
    let rating: Double
    let size: CGFloat

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { index in
                Image(systemName: starImage(for: index))
                    .font(.system(size: size))
                    .foregroundColor(.wineRed)
            }
        }
    }

    private func starImage(for index: Int) -> String {
        let starValue = Double(index) + 1
        if rating >= starValue {
            return "star.fill"
        } else if rating >= starValue - 0.5 {
            return "star.leadinghalf.filled"
        } else {
            return "star"
        }
    }
}

struct EmptyRatingsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "star")
                .font(.system(size: 60))
                .foregroundColor(.wineRed.opacity(0.5))

            Text("No Ratings Yet")
                .font(.nyTitle2)
                .fontWeight(.semibold)

            Text("Start rating wines to build your taste profile and get personalized recommendations.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 32)
        }
    }
}

struct FilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedWineType: String?
    @Binding var selectedCountry: String?
    @Binding var selectedGrapeVariety: String?

    let availableWineTypes: [String]
    let availableCountries: [String]
    let availableGrapeVarieties: [String]

    var hasActiveFilters: Bool {
        selectedWineType != nil || selectedCountry != nil || selectedGrapeVariety != nil
    }

    var body: some View {
        NavigationStack {
            List {
                // Grape Varietal
                Section {
                    FilterRow(title: "All Varietals", isSelected: selectedGrapeVariety == nil) {
                        selectedGrapeVariety = nil
                    }
                    ForEach(availableGrapeVarieties, id: \.self) { variety in
                        FilterRow(title: variety, isSelected: selectedGrapeVariety == variety) {
                            selectedGrapeVariety = variety
                        }
                    }
                } header: {
                    Text("Grape Varietal")
                        .font(.nyCaption)
                }

                // Wine Type
                Section {
                    FilterRow(title: "All Types", isSelected: selectedWineType == nil) {
                        selectedWineType = nil
                    }
                    ForEach(availableWineTypes, id: \.self) { type in
                        FilterRow(title: type, isSelected: selectedWineType == type) {
                            selectedWineType = type
                        }
                    }
                } header: {
                    Text("Wine Type")
                        .font(.nyCaption)
                }

                // Country
                Section {
                    FilterRow(title: "All Countries", isSelected: selectedCountry == nil) {
                        selectedCountry = nil
                    }
                    ForEach(availableCountries, id: \.self) { country in
                        FilterRow(title: country, isSelected: selectedCountry == country) {
                            selectedCountry = country
                        }
                    }
                } header: {
                    Text("Country")
                        .font(.nyCaption)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if hasActiveFilters {
                        Button("Clear All") {
                            selectedWineType = nil
                            selectedCountry = nil
                            selectedGrapeVariety = nil
                        }
                        .font(.nyBody)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.nyBody)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct FilterRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.nyBody)
                    .foregroundColor(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.wineRed)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    MyRatingsView()
        .modelContainer(for: [Wine.self, UserRating.self, ScanHistory.self], inMemory: true)
}
