import SwiftUI
import SwiftData

struct AddWineView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let initialName: String
    var onWineCreated: ((Wine) -> Void)?

    @State private var name: String = ""
    @State private var winery: String = ""
    @State private var grapeVariety: String = ""
    @State private var region: String = ""
    @State private var country: String = ""
    @State private var wineType: String = "Red"
    @State private var vintage: Int?

    // Picker states
    @State private var showingVintagePicker = false
    @State private var showingVarietyPicker = false
    @State private var showingCountryPicker = false
    @State private var showingRegionPicker = false

    private let wineTypeOptions = ["Red", "White", "Rosé", "Sparkling", "Dessert", "Fortified"]

    init(initialName: String = "", onWineCreated: ((Wine) -> Void)? = nil) {
        self.initialName = initialName
        self.onWineCreated = onWineCreated
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Wine Name", text: $name)
                        .font(.nyBody)

                    TextField("Winery", text: $winery)
                        .font(.nyBody)

                    // Vintage picker
                    Button(action: { showingVintagePicker = true }) {
                        HStack {
                            Text("Vintage")
                                .font(.nyBody)
                                .foregroundColor(.primary)
                            Spacer()
                            Text(vintage != nil ? String(vintage!) : "Select")
                                .font(.nyBody)
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.nyCaption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Basic Info")
                        .font(.nyCaption)
                }

                Section {
                    // Wine Type picker
                    Picker("Wine Type", selection: $wineType) {
                        ForEach(wineTypeOptions, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    .font(.nyBody)
                    .tint(.secondary)

                    // Grape Varietal picker
                    Button(action: { showingVarietyPicker = true }) {
                        HStack {
                            Text("Grape Varietal")
                                .font(.nyBody)
                                .foregroundColor(.primary)
                            Spacer()
                            Text(grapeVariety.isEmpty ? "Select" : grapeVariety)
                                .font(.nyBody)
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.nyCaption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Wine Details")
                        .font(.nyCaption)
                }

                Section {
                    // Country picker
                    Button(action: { showingCountryPicker = true }) {
                        HStack {
                            Text("Country")
                                .font(.nyBody)
                                .foregroundColor(.primary)
                            Spacer()
                            Text(country.isEmpty ? "Select" : country)
                                .font(.nyBody)
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.nyCaption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Region picker
                    Button(action: { showingRegionPicker = true }) {
                        HStack {
                            Text("Region")
                                .font(.nyBody)
                                .foregroundColor(.primary)
                            Spacer()
                            Text(region.isEmpty ? "Select" : region)
                                .font(.nyBody)
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.nyCaption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Origin")
                        .font(.nyCaption)
                }
            }
            .navigationTitle("Add Wine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.nyBody)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveWine()
                    }
                    .font(.nyBody)
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                name = initialName
            }
            .sheet(isPresented: $showingVintagePicker) {
                AddWineVintagePicker(selectedVintage: $vintage)
            }
            .sheet(isPresented: $showingVarietyPicker) {
                VarietalPickerView(selection: $grapeVariety)
            }
            .sheet(isPresented: $showingCountryPicker) {
                SearchablePickerView(
                    title: "Country",
                    selection: $country,
                    options: WineCatalog.shared.distinctCountries()
                )
            }
            .sheet(isPresented: $showingRegionPicker) {
                SearchablePickerView(
                    title: "Region",
                    selection: $region,
                    options: WineCatalog.shared.distinctRegions()
                )
            }
        }
    }

    private func saveWine() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let wine = Wine(
            name: trimmedName,
            vintage: vintage,
            region: region.isEmpty ? nil : region,
            grapeVariety: grapeVariety.isEmpty ? nil : grapeVariety,
            averageRating: nil,
            winery: winery.isEmpty ? nil : winery,
            country: country.isEmpty ? nil : country,
            priceUSD: nil,
            wineType: wineType,
            body: nil,
            acidity: nil,
            foodPairings: nil
        )

        modelContext.insert(wine)

        do {
            try modelContext.save()
            onWineCreated?(wine)
            dismiss()
        } catch {
            print("Error saving wine: \(error)")
        }
    }
}

// Simplified vintage picker for AddWineView
struct AddWineVintagePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedVintage: Int?

    private let currentYear = Calendar.current.component(.year, from: Date())
    private var vintageRange: [Int] {
        Array((currentYear - 100)...currentYear).reversed()
    }

    var body: some View {
        NavigationStack {
            List {
                Button(action: {
                    selectedVintage = nil
                    dismiss()
                }) {
                    HStack {
                        Text("No Vintage (NV)")
                            .font(.nyBody)
                            .foregroundColor(.secondary)
                        Spacer()
                        if selectedVintage == nil {
                            Image(systemName: "checkmark")
                                .foregroundColor(.wineRed)
                        }
                    }
                }

                ForEach(vintageRange, id: \.self) { year in
                    Button(action: {
                        selectedVintage = year
                        dismiss()
                    }) {
                        HStack {
                            Text(String(year))
                                .font(.nyBody)
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedVintage == year {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.wineRed)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Vintage")
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

#Preview {
    AddWineView(initialName: "My Custom Wine")
        .modelContainer(for: Wine.self, inMemory: true)
}
