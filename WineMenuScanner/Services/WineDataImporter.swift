import Foundation
import SwiftData

actor WineDataImporter {
    private var hasImported = false

    struct ImportProgress {
        let current: Int
        let total: Int
        let message: String

        var percentage: Double {
            guard total > 0 else { return 0 }
            return Double(current) / Double(total)
        }
    }

    static func importWinesIfNeeded(
        modelContext: ModelContext,
        forceReimport: Bool = false,
        progressHandler: ((ImportProgress) -> Void)? = nil
    ) async {
        if forceReimport {
            await importWines(modelContext: modelContext, progressHandler: progressHandler)
            return
        }

        // Check if wines already exist
        let descriptor = FetchDescriptor<Wine>()
        let existingCount = (try? modelContext.fetchCount(descriptor)) ?? 0

        guard existingCount == 0 else {
            return
        }

        await importWines(modelContext: modelContext, progressHandler: progressHandler)
    }

    func importWinesIfNeeded(modelContext: ModelContext) async {
        guard !hasImported else { return }

        // Check if wines already exist
        let descriptor = FetchDescriptor<Wine>()
        let existingCount = (try? modelContext.fetchCount(descriptor)) ?? 0

        guard existingCount == 0 else {
            hasImported = true
            return
        }

        await Self.importWines(modelContext: modelContext, progressHandler: nil)
        hasImported = true
    }

    private static func importWines(
        modelContext: ModelContext,
        progressHandler: ((ImportProgress) -> Void)?
    ) async {
        guard let url = Bundle.main.url(forResource: "wines", withExtension: "csv") else {
            print("Could not find wines.csv in bundle")
            return
        }

        do {
            await MainActor.run {
                progressHandler?(ImportProgress(current: 0, total: 100, message: "Reading wine database..."))
            }

            let content = try String(contentsOf: url, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
                .dropFirst() // Skip header
                .filter { !$0.isEmpty }

            let totalLines = lines.count
            var count = 0
            let batchSize = 250 // Even smaller batches for mobile

            await MainActor.run {
                progressHandler?(ImportProgress(current: 0, total: totalLines, message: "Importing \(totalLines.formatted()) wines..."))
            }

            // Process in batches on a background thread
            let linesArray = Array(lines)

            for batchStart in stride(from: 0, to: linesArray.count, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, linesArray.count)
                let batch = linesArray[batchStart..<batchEnd]

                // Process batch
                autoreleasepool {
                    for line in batch {
                        if let wine = parseWineLine(line) {
                            modelContext.insert(wine)
                            count += 1
                        }
                    }
                }

                // Save this batch
                try modelContext.save()

                // Update progress on main thread
                let currentCount = count
                await MainActor.run {
                    progressHandler?(ImportProgress(
                        current: currentCount,
                        total: totalLines,
                        message: "Imported \(currentCount.formatted()) of \(totalLines.formatted()) wines..."
                    ))
                }

                // Small delay to prevent blocking
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            }

            await MainActor.run {
                progressHandler?(ImportProgress(
                    current: totalLines,
                    total: totalLines,
                    message: "Import complete!"
                ))
            }

            print("Imported \(count) wines successfully")
        } catch {
            print("Error importing wines: \(error)")
        }
    }

    private static func parseWineLine(_ line: String) -> Wine? {
        // CSV format: name,winery,variety,region,country,vintage,rating,price,type,body,acidity,food_pairings
        let fields = parseCSVLine(line)

        guard fields.count >= 5 else { return nil }

        let name = fields[0]
        guard !name.isEmpty else { return nil }

        let winery = fields.count > 1 && !fields[1].isEmpty ? fields[1] : nil
        let variety = fields.count > 2 && !fields[2].isEmpty ? fields[2] : nil
        let region = fields.count > 3 && !fields[3].isEmpty ? fields[3] : nil
        let country = fields.count > 4 && !fields[4].isEmpty ? fields[4] : nil
        let vintage = fields.count > 5 ? Int(fields[5]) : nil
        let rating = fields.count > 6 ? Double(fields[6]) : nil
        let price = fields.count > 7 ? Double(fields[7]) : nil
        let wineType = fields.count > 8 && !fields[8].isEmpty ? fields[8] : nil
        let body = fields.count > 9 && !fields[9].isEmpty ? fields[9] : nil
        let acidity = fields.count > 10 && !fields[10].isEmpty ? fields[10] : nil
        let foodPairings = fields.count > 11 && !fields[11].isEmpty ? fields[11] : nil

        return Wine(
            name: name,
            vintage: vintage,
            region: region,
            grapeVariety: variety,
            averageRating: rating,
            winery: winery,
            country: country,
            priceUSD: price,
            wineType: wineType,
            body: body,
            acidity: acidity,
            foodPairings: foodPairings
        )
    }

    private static func parseCSVLine(_ line: String) -> [String] {
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
