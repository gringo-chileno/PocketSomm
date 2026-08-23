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
        // Some catalog names already end with the year — don't double it
        if let vintage = vintage, !name.contains(String(vintage)) {
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
    // Serial: Apple's sqlite ships THREADSAFE=2 (no per-connection mutex), so
    // two threads inside the same connection is undefined behavior
    private let queue = DispatchQueue(label: "wine.catalog.queue")
    // Cached set of known winery names (lowercased, accent-folded) for O(1) lookup
    private var knownWineries: Set<String> = []
    // The catalog is read-only, so distinct-value lists never change — cache
    // them; the pickers otherwise re-query on every sheet render
    private var distinctCache: [String: [String]] = [:]

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
        // WINE_CATALOG_PATH override lets the offline harness in scripts/
        // run this class on a Mac against the repo copy of the catalog
        let envPath = ProcessInfo.processInfo.environment["WINE_CATALOG_PATH"]
        guard let dbPath = envPath ?? Bundle.main.path(forResource: "wines_catalog", ofType: "sqlite") else {
            print("Could not find wines_catalog.sqlite in bundle")
            return
        }

        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            print("Failed to open database: \(String(cString: sqlite3_errmsg(db)))")
            return
        }

        print("Wine catalog opened: \(totalWines) wines")

        // Register custom UNACCENT function for accent-insensitive search
        sqlite3_create_function(db, "UNACCENT", 1, SQLITE_UTF8, nil, { context, argc, argv in
            guard let value = sqlite3_value_text(argv![0]) else {
                sqlite3_result_null(context)
                return
            }
            let str = String(cString: value)
            let folded = str.folding(options: .diacriticInsensitive, locale: .current)
            folded.withCString { cStr in
                sqlite3_result_text(context, cStr, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
        }, nil, nil)

        // Build cached set of known wineries for fast O(1) lookup
        buildWineryCache()
    }

    private func buildWineryCache() {
        queue.sync {
            let sql = "SELECT DISTINCT winery FROM wines WHERE winery IS NOT NULL AND winery != ''"
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    if let ptr = sqlite3_column_text(statement, 0) {
                        let name = String(cString: ptr)
                            .folding(options: .diacriticInsensitive, locale: .current)
                            .lowercased()
                        knownWineries.insert(name)
                    }
                }
            }
            sqlite3_finalize(statement)
        }
        print("Cached \(knownWineries.count) distinct wineries")
    }

    func search(query: String, limit: Int = 50) -> [CatalogWine] {
        guard !query.isEmpty else { return [] }

        var results: [CatalogWine] = []
        // Strip diacritics and punctuation from search terms
        let searchTerms = query.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .components(separatedBy: .whitespaces)
            .map { $0.filter { $0.isLetter || $0.isNumber || $0 == " " } }
            .filter { !$0.isEmpty }

        queue.sync {
            // search_text is a precomputed accent-folded lowercase concat of
            // name/winery/variety/region/country — plain LIKE against it is
            // ~50x faster than calling UNACCENT() five times per row
            var conditions: [String] = []
            var params: [String] = []

            for term in searchTerms {
                conditions.append("search_text LIKE ?")
                params.append("%\(term)%")
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
        let cacheKey = "region-\(country)-\(limit)"
        if let cached = queue.sync(execute: { distinctCache[cacheKey] }) {
            return cached
        }
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
            distinctCache[cacheKey] = results
        }

        return results
    }

    /// Quick check if text matches a known winery name in the catalog (accent-insensitive)
    func isKnownWinery(_ name: String) -> Bool {
        let folded = name.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        return knownWineries.contains(folded)
    }

    func distinctWineries(limit: Int = 500) -> [String] {
        return distinctValues(column: "winery", limit: limit)
    }

    private func distinctValues(column: String, limit: Int) -> [String] {
        let cacheKey = "\(column)-\(limit)"
        if let cached = queue.sync(execute: { distinctCache[cacheKey] }) {
            return cached
        }
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
            distinctCache[cacheKey] = results
        }

        return results
    }

    deinit {
        sqlite3_close(db)
    }
}
