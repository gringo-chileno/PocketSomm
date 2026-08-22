import SwiftUI
import SwiftData

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showingVivinoImport = false
    @State private var showingResetConfirmation = false
    @State private var showingFeedback = false
    @State private var showingExport = false
    @State private var csvURL: URL?

    var body: some View {
        NavigationStack {
            List {
                // Appearance Section
                Section {
                    ForEach(AppColorScheme.allCases) { scheme in
                        Button(action: {
                            settings.colorScheme = scheme
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(scheme.rawValue)
                                        .font(.nyBody)
                                        .foregroundColor(.primary)
                                    Text(scheme.description)
                                        .font(.nyCaption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if settings.colorScheme == scheme {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Appearance")
                        .font(.nyCaption)
                } footer: {
                    Text("Dark mode gives the app a more premium, modern feel.")
                        .font(.nyCaption)
                }

                // Data Import Section
                Section {
                    Button(action: { showingVivinoImport = true }) {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                                .foregroundColor(.white)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Import Ratings")
                                    .font(.nyBody)
                                    .foregroundColor(.primary)
                                Text("Import wine ratings from a CSV file (Vivino export, etc.)")
                                    .font(.nyCaption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    Button(action: { exportCSV() }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.white)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Export My Wines")
                                    .font(.nyBody)
                                    .foregroundColor(.primary)
                                Text("Save all your wines and ratings as a CSV backup")
                                    .font(.nyCaption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Data")
                        .font(.nyCaption)
                }

                // Feedback Section
                Section {
                    Button(action: { showingFeedback = true }) {
                        HStack {
                            Image(systemName: "envelope")
                                .foregroundColor(.white)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Send Feedback")
                                    .font(.nyBody)
                                    .foregroundColor(.primary)
                                Text("Report a bug or request a feature")
                                    .font(.nyCaption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Feedback")
                        .font(.nyCaption)
                }

                // About Section
                Section {
                    HStack {
                        Text("Version")
                            .font(.nyBody)
                        Spacer()
                        Text("1.0.1")
                            .font(.nyBody)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Wine Catalog")
                            .font(.nyBody)
                        Spacer()
                        Text("\(WineCatalog.shared.totalWines.formatted()) wines")
                            .font(.nyBody)
                            .foregroundColor(.secondary)
                    }

                    Link(destination: URL(string: "https://github.com/rogerioxavier/X-Wines")!) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Catalog based on the X-Wines dataset")
                                .font(.nyBody)
                                .foregroundColor(.primary)
                            Text("de Azambuja, Morais & Filipe, 2023 (CC0)")
                                .font(.nyCaption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("About")
                        .font(.nyCaption)
                }

                // Developer Section
                Section {
                    Button(action: { showingResetConfirmation = true }) {
                        HStack {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Clear My Data")
                                    .font(.nyBody)
                                    .foregroundColor(.red)
                                Text("Delete all ratings and scan history")
                                    .font(.nyCaption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Developer")
                        .font(.nyCaption)
                } footer: {
                    Text("The wine catalog (\(WineCatalog.shared.totalWines.formatted()) wines) is built-in and won't be deleted.")
                        .font(.nyCaption)
                }
            }
            .navigationTitle("Settings")
            .alert("Clear All Data?", isPresented: $showingResetConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) {
                    clearUserData()
                }
            } message: {
                Text("This will delete all your ratings and scan history. This cannot be undone.")
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.nyBody)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                }
            }
            .sheet(isPresented: $showingVivinoImport) {
                VivinoImportView()
            }
            .sheet(isPresented: $showingFeedback) {
                FeedbackView()
            }
            .sheet(isPresented: $showingExport) {
                if let url = csvURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    private func exportCSV() {
        let descriptor = FetchDescriptor<Wine>(sortBy: [SortDescriptor(\.name)])
        guard let wines = try? modelContext.fetch(descriptor), !wines.isEmpty else { return }

        var csv = "Name,Vintage,Winery,Variety,Region,Country,Type,My Rating,Rating Date,Notes,Community Rating,Vivino Rating\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for wine in wines {
            let rating = wine.userRating
            let fields: [String] = [
                escapeCSV(wine.name),
                wine.vintage.map { String($0) } ?? "",
                escapeCSV(wine.winery ?? ""),
                escapeCSV(wine.grapeVariety ?? ""),
                escapeCSV(wine.region ?? ""),
                escapeCSV(wine.country ?? ""),
                escapeCSV(wine.wineType ?? ""),
                rating.map { String(format: "%.1f", $0.rating) } ?? "",
                rating.map { dateFormatter.string(from: $0.dateRated) } ?? "",
                escapeCSV(rating?.notes ?? ""),
                wine.averageRating.map { String(format: "%.1f", $0) } ?? "",
                wine.vivinoRating.map { String(format: "%.1f", $0) } ?? ""
            ]
            csv += fields.joined(separator: ",") + "\n"
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pocket_somm_export_\(dateFormatter.string(from: Date())).csv")
        do {
            try csv.write(to: tempURL, atomically: true, encoding: .utf8)
            csvURL = tempURL
            showingExport = true
        } catch {
            print("Error writing CSV: \(error)")
        }
    }

    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private func clearUserData() {
        do {
            try modelContext.delete(model: UserRating.self)
            try modelContext.delete(model: ScanHistory.self)
            try modelContext.delete(model: Wine.self)
            try modelContext.save()
        } catch {
            print("Error clearing data: \(error)")
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    SettingsView()
}
