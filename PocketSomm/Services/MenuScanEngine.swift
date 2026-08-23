import Foundation

/// Pure menu-scan logic: turning OCR text lines into wine-name entries, and
/// matching an entry against the bundled catalog. UI-free so the offline
/// harness in scripts/ can exercise it against the real catalog.
enum MenuScanEngine {

    /// Separator used to encode variety context with wine names: "name\tvariety"
    static let varietySeparator = "\t"

    // Grape varieties — used for section header detection and variety context
    static let sectionVarieties: Set<String> = [
        "cabernet sauvignon", "cabernet franc", "cabernet", "merlot",
        "pinot noir", "pinot grigio", "pinot gris", "pinot",
        "chardonnay", "sauvignon blanc", "sauvignon",
        "syrah", "shiraz", "riesling", "malbec", "zinfandel",
        "carmenere", "carménère", "carmenère",
        "tempranillo", "sangiovese", "garnacha", "grenache",
        "cinsault", "cinsaut", "mourvèdre", "mourvedre",
        "pais", "país", "viognier", "gewürztraminer", "gewurztraminer",
        "semillon", "sémillon", "muscat", "moscatel",
        "torrontés", "torrontes", "touriga nacional",
        "carignan", "petit verdot", "petit sirah", "petite sirah",
        "blanc", "rosé", "rose", "tinto", "blanco", "noir",
        "red blend", "white blend"
    ]

    // Narrower list used when deciding whether a comma-part names a grape
    static let partVarieties: Set<String> = [
        "cabernet sauvignon", "cabernet franc", "cabernet", "merlot",
        "pinot noir", "pinot grigio", "pinot gris", "pinot",
        "chardonnay", "sauvignon blanc", "sauvignon",
        "syrah", "shiraz", "riesling", "malbec", "zinfandel",
        "carmenere", "carménère", "tempranillo", "sangiovese",
        "garnacha", "grenache", "cinsault", "mourvèdre",
        "pais", "país", "viognier", "gewürztraminer",
        "semillon", "sémillon", "muscat", "moscatel",
        "torrontés", "carignan", "petit verdot", "petite sirah",
        "nebbiolo", "red blend", "white blend", "ensamblaje"
    ]

    // Common wine regions — skip when standalone, and recognize
    // variety+region-only lines that carry no wine identity
    static let regionNames: Set<String> = [
        // Chile
        "cachapoal", "colchagua", "maipo", "casablanca", "aconcagua",
        "cauquenes", "itata", "curicó", "curico", "rapel", "maule",
        "san antonio", "leyda", "limarí", "limari", "elqui", "bío-bío",
        "malleco", "marchigüe", "marchigue", "apalta", "millahue",
        "maipo andes", "central valley", "millahue cachapoal",
        // France
        "bordeaux", "burgundy", "bourgogne", "champagne", "rhône",
        "alsace", "loire", "provence", "languedoc", "roussillon",
        // Italy
        "tuscany", "toscana", "piedmont", "piemonte", "veneto", "sicily",
        // Spain
        "rioja", "ribera del duero", "priorat", "galicia", "penedès",
        // Argentina
        "mendoza", "salta", "patagonia", "uco valley",
        // USA
        "napa valley", "sonoma", "willamette", "paso robles"
    ]

    /// "Valle del Maipo", "Maipo Valley", "Maipo" all count as region-only text
    static func isRegionOnly(_ s: String) -> Bool {
        var t = s.lowercased().trimmingCharacters(in: .whitespaces)
        for prefix in ["valle del ", "valle de la ", "valle de ", "valle "] where t.hasPrefix(prefix) {
            t = String(t.dropFirst(prefix.count))
            break
        }
        if t.hasSuffix(" valley") { t = String(t.dropLast(" valley".count)) }
        return regionNames.contains(t) || regionNames.contains(s.lowercased())
    }

    // MARK: - Extraction

    static func extractWineNames(from texts: [String]) -> [String] {
        var wineNames: [String] = []
        var currentVariety: String? = nil
        // Wine's proper name from the previous line, for menus that put the
        // fantasy name alone above a "VARIETY. WINERY; PLACE, VALLEY" detail line
        var pendingHeader: String? = nil
        // Winery-section context: a bare winery line followed by its wines
        var sectionWinery: String? = nil
        var sectionWineryEntryIndex: Int? = nil

        // Menu section headers and non-wine items to exclude (Spanish/English)
        let excludedPatterns = [
            // Spanish menu terms
            "otros tintos", "otros blancos", "medias botellas", "por copa", "tintos por copa",
            "blancos por copa", "vinos tintos", "vinos blancos", "espumantes", "postres",
            "carta de vinos", "nuestra selección", "selección de", "media botella",
            "copas", "burbujas", "botellas", "reservas",
            // English menu terms
            "by the glass", "red wines", "white wines", "sparkling wines", "dessert wines",
            "wine list", "our selection", "half bottle", "bottle", "glass",
            // Common non-wine items
            "appetizers", "entradas", "principales", "main courses", "desserts",
            // Websites and URLs
            ".com", ".net", ".org", "www.", "http", "foodsherpas", "instagram", "facebook"
        ]

        // Price patterns (various currencies)
        let pricePatterns = [
            /^\$\s*\d+/,           // $50, $ 50
            /^\d+\s*\$/,           // 50$
            /^S\s*[\d,\.]+$/,      // S 28,500 (Chilean/Peruvian Sol)
            /^S\/\s*[\d,\.]+$/,    // S/ 28,500 (Sol with slash)
            /^\d+[\.,]\d{3}$/,     // 28,500 or 28.500
            /^[\d,\.]+\s*€/,       // European prices
            /^€\s*[\d,\.]+/,       // €50
            /^\d+\.\d{2}$/,        // 50.00
            /^E\s*[\d,\.]+$/,      // E 38,000 (generic currency)
            /^[A-Z]\s*[\d,\.]+$/   // Single letter + number pattern (currencies)
        ]

        for text in texts {
            var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

            // Strip leading bin numbers ("12. ", "7) ") — vintage years don't match
            if let binRange = trimmed.range(of: #"^\d{1,3}[\.\)]\s+"#, options: .regularExpression) {
                trimmed = String(trimmed[binRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            }

            // Strip trailing price info, repeatedly — menus often list bottle
            // AND glass prices ("$54.000  $13.000"), sometimes without the "$"
            while true {
                if let r = trimmed.range(of: #"\s*\|?\s*\$\s?[\d,\.]+\s*$"#, options: .regularExpression),
                   r.lowerBound != trimmed.startIndex {
                    trimmed = String(trimmed[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                } else if let r = trimmed.range(of: #"\s+\d{1,3}[\.,]\d{3}\s*$"#, options: .regularExpression) {
                    trimmed = String(trimmed[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                } else {
                    break
                }
            }

            // Skip very short or very long strings
            guard trimmed.count >= 4 && trimmed.count <= 100 else { continue }

            let lowercased = trimmed.lowercased()

            // Check if this is a grape variety section header — track it for context
            if sectionVarieties.contains(lowercased) {
                currentVariety = lowercased
                continue
            }

            // Skip excluded menu section headers (and end any winery section)
            if excludedPatterns.contains(where: { lowercased.contains($0) }) {
                sectionWinery = nil
                sectionWineryEntryIndex = nil
                continue
            }

            // Skip strings that look like prices (various formats)
            var isPrice = false
            for pattern in pricePatterns {
                if trimmed.matches(of: pattern).count > 0 {
                    isPrice = true
                    break
                }
            }
            if isPrice { continue }

            // Skip strings that are entirely a price (after stripping above, this catches standalone prices)
            if trimmed.contains("$") && trimmed.allSatisfy({ $0 == "$" || $0.isNumber || $0 == "," || $0 == "." || $0.isWhitespace }) {
                continue
            }

            // Skip strings that are just numbers/punctuation
            if trimmed.allSatisfy({ $0.isNumber || $0.isWhitespace || $0 == "," || $0 == "." }) {
                continue
            }

            // Skip very short words that are likely prices or codes
            let words = trimmed.components(separatedBy: .whitespaces)
            if words.count == 1 && trimmed.count < 6 && trimmed.first?.isNumber == true {
                continue
            }

            // Skip standalone region names
            if regionNames.contains(lowercased) {
                continue
            }

            // Detail lines in "VARIETY. WINERY; PLACE, VALLEY" menus: normalize
            // periods/semicolons to commas so comma-based matching applies, and
            // prepend the wine's proper name from the preceding header line
            let headSegment = trimmed.components(separatedBy: CharacterSet(charactersIn: ".;,"))
                .first?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
            let startsWithVariety = sectionVarieties.contains { headSegment == $0 || headSegment.hasSuffix(" \($0)") }
            if trimmed.contains(";") || (trimmed.contains(".") && startsWithVariety) {
                var normalized = trimmed
                    .replacingOccurrences(of: ";", with: ",")
                    .replacingOccurrences(of: ". ", with: ", ")
                while normalized.hasSuffix(".") { normalized.removeLast() }
                if let header = pendingHeader {
                    // The header was this wine's name, not its own entry — if it
                    // slipped in standalone (e.g. as a known winery), fold it in
                    if let last = wineNames.last,
                       (last.components(separatedBy: varietySeparator).first ?? last)
                           .caseInsensitiveCompare(header) == .orderedSame {
                        wineNames.removeLast()
                        if sectionWineryEntryIndex == wineNames.count { sectionWineryEntryIndex = nil }
                    }
                    if !normalized.lowercased().hasPrefix(header.lowercased()) {
                        normalized = header + ", " + normalized
                    }
                    if sectionWinery?.caseInsensitiveCompare(header) == .orderedSame {
                        sectionWinery = nil
                        sectionWineryEntryIndex = nil
                    }
                    pendingHeader = nil
                }
                trimmed = normalized
            }

            // Wine entry indicators (winery/estate terms, NOT grape varieties)
            let wineEntryKeywords = ["château", "chateau", "domaine", "estate", "vineyard", "winery",
                               "reserve", "reserva", "gran reserva", "grand cru", "premier cru",
                               "viña", "vina", "bodega", "finca", "clos", "casa", "quinta"]

            let hasWineEntryKeyword = wineEntryKeywords.contains { lowercased.contains($0) }
            let hasYear = trimmed.matches(of: /\b(19|20)\d{2}\b/).count > 0
            let hasComma = trimmed.contains(",")
            // Check if standalone text matches a known winery in the catalog
            // (keyword lines included — "Marques de Casa Concha" contains "casa")
            let isKnownWinery = !hasYear && !hasComma
                ? WineCatalog.shared.isKnownWinery(trimmed)
                : false

            if isKnownWinery {
                // Bare winery line: usually a section header with that winery's
                // wines below. Keep it as an entry, but track it as context and
                // drop the standalone entry once a following wine consumes it.
                if let variety = currentVariety {
                    wineNames.append(trimmed + varietySeparator + variety)
                } else {
                    wineNames.append(trimmed)
                }
                sectionWinery = trimmed
                sectionWineryEntryIndex = wineNames.count - 1
                // A menu's fantasy wine name can collide with some winery in the
                // 60K-winery catalog ("ARTESANO") — keep it as a pending header
                // too, so a following "VARIETY. WINERY; PLACE" line claims it as
                // a wine name instead of it leaking winery context downward
                pendingHeader = trimmed
                continue
            }

            // Lines starting with a known winery ("Catena Zapata Malbec Argentino")
            // become "Winery, Wine" so matching sees the winery boundary
            // Only when no winery section is active (context is more reliable),
            // and never on tiny prefixes ("Casa") that split wine names apart
            var lineWineryPrefix: String? = nil
            if !hasComma && sectionWinery == nil {
                let lineWords = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if lineWords.count >= 2 {
                    for k in stride(from: min(4, lineWords.count - 1), through: 1, by: -1) {
                        let prefix = lineWords.prefix(k).joined(separator: " ")
                        if prefix.count >= 5, WineCatalog.shared.isKnownWinery(prefix) {
                            lineWineryPrefix = prefix
                            trimmed = prefix + ", " + lineWords.dropFirst(k).joined(separator: " ")
                            break
                        }
                    }
                }
            }

            // Include if: has a winery/estate keyword, has a vintage year,
            // has a comma (common "Winery, Wine" format), or starts with a winery
            if hasWineEntryKeyword || hasYear || hasComma || lineWineryPrefix != nil {
                var entry = trimmed
                // Prepend the winery-section context when the line has no winery
                // of its own — "CATENA ZAPATA" above, "Malbec Argentino 2017" here
                if let winery = sectionWinery, lineWineryPrefix == nil,
                   !entry.lowercased().contains(winery.lowercased()) {
                    let ownWinery = entry.components(separatedBy: ",").contains {
                        let part = $0.trimmingCharacters(in: .whitespaces)
                        return !partVarieties.contains(part.lowercased())
                            && WineCatalog.shared.isKnownWinery(part)
                    }
                    if !ownWinery {
                        entry = winery + ", " + entry
                        if let idx = sectionWineryEntryIndex {
                            wineNames.remove(at: idx)
                            sectionWineryEntryIndex = nil
                        }
                    }
                }
                // Encode variety context if we have it (from section header)
                if let variety = currentVariety {
                    wineNames.append(entry + varietySeparator + variety)
                } else {
                    wineNames.append(entry)
                }
            }

            // Remember short name-like lines — menus often put the wine's proper
            // name alone on the line above its details
            let letterCount = trimmed.filter { $0.isLetter }.count
            pendingHeader = (words.count <= 4 && trimmed.count <= 32 && letterCount >= 3 && !trimmed.contains(","))
                ? trimmed : nil
        }

        // Label scan fallback: when OCR returns few lines and we extracted few/no
        // wine names, this is likely a wine label rather than a menu. Combine the
        // short text fragments into a single search query.
        if wineNames.count <= 1 && texts.count <= 25 {
            let descriptionWords: Set<String> = [
                "this", "and", "the", "with", "has", "its", "our", "wine", "wines",
                "is", "are", "from", "made", "produced", "aged", "bottle", "bottled",
                "smooth", "elegant", "balanced", "juicy", "tense", "unique", "intense"
            ]

            var labelParts: [String] = []
            var labelVariety: String? = nil

            for text in texts {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                let words = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

                // Keep only short fragments (1-4 words, 2-40 chars)
                guard trimmed.count >= 2 && trimmed.count <= 40 && words.count <= 4 else { continue }

                let lower = trimmed.lowercased()

                // Skip menu section headers and other excluded text
                if excludedPatterns.contains(where: { lower.contains($0) }) { continue }

                // Skip URLs, volumes, percentages, legal text
                if lower.contains(".com") || lower.contains("www.") || lower.contains("http") { continue }
                if trimmed.hasSuffix("%") { continue }
                if lower.hasSuffix(" cl") || lower.hasSuffix(" ml") || lower.hasSuffix(" lt") { continue }
                if lower.contains("sulfite") || lower.contains("alcohol") || lower.contains("contains") { continue }

                // Skip pure numbers/punctuation
                let letters = trimmed.filter { $0.isLetter }
                if letters.isEmpty { continue }

                // Skip descriptive phrases (2+ common description words)
                let fragWords = lower.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if fragWords.count > 1 {
                    let descCount = fragWords.filter { descriptionWords.contains($0) }.count
                    if descCount >= 2 { continue }
                }

                // Check if this is a grape variety — use as context, don't include in name
                let cleanLower = lower.filter { $0.isLetter || $0 == " " }
                    .trimmingCharacters(in: .whitespaces)
                if sectionVarieties.contains(cleanLower) {
                    labelVariety = cleanLower
                    continue
                }

                // Keep the cleaned fragment (alphanumeric + spaces only)
                let cleaned = trimmed.filter { $0.isLetter || $0.isNumber || $0 == " " }
                    .trimmingCharacters(in: .whitespaces)
                if !cleaned.isEmpty && cleaned.count >= 2 {
                    labelParts.append(cleaned)
                }
            }

            if !labelParts.isEmpty {
                let combined = labelParts.joined(separator: " ")
                let existingNames = Set(wineNames.map {
                    $0.components(separatedBy: varietySeparator).first?.lowercased() ?? ""
                })
                if !existingNames.contains(combined.lowercased()) {
                    if let variety = labelVariety {
                        wineNames.insert(combined + varietySeparator + variety, at: 0)
                    } else {
                        wineNames.insert(combined, at: 0)
                    }
                }
            }
        }

        // Remove duplicates while preserving order (compare by name part only)
        var seen = Set<String>()
        return wineNames.filter { entry in
            let name = entry.components(separatedBy: varietySeparator).first ?? entry
            let lowercased = name.lowercased()
            if seen.contains(lowercased) {
                return false
            }
            seen.insert(lowercased)
            return true
        }
    }

    // MARK: - Catalog matching

    private static func fold(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: .current).lowercased()
    }

    /// Search, preferring the candidate whose NAME the query words cover best.
    /// Plain rating order returns the winery's flagship ("Etiqueta Negra")
    /// instead of the bottling the menu actually names ("Cabernet Sauvignon").
    private static func bestMatch(query: String) -> CatalogWine? {
        let candidates = WineCatalog.shared.search(query: query, limit: 25)
        guard candidates.count > 1 else { return candidates.first }
        let queryWords = Set(fold(query).components(separatedBy: .whitespaces).filter { !$0.isEmpty })
        func coverage(_ w: CatalogWine) -> Double {
            let nameWords = fold(w.name).components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard !nameWords.isEmpty else { return 0 }
            return Double(nameWords.filter { queryWords.contains($0) }.count) / Double(nameWords.count)
        }
        return candidates.max { a, b in
            let ca = coverage(a), cb = coverage(b)
            if ca != cb { return ca < cb }
            return (a.rating ?? 0) < (b.rating ?? 0)
        }
    }

    static func findCatalogMatch(for rawName: String, variety: String? = nil) -> CatalogWine? {
        // Vintage years never match the searchable columns (vintage isn't
        // searched), so a year in the query guarantees a miss — drop them
        let name = rawName.replacingOccurrences(
            of: #"\b(19|20)\d{2}\b"#, with: " ", options: .regularExpression)
        let cleanedName = name.filter { $0.isLetter || $0.isNumber || $0 == " " }

        // Build search query — append variety from menu section header if available
        let searchQuery = variety != nil ? "\(cleanedName) \(variety!)" : cleanedName

        // Search the catalog with full detected name (+ variety context)
        if let catalogWine = bestMatch(query: searchQuery) {
            return catalogWine
        }

        // If comma-separated, handle two menu formats:
        // Format A: "Winery, Wine Name" (e.g., "Vik, A")
        // Format B: "Variety, Winery Details, Region" (e.g., "Pinot Noir, Montes Outer Limits, Zapallar")
        if name.contains(",") {
            let parts = name.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if parts.count >= 2 {
                let firstPartLower = parts[0].lowercased()
                let firstPartIsVariety = partVarieties.contains(firstPartLower)

                if firstPartIsVariety {
                    // Variety+region-only lines ("Malbec, Mendoza") carry no wine
                    // identity — searching would return an arbitrary top-rated hit
                    if parts.dropFirst().allSatisfy({ isRegionOnly($0) }) {
                        return nil
                    }

                    // Format B: "Variety, Winery/Wine, Region"
                    // Winery detail + variety first — region words in the query
                    // often LIKE-match unrelated wineries ("del" → "Casas del …")
                    let wineryOnly = "\(parts[1]) \(parts[0])"
                    if let catalogWine = bestMatch(query: wineryOnly) {
                        return catalogWine
                    }

                    // Then the full remainder including region
                    let wineryAndRegion = Array(parts[1...]).joined(separator: " ")
                    let queryWithVariety = "\(wineryAndRegion) \(parts[0])"
                    if let catalogWine = bestMatch(query: queryWithVariety) {
                        return catalogWine
                    }
                } else {
                    // Format A: "Winery, Wine Name"
                    let reordered = (Array(parts[1...]) + [parts[0]]).joined(separator: " ")
                    let reorderedQuery = variety != nil ? "\(reordered) \(variety!)" : reordered
                    if let catalogWine = bestMatch(query: reorderedQuery) {
                        return catalogWine
                    }

                    // Menu-header format: "Name, Variety, Winery, Place" — a later
                    // part naming the grape gives the most precise query (e.g.
                    // "SOLDESOL, CHARDONNAY, VIÑA AQUITANIA, ..." → "SOLDESOL chardonnay")
                    let sortedVarieties = partVarieties.sorted { $0.count > $1.count }
                    let entryVariety = parts.dropFirst().compactMap { part -> String? in
                        // Menus write blends as "Cabernet Franc/ Malbec" — treat
                        // slashes as spaces so the grape is still recognized
                        let lower = " " + part.lowercased()
                            .replacingOccurrences(of: "/", with: " ")
                            .replacingOccurrences(of: "  ", with: " ") + " "
                        return sortedVarieties.first { lower.contains(" \($0) ") }
                    }.first
                    if let entryVariety {
                        if let catalogWine = bestMatch(query: "\(parts[0]) \(entryVariety)") {
                            return catalogWine
                        }
                    }

                    // Bare first-part fallback ONLY for true "Winery, Wine" pairs.
                    // Header-derived entries (3+ parts) skip it: a fantasy name
                    // alone matches unrelated wines and wineries ("ARTESANO" →
                    // Cavas del Artesano), and the precise queries above already
                    // cover anything actually in the catalog
                    if parts.count == 2 {
                        let wineryQuery = variety != nil ? "\(parts[0]) \(variety!)" : parts[0]
                        if let catalogWine = bestMatch(query: wineryQuery) {
                            // A bare-name hit must agree on the grape when known
                            let matchVariety = catalogWine.variety?.lowercased() ?? ""
                            if entryVariety == nil || matchVariety.contains(entryVariety!) || entryVariety!.contains(matchVariety) {
                                return catalogWine
                            }
                        }
                    }
                }
            }
        }

        return nil
    }
}
