import SwiftUI
import SwiftData

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showingVivinoImport = false
    @State private var showingResetConfirmation = false

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
                                .foregroundColor(.wineRed)
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
                } header: {
                    Text("Data")
                        .font(.nyCaption)
                }

                // About Section
                Section {
                    HStack {
                        Text("Version")
                            .font(.nyBody)
                        Spacer()
                        Text("1.0.0")
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
        }
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

#Preview {
    SettingsView()
}
