import Foundation
import SQLite3

// Lightweight wine struct from the catalog (not SwiftData)
struct CatalogWine: Identifiable, Hashable {
    let id: Int64
    let name: String
    let winery: String?
    let variety: String?
    let region: String?
    let country: String?
    let vintage: Int?
    let rating: Double?
    let price: Double?
    let wineType: String?
    let body: String?
    let acidity: String?
    let foodPairings: String?

    var displayName: String {
        if let vintage = vintage {
            return "\(name) \(vintage)"
        }
        return name
    }

    // Parse food pairings from JSON-like string
    var foodPairingsArray: [String] {
        guard let pairings = foodPairings, !pairings.isEmpty else { return [] }
        // Format: "['Beef', 'Lamb', 'Poultry']"
        let cleaned = pairings
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: "'", with: "")
        return cleaned.components(separatedBy: ", ").filter { !$0.isEmpty }
    }
}

class WineCatalog {
    static let shared = WineCatalog()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "wine.catalog.queue", attributes: .concurrent)

    var totalWines: Int {
        var count = 0
        queue.sync {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM wines", -1, &statement, nil) == SQLITE_OK {
                if sqlite3_step(statement) == SQLITE_ROW {
                    count = Int(sqlite3_column_int64(statement, 0))
                }
            }
            sqlite3_finalize(statement)
        }
        return count
    }

    private init() {
        openDatabase()
    }

    private func openDatabase() {
        guard let dbPath = Bundle.main.path(forResource: "wines_catalog", ofType: "sqlite") else {
            print("Could not find wines_catalog.sqlite in bundle")
            return
        }

        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            print("Failed to open database: \(String(cString: sqlite3_errmsg(db)))")
            return
        }

        print("Wine catalog opened: \(totalWines) wines")
    }

    func search(query: String, limit: Int = 50) -> [CatalogWine] {
        guard !query.isEmpty else { return [] }

        var results: [CatalogWine] = []
        let searchTerms = query.lowercased()
            .components(separatedBy: .whitespaces)
            .map { $0.filter { $0.isLetter || $0.isNumber || $0 == " " } }
            .filter { !$0.isEmpty }

        queue.sync {
            // Build WHERE clause for each term
            var conditions: [String] = []
            var params: [String] = []

            for term in searchTerms {
                conditions.append("(LOWER(name) LIKE ? OR LOWER(winery) LIKE ? OR LOWER(variety) LIKE ? OR LOWER(region) LIKE ? OR LOWER(country) LIKE ?)")
                let likeTerm = "%\(term)%"
                params.append(contentsOf: [likeTerm, likeTerm, likeTerm, likeTerm, likeTerm])
            }

            let sql = """
                SELECT id, name, winery, variety, region, country, vintage, rating, price, type, body, acidity, food_pairings
                FROM wines
                WHERE \(conditions.joined(separator: " AND "))
                ORDER BY rating DESC
                LIMIT ?
            """

            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                // Bind parameters
                for (index, param) in params.enumerated() {
                    sqlite3_bind_text(statement, Int32(index + 1), param, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
                sqlite3_bind_int(statement, Int32(params.count + 1), Int32(limit))

                while sqlite3_step(statement) == SQLITE_ROW {
                    if let wine = wineFromStatement(statement) {
                        results.append(wine)
                    }
                }
            }
            sqlite3_finalize(statement)
        }

        return results
    }

    func findWine(byName name: String) -> CatalogWine? {
        var result: CatalogWine?

        queue.sync {
            let sql = """
                SELECT id, name, winery, variety, region, country, vintage, rating, price, type, body, acidity, food_pairings
                FROM wines
                WHERE LOWER(name) LIKE ?
                LIMIT 1
            """

            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                let likeName = "%\(name.lowercased())%"
                sqlite3_bind_text(statement, 1, likeName, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

                if sqlite3_step(statement) == SQLITE_ROW {
                    result = wineFromStatement(statement)
                }
            }
            sqlite3_finalize(statement)
        }

        return result
    }

    func getWine(byId id: Int64) -> CatalogWine? {
        var result: CatalogWine?

        queue.sync {
            let sql = """
                SELECT id, name, winery, variety, region, country, vintage, rating, price, type, body, acidity, food_pairings
                FROM wines
                WHERE id = ?
            """

            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int64(statement, 1, id)

                if sqlite3_step(statement) == SQLITE_ROW {
                    result = wineFromStatement(statement)
                }
            }
            sqlite3_finalize(statement)
        }

        return result
    }

    func winesByCountry(_ country: String, limit: Int = 100) -> [CatalogWine] {
        var results: [CatalogWine] = []

        queue.sync {
            let sql = """
                SELECT id, name, winery, variety, region, country, vintage, rating, price, type, body, acidity, food_pairings
                FROM wines
                WHERE country = ?
                ORDER BY rating DESC
                LIMIT ?
            """

            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, country, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_int(statement, 2, Int32(limit))

                while sqlite3_step(statement) == SQLITE_ROW {
                    if let wine = wineFromStatement(statement) {
                        results.append(wine)
                    }
                }
            }
            sqlite3_finalize(statement)
        }

        return results
    }

    private func wineFromStatement(_ statement: OpaquePointer?) -> CatalogWine? {
        guard let statement = statement else { return nil }

        let id = sqlite3_column_int64(statement, 0)
        guard let namePtr = sqlite3_column_text(statement, 1) else { return nil }
        let name = String(cString: namePtr)

        return CatalogWine(
            id: id,
            name: name,
            winery: columnText(statement, 2),
            variety: columnText(statement, 3),
            region: columnText(statement, 4),
            country: columnText(statement, 5),
            vintage: columnInt(statement, 6),
            rating: columnDouble(statement, 7),
            price: columnDouble(statement, 8),
            wineType: columnText(statement, 9),
            body: columnText(statement, 10),
            acidity: columnText(statement, 11),
            foodPairings: columnText(statement, 12)
        )
    }

    private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let ptr = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: ptr)
    }

    private func columnInt(_ statement: OpaquePointer?, _ index: Int32) -> Int? {
        if sqlite3_column_type(statement, index) == SQLITE_NULL { return nil }
        return Int(sqlite3_column_int(statement, index))
    }

    private func columnDouble(_ statement: OpaquePointer?, _ index: Int32) -> Double? {
        if sqlite3_column_type(statement, index) == SQLITE_NULL { return nil }
        return sqlite3_column_double(statement, index)
    }

    // MARK: - Distinct Values for Pickers

    func distinctVarieties(limit: Int = 200) -> [String] {
        return distinctValues(column: "variety", limit: limit)
    }

    func distinctCountries(limit: Int = 100) -> [String] {
        return distinctValues(column: "country", limit: limit)
    }

    func distinctRegions(limit: Int = 300) -> [String] {
        return distinctValues(column: "region", limit: limit)
    }

    func distinctRegions(forCountry country: String, limit: Int = 300) -> [String] {
        var results: [String] = []

        queue.sync {
            let sql = """
                SELECT DISTINCT region
                FROM wines
                WHERE country = ? AND region IS NOT NULL AND region != ''
                ORDER BY region
                LIMIT ?
            """

            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, country, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_int(statement, 2, Int32(limit))

                while sqlite3_step(statement) == SQLITE_ROW {
                    if let ptr = sqlite3_column_text(statement, 0) {
                        results.append(String(cString: ptr))
                    }
                }
            }
            sqlite3_finalize(statement)
        }

        return results
    }

    func distinctWineries(limit: Int = 500) -> [String] {
        return distinctValues(column: "winery", limit: limit)
    }

    private func distinctValues(column: String, limit: Int) -> [String] {
        var results: [String] = []

        queue.sync {
            let sql = """
                SELECT DISTINCT \(column)
                FROM wines
                WHERE \(column) IS NOT NULL AND \(column) != ''
                ORDER BY \(column)
                LIMIT ?
            """

            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(limit))

                while sqlite3_step(statement) == SQLITE_ROW {
                    if let ptr = sqlite3_column_text(statement, 0) {
                        results.append(String(cString: ptr))
                    }
                }
            }
            sqlite3_finalize(statement)
        }

        return results
    }

    deinit {
        sqlite3_close(db)
    }
}
