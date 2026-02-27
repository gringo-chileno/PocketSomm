import SwiftUI
import SwiftData

struct WineDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let wine: Wine
    var onRatingSaved: (() -> Void)?

    @State private var userRatingValue: Double = 0.0
    @State private var notes: String = ""
    @State private var showingSaveConfirmation = false
    @State private var editedVintage: Int?
    @State private var showingVintagePicker = false
    @State private var showingRatingHistory = false
    @State private var isEditingRating = false
    @State private var showingEditWine = false
    @State private var showingDeleteConfirmation = false

    private var existingRating: UserRating? {
        wine.userRatings?.sorted { $0.dateRated > $1.dateRated }.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Wine Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(wine.name)
                        .font(.nyTitle2)
                        .fontWeight(.bold)

                    HStack(spacing: 8) {
                        if let winery = wine.winery {
                            Text(winery)
                                .font(.nySubheadline)
                                .foregroundColor(.secondary)
                        }

                        // Vintage (editable, updates immediately)
                        if let vintage = editedVintage ?? wine.vintage, vintage > 0 {
                            Text("•")
                                .foregroundColor(.secondary)
                            Button(action: { showingVintagePicker = true }) {
                                Text(String(vintage))
                                    .font(.nySubheadline)
                                    .foregroundColor(.white)
                            }
                        } else {
                            Button(action: { showingVintagePicker = true }) {
                                Text("Add Vintage")
                                    .font(.nyCaption)
                                    .foregroundColor(.white)
                            }
                        }
                    }

                    // Wine type badge
                    if let wineType = wine.wineType {
                        Text(wineType)
                            .font(.nyCaption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.wineRed.opacity(0.15))
                            .foregroundColor(.wineRed)
                            .cornerRadius(4)
                    }
                }

                // Your Rating Section - show existing or allow new
                if let rating = existingRating, !isEditingRating {
                    // Show existing rating
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Your Rating")
                                .font(.nyHeadline)

                            Spacer()

                            if let ratings = wine.userRatings, ratings.count > 1 {
                                Button(action: { showingRatingHistory = true }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "clock.arrow.circlepath")
                                        Text("\(ratings.count)")
                                    }
                                    .font(.nyCaption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.wineRed.opacity(0.2))
                                    .foregroundColor(.wineRed)
                                    .cornerRadius(4)
                                }
                            }
                        }

                        HStack(alignment: .center, spacing: 12) {
                            Text(String(format: "%.1f", rating.rating))
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)

                            VStack(alignment: .leading, spacing: 4) {
                                StarRatingView(rating: rating.rating, size: 18)
                                Text(rating.dateRated.formatted(date: .abbreviated, time: .omitted))
                                    .font(.nyCaption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if let ratingNotes = rating.notes, !ratingNotes.isEmpty, ratingNotes != "Imported" {
                            Text(ratingNotes)
                                .font(.nyBody)
                                .foregroundColor(.secondary)
                        }

                        HStack(spacing: 12) {
                            Button(action: {
                                userRatingValue = rating.rating
                                notes = rating.notes ?? ""
                                isEditingRating = true
                            }) {
                                HStack {
                                    Image(systemName: "pencil")
                                    Text("Edit")
                                }
                                .font(.nySubheadline)
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(.secondarySystemBackground))
                                .foregroundColor(.primary)
                                .cornerRadius(8)
                            }

                            Button(action: {
                                userRatingValue = 0
                                notes = ""
                                isEditingRating = true
                            }) {
                                HStack {
                                    Image(systemName: "plus")
                                    Text("Rate Again")
                                }
                                .font(.nySubheadline)
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.wineRed)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                        }

                        Button(action: {
                            showingDeleteConfirmation = true
                        }) {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete Rating")
                            }
                            .font(.nyCaption)
                            .foregroundColor(.red)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
                } else {
                    // Rating input section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text(existingRating != nil ? "Edit Rating" : "Rate This Wine")
                                .font(.nyHeadline)

                            Spacer()

                            if existingRating != nil {
                                Button("Cancel") {
                                    isEditingRating = false
                                }
                                .font(.nyCaption)
                                .foregroundColor(.white)
                            }
                        }

                        // Rating Slider
                        VStack(spacing: 12) {
                            HStack {
                                Text(String(format: "%.1f", userRatingValue))
                                    .font(.system(size: 48, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)

                                Text("/ 5.0")
                                    .font(.nyTitle2)
                                    .foregroundColor(.white.opacity(0.7))
                            }

                            InteractiveStarRating(rating: $userRatingValue)

                            Slider(value: $userRatingValue, in: 0...5, step: 0.1)
                                .tint(.wineRed)

                            HStack {
                                Text("0")
                                Spacer()
                                Text("5")
                            }
                            .font(.nyCaption)
                            .foregroundColor(.secondary)
                        }

                        // Notes
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notes (optional)")
                                .font(.nySubheadline)
                                .foregroundColor(.secondary)

                            TextEditor(text: $notes)
                                .frame(height: 80)
                                .padding(8)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color(.systemGray4), lineWidth: 1)
                                )
                        }

                        // Save button inline
                        Button(action: { saveRating() }) {
                            Text(existingRating != nil && userRatingValue == existingRating?.rating ? "Update Rating" : "Save Rating")
                                .font(.nyHeadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(userRatingValue == 0 ? Color.gray : Color.wineRed)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .disabled(userRatingValue == 0)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
                }

                // Wine Details
                VStack(spacing: 16) {
                    HStack {
                        Text("Wine Details")
                            .font(.nyHeadline)
                        Spacer()
                        Button(action: { showingEditWine = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "pencil")
                                Text("Edit")
                            }
                            .font(.nyCaption)
                            .foregroundColor(.secondary)
                        }
                    }

                    EditableDetailRow(icon: "leaf.fill", label: "Varietal", value: wine.grapeVariety, onTap: { showingEditWine = true })
                    EditableDetailRow(icon: "globe", label: "Country", value: wine.country, onTap: { showingEditWine = true })
                    EditableDetailRow(icon: "mappin.circle.fill", label: "Region", value: wine.region, onTap: { showingEditWine = true })

                    if let price = wine.priceUSD {
                        DetailRow(icon: "dollarsign.circle.fill", label: "Price", value: String(format: "$%.0f", price))
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

                // Community Rating
                VStack(alignment: .leading, spacing: 8) {
                    Text("Community Rating")
                        .font(.nyHeadline)

                    if let avgRating = wine.averageRating {
                        HStack {
                            StarRatingView(rating: avgRating, size: 20)

                            Text(String(format: "%.1f", avgRating))
                                .font(.nyTitle2)
                                .fontWeight(.semibold)

                            Text("/ 5.0")
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("—")
                            .font(.nyTitle2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Initialize vintage from wine's default
            editedVintage = wine.vintage
        }
        .overlay {
            if showingSaveConfirmation {
                SaveConfirmationView()
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showingVintagePicker) {
            VintagePickerView(
                selectedVintage: $editedVintage,
                currentVintage: wine.vintage,
                onVintageSelected: { newVintage in
                    wine.vintage = newVintage
                    try? modelContext.save()
                }
            )
        }
        .sheet(isPresented: $showingRatingHistory) {
            RatingHistoryView(wine: wine)
        }
        .sheet(isPresented: $showingEditWine) {
            EditWineView(wine: wine)
        }
        .alert("Delete Rating", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteCurrentRating()
            }
        } message: {
            Text("Are you sure you want to delete this rating?")
        }
    }

    private func deleteCurrentRating() {
        guard let rating = existingRating else { return }

        // Remove from wine's ratings array
        wine.userRatings?.removeAll { $0.id == rating.id }

        // Delete from context
        modelContext.delete(rating)

        do {
            try modelContext.save()
        } catch {
            print("Error deleting rating: \(error)")
        }
    }

    private func parseFoodPairings(_ string: String) -> [String]? {
        // Parse Python-style list: ['Beef', 'Lamb', 'Pasta']
        let cleaned = string
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: "'", with: "")
        let items = cleaned.components(separatedBy: ", ").filter { !$0.isEmpty }
        return items.isEmpty ? nil : items
    }

    private func saveRating() {
        // Always create a new rating (supports multiple tastings)
        let newRating = UserRating(
            wine: wine,
            rating: userRatingValue,
            notes: notes.isEmpty ? nil : notes,
            vintage: editedVintage ?? wine.vintage
        )
        modelContext.insert(newRating)

        // Ensure the relationship is set up
        if wine.userRatings == nil {
            wine.userRatings = []
        }
        wine.userRatings?.append(newRating)

        // Explicitly save
        do {
            try modelContext.save()
        } catch {
            print("Error saving rating: \(error)")
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            showingSaveConfirmation = true
        }

        // Brief confirmation then dismiss back to home
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            dismiss()
            onRatingSaved?()
        }
    }
}

struct VintagePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedVintage: Int?
    let currentVintage: Int?
    var onVintageSelected: ((Int?) -> Void)?

    private let currentYear = Calendar.current.component(.year, from: Date())
    private var vintageRange: [Int] {
        Array((currentYear - 100)...currentYear).reversed()
    }

    var body: some View {
        NavigationStack {
            List {
                Button(action: {
                    selectedVintage = nil
                    onVintageSelected?(nil)
                    dismiss()
                }) {
                    HStack {
                        Text("No Vintage (NV)")
                            .font(.nyBody)
                        Spacer()
                        if selectedVintage == nil && currentVintage == nil {
                            Image(systemName: "checkmark")
                                .foregroundColor(.wineRed)
                        }
                    }
                }
                .foregroundColor(.primary)

                ForEach(vintageRange, id: \.self) { year in
                    Button(action: {
                        selectedVintage = year
                        onVintageSelected?(year)
                        dismiss()
                    }) {
                        HStack {
                            Text(String(year))
                                .font(.nyBody)
                            Spacer()
                            if (selectedVintage ?? currentVintage) == year {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.wineRed)
                            }
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
            .navigationTitle("Select Vintage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.nyBody)
                }
            }
        }
    }
}

struct DetailRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 24)

            Text(label)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .fontWeight(.medium)
        }
    }
}

struct EditableDetailRow: View {
    let icon: String
    let label: String
    let value: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
                    .frame(width: 24)

                Text(label)
                    .foregroundColor(.secondary)

                Spacer()

                if let value = value, !value.isEmpty {
                    Text(value)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                } else {
                    Text("Add")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct EditWineView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let wine: Wine

    @State private var grapeVariety: String = ""
    @State private var region: String = ""
    @State private var country: String = ""
    @State private var winery: String = ""
    @State private var wineType: String = ""

    @State private var showingVarietyPicker = false
    @State private var showingRegionPicker = false
    @State private var showingCountryPicker = false
    @State private var showingWineryPicker = false

    private let wineTypeOptions = ["", "Red", "White", "Rosé", "Sparkling", "Dessert", "Fortified"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SelectableRow(label: "Grape Varietal", value: grapeVariety) {
                        showingVarietyPicker = true
                    }
                    SelectableRow(label: "Country", value: country) {
                        showingCountryPicker = true
                    }
                    SelectableRow(label: "Region", value: region) {
                        showingRegionPicker = true
                    }
                    SelectableRow(label: "Winery", value: winery) {
                        showingWineryPicker = true
                    }
                    Picker("Wine Type", selection: $wineType) {
                        ForEach(wineTypeOptions, id: \.self) { type in
                            Text(type.isEmpty ? "Not specified" : type).tag(type)
                        }
                    }
                    .font(.nyBody)
                    .tint(.secondary)
                } header: {
                    Text("Wine Info")
                        .font(.nyCaption)
                }
            }
            .navigationTitle("Edit Wine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.nyBody)
                    .foregroundColor(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveChanges()
                        dismiss()
                    }
                    .font(.nyBody)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                }
            }
            .onAppear {
                grapeVariety = wine.grapeVariety ?? ""
                region = wine.region ?? ""
                country = wine.country ?? ""
                winery = wine.winery ?? ""
                wineType = wine.wineType ?? ""
            }
            .sheet(isPresented: $showingVarietyPicker) {
                VarietalPickerView(selection: $grapeVariety)
            }
            .sheet(isPresented: $showingRegionPicker) {
                SearchablePickerView(
                    title: "Region",
                    selection: $region,
                    options: country.isEmpty
                        ? WineCatalog.shared.distinctRegions()
                        : WineCatalog.shared.distinctRegions(forCountry: country)
                )
            }
            .sheet(isPresented: $showingCountryPicker) {
                SearchablePickerView(
                    title: "Country",
                    selection: $country,
                    options: WineCatalog.shared.distinctCountries()
                )
            }
            .onChange(of: country) { _, _ in
                region = ""
            }
            .sheet(isPresented: $showingWineryPicker) {
                SearchablePickerView(
                    title: "Winery",
                    selection: $winery,
                    options: WineCatalog.shared.distinctWineries()
                )
            }
        }
    }

    private func saveChanges() {
        wine.grapeVariety = grapeVariety.isEmpty ? nil : grapeVariety
        wine.region = region.isEmpty ? nil : region
        wine.country = country.isEmpty ? nil : country
        wine.winery = winery.isEmpty ? nil : winery
        wine.wineType = wineType.isEmpty ? nil : wineType

        try? modelContext.save()
    }
}

struct SelectableRow: View {
    let label: String
    let value: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(label)
                    .font(.nyBody)
                    .foregroundColor(.primary)
                Spacer()
                Text(value.isEmpty ? "Select" : value)
                    .font(.nyBody)
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.right")
                    .font(.nyCaption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct VarietalPickerView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selection: String
    @State private var searchText = ""

    private let commonVarietals = [
        "Cabernet Sauvignon",
        "Merlot",
        "Pinot Noir",
        "Syrah",
        "Shiraz",
        "Malbec",
        "Carmenere",
        "Tempranillo",
        "Sangiovese",
        "Zinfandel",
        "Grenache",
        "Chardonnay",
        "Sauvignon Blanc",
        "Pinot Grigio",
        "Riesling",
        "Moscato",
        "Gewürztraminer",
        "Viognier",
        "Chenin Blanc",
        "Albariño"
    ]

    private var allVarietals: [String] {
        WineCatalog.shared.distinctVarieties()
    }

    private var filteredVarietals: [String] {
        if searchText.isEmpty {
            return allVarietals
        }
        return allVarietals.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredCommon: [String] {
        if searchText.isEmpty {
            return commonVarietals
        }
        return commonVarietals.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                // Clear option
                Button(action: {
                    selection = ""
                    dismiss()
                }) {
                    HStack {
                        Text("None")
                            .font(.nyBody)
                            .foregroundColor(.secondary)
                        Spacer()
                        if selection.isEmpty {
                            Image(systemName: "checkmark")
                                .foregroundColor(.wineRed)
                        }
                    }
                }

                // Common varietals section
                if !filteredCommon.isEmpty {
                    Section {
                        ForEach(filteredCommon, id: \.self) { varietal in
                            Button(action: {
                                selection = varietal
                                dismiss()
                            }) {
                                HStack {
                                    Text(varietal)
                                        .font(.nyBody)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if selection == varietal {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.wineRed)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Most Common")
                            .font(.nyCaption)
                    }
                }

                // All varietals section
                Section {
                    ForEach(filteredVarietals, id: \.self) { varietal in
                        Button(action: {
                            selection = varietal
                            dismiss()
                        }) {
                            HStack {
                                Text(varietal)
                                    .font(.nyBody)
                                    .foregroundColor(.primary)
                                Spacer()
                                if selection == varietal {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.wineRed)
                                }
                            }
                        }
                    }
                } header: {
                    Text("All Varietals")
                        .font(.nyCaption)
                }
            }
            .searchable(text: $searchText, prompt: "Search varietals")
            .navigationTitle("Grape Varietal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.nyBody)
                }
            }
        }
    }
}

struct SearchablePickerView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    @Binding var selection: String
    let options: [String]

    @State private var searchText = ""

    private var filteredOptions: [String] {
        if searchText.isEmpty {
            return options
        }
        return options.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                // Clear option
                Button(action: {
                    selection = ""
                    dismiss()
                }) {
                    HStack {
                        Text("None")
                            .font(.nyBody)
                            .foregroundColor(.secondary)
                        Spacer()
                        if selection.isEmpty {
                            Image(systemName: "checkmark")
                                .foregroundColor(.wineRed)
                        }
                    }
                }

                ForEach(filteredOptions, id: \.self) { option in
                    Button(action: {
                        selection = option
                        dismiss()
                    }) {
                        HStack {
                            Text(option)
                                .font(.nyBody)
                                .foregroundColor(.primary)
                            Spacer()
                            if selection == option {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.wineRed)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search \(title.lowercased())")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.nyBody)
                }
            }
        }
    }
}

struct InteractiveStarRating: View {
    @Binding var rating: Double

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: starImage(for: star))
                    .font(.nyTitle)
                    .foregroundColor(.wineRed)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.1)) {
                            rating = Double(star)
                        }
                    }
            }
        }
    }

    private func starImage(for star: Int) -> String {
        let starValue = Double(star)
        if rating >= starValue {
            return "star.fill"
        } else if rating >= starValue - 0.5 {
            return "star.leadinghalf.filled"
        } else {
            return "star"
        }
    }
}

struct SaveConfirmationView: View {
    var body: some View {
        VStack {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.wineRed)

            Text("Rating Saved!")
                .font(.nyHeadline)
                .padding(.top, 8)
        }
        .padding(32)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
    }
}

struct RatingHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    let wine: Wine

    private var sortedRatings: [UserRating] {
        (wine.userRatings ?? []).sorted { $0.dateRated > $1.dateRated }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sortedRatings) { rating in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            // Rating stars
                            HStack(spacing: 2) {
                                ForEach(0..<5) { index in
                                    Image(systemName: index < Int(rating.rating) ? "star.fill" : "star")
                                        .font(.system(size: 14))
                                        .foregroundColor(.wineRed)
                                }
                            }

                            Text(String(format: "%.1f", rating.rating))
                                .font(.nyHeadline)
                                .foregroundColor(.wineRed)

                            Spacer()

                            // Vintage if different from wine's current
                            if let vintage = rating.vintage {
                                Text(String(vintage))
                                    .font(.nyCaption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.wineRed.opacity(0.15))
                                    .foregroundColor(.wineRed)
                                    .cornerRadius(4)
                            }
                        }

                        // Date
                        Text(rating.dateRated.formatted(date: .abbreviated, time: .shortened))
                            .font(.nyCaption)
                            .foregroundColor(.secondary)

                        // Notes if present
                        if let notes = rating.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.nyBody)
                                .foregroundColor(.primary)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Rating History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.nyBody)
                }
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                       y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
                self.size.width = max(self.size.width, x)
            }
            self.size.height = y + rowHeight
        }
    }
}

#Preview {
    NavigationStack {
        WineDetailView(wine: Wine(
            name: "Château Margaux",
            vintage: 2015,
            region: "Margaux",
            grapeVariety: "Cabernet Sauvignon Blend",
            averageRating: 4.7,
            winery: "Château Margaux",
            country: "France",
            priceUSD: 650
        ))
    }
    .modelContainer(for: [Wine.self, UserRating.self], inMemory: true)
}
