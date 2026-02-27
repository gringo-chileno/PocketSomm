import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct WineDataImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isImporting = false
    @State private var importResult: ImportResult?
    @State private var showingFilePicker = false

    struct ImportResult {
        let imported: Int
        let skipped: Int
        let errors: [String]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let result = importResult {
                    // Results view
                    VStack(spacing: 16) {
                        Image(systemName: result.imported > 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(result.imported > 0 ? .green : .orange)

                        Text("Import Complete")
                            .font(.nyTitle2)
                            .fontWeight(.semibold)

                        VStack(spacing: 8) {
                            HStack {
                                Text("Wines imported:")
                                Spacer()
                                Text("\(result.imported)")
                                    .fontWeight(.semibold)
                            }

                            HStack {
                                Text("Duplicates skipped:")
                                Spacer()
                                Text("\(result.skipped)")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .font(.nyBody)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)

                        if !result.errors.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Errors:")
                                    .font(.nySubheadline)
                                    .fontWeight(.semibold)

                                ForEach(result.errors.prefix(5), id: \.self) { error in
                                    Text(error)
                                        .font(.nyCaption)
                                        .foregroundColor(.red)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(12)
                        }

                        Button("Done") {
                            dismiss()
                        }
                        .font(.nyHeadline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.wineRed)
                        .cornerRadius(10)
                    }
                    .padding()
                } else if isImporting {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)

                        Text("Importing wines...")
                            .font(.nyBody)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    // Initial view
                    VStack(spacing: 20) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 60))
                            .foregroundColor(.wineRed.opacity(0.7))

                        Text("Import Wine Database")
                            .font(.nyTitle2)
                            .fontWeight(.semibold)

                        Text("Add wines from a CSV file. The file should have columns for wine name, winery, variety, region, country, and optionally vintage, rating, and type.")
                            .font(.nyBody)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Expected CSV format:")
                                .font(.nySubheadline)
                                .fontWeight(.semibold)

                            Text("name, winery, variety, region, country, vintage, rating, type")
                                .font(.system(.caption, design: .monospaced))
                                .padding(8)
                                .background(Color(.tertiarySystemBackground))
                                .cornerRadius(6)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)

                        Spacer()

                        Button(action: { showingFilePicker = true }) {
                            HStack {
                                Image(systemName: "folder")
                                Text("Select CSV File")
                            }
                            .font(.nyHeadline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.wineRed)
                            .cornerRadius(10)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Import Wines")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.nyBody)
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [UTType.commaSeparatedText, UTType.plainText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        importWines(from: url)
                    }
                case .failure(let error):
                    print("File picker error: \(error)")
                }
            }
        }
    }

    private func importWines(from url: URL) {
        isImporting = true

        Task {
            var imported = 0
            var skipped = 0
            var errors: [String] = []

            do {
                guard url.startAccessingSecurityScopedResource() else {
                    throw NSError(domain: "WineImport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot access file"])
                }
                defer { url.stopAccessingSecurityScopedResource() }

                let content = try String(contentsOf: url, encoding: .utf8)
                let lines = content.components(separatedBy: .newlines)

                guard !lines.isEmpty else {
                    throw NSError(domain: "WineImport", code: 2, userInfo: [NSLocalizedDescriptionKey: "File is empty"])
                }

                // Parse header to find column indices
                let headerLine = lines[0].lowercased()
                let headers = parseCSVLine(headerLine)

                let nameIndex = headers.firstIndex { $0.contains("name") } ?? 0
                let wineryIndex = headers.firstIndex { $0.contains("winery") }
                let varietyIndex = headers.firstIndex { $0.contains("variety") || $0.contains("grape") }
                let regionIndex = headers.firstIndex { $0.contains("region") }
                let countryIndex = headers.firstIndex { $0.contains("country") }
                let vintageIndex = headers.firstIndex { $0.contains("vintage") || $0.contains("year") }
                let ratingIndex = headers.firstIndex { $0.contains("rating") }
                let typeIndex = headers.firstIndex { $0.contains("type") }

                // Process each line
                for (index, line) in lines.dropFirst().enumerated() {
                    guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }

                    let fields = parseCSVLine(line)
                    guard fields.count > nameIndex else {
                        errors.append("Line \(index + 2): Not enough columns")
                        continue
                    }

                    let name = fields[nameIndex].trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { continue }

                    // Check for duplicate
                    let descriptor = FetchDescriptor<Wine>(
                        predicate: #Predicate<Wine> { wine in
                            wine.name == name
                        }
                    )
                    let existingCount = (try? modelContext.fetchCount(descriptor)) ?? 0

                    if existingCount > 0 {
                        skipped += 1
                        continue
                    }

                    // Create wine
                    let wine = Wine(
                        name: name,
                        vintage: vintageIndex.flatMap { fields.count > $0 ? Int(fields[$0]) : nil },
                        region: regionIndex.flatMap { fields.count > $0 && !fields[$0].isEmpty ? fields[$0] : nil },
                        grapeVariety: varietyIndex.flatMap { fields.count > $0 && !fields[$0].isEmpty ? fields[$0] : nil },
                        averageRating: ratingIndex.flatMap { fields.count > $0 ? Double(fields[$0]) : nil },
                        winery: wineryIndex.flatMap { fields.count > $0 && !fields[$0].isEmpty ? fields[$0] : nil },
                        country: countryIndex.flatMap { fields.count > $0 && !fields[$0].isEmpty ? fields[$0] : nil },
                        priceUSD: nil,
                        wineType: typeIndex.flatMap { fields.count > $0 && !fields[$0].isEmpty ? fields[$0] : nil },
                        body: nil,
                        acidity: nil,
                        foodPairings: nil
                    )

                    modelContext.insert(wine)
                    imported += 1
                }

                try modelContext.save()

            } catch {
                errors.append(error.localizedDescription)
            }

            await MainActor.run {
                importResult = ImportResult(imported: imported, skipped: skipped, errors: errors)
                isImporting = false
            }
        }
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

#Preview {
    WineDataImportView()
        .modelContainer(for: Wine.self, inMemory: true)
}
