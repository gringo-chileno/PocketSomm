import Foundation

// Offline regression harness for the menu-scan pipeline.
// Build & run (from repo root):
//   WINE_CATALOG_PATH=PocketSomm/Resources/wines_catalog.sqlite \
//   swiftc -enable-bare-slash-regex -o /tmp/scan_harness \
//     PocketSomm/Services/WineCatalog.swift \
//     PocketSomm/Services/MenuScanEngine.swift \
//     scripts/harness/main.swift && WINE_CATALOG_PATH=... /tmp/scan_harness
// Each case lists OCR-like lines plus wines that ARE in the catalog, so a
// miss is a pipeline gap, never missing data.

struct Expectation {
    let label: String
    let winery: String   // catalog winery must contain this (case-insensitive)
    let name: String     // catalog name must contain this (case-insensitive)
}

struct MenuCase {
    let title: String
    let lines: [String]
    let expected: [Expectation]
    var expectNoFalseMatches: Bool = false
}

let cases: [MenuCase] = [
    MenuCase(
        title: "Format A: Winery, Wine + inline price",
        lines: [
            "VINOS TINTOS",
            "Catena Zapata, Malbec Argentino $54.000",
            "Lapostolle, Cuvée Alexandre Carmenère $32.000",
            "Emiliana, Coyam $28.000",
        ],
        expected: [
            Expectation(label: "Malbec Argentino", winery: "Catena Zapata", name: "Malbec Argentino"),
            Expectation(label: "Cuvée Alexandre", winery: "Lapostolle", name: "Cuvée Alexandre Carmenère"),
            Expectation(label: "Coyam", winery: "Emiliana", name: "Coyam"),
        ]),
    MenuCase(
        title: "Format B: Variety, Winery, Region",
        lines: [
            "Malbec, Catena Zapata Nicasia Vineyard, Mendoza",
            "Carmenère, Lapostolle Cuvée Alexandre, Apalta",
            "Cabernet Sauvignon, Santa Rita Casa Real, Maipo",
        ],
        expected: [
            Expectation(label: "Nicasia", winery: "Catena Zapata", name: "Nicasia"),
            Expectation(label: "Cuvée Alexandre", winery: "Lapostolle", name: "Cuvée Alexandre"),
            Expectation(label: "Casa Real", winery: "Santa Rita", name: "Casa Real"),
        ]),
    MenuCase(
        title: "Header + VARIETY. WINERY; PLACE (tonight's menu)",
        lines: [
            "CARTA DE VINOS",
            "SOLDESOL",
            "CHARDONNAY. VIÑA AQUITANIA; TRAIGUEN VALLE DEL MALLECO.",
            "$39.000", "$9.500",
            "ARTESANO",
            "CARMENERE. VIÑA LA PUENTE ALTA; QUINTA DE TILCOCO, VALLE DEL CACHAPOAL.",
            "$39.000", "$8.500",
        ],
        expected: [
            Expectation(label: "SOLdeSOL", winery: "Aquitania", name: "SOLdeSOL Chardonnay"),
        ],
        expectNoFalseMatches: true),
    MenuCase(
        title: "Winery section header + wine lines with vintage",
        lines: [
            "CATENA ZAPATA",
            "Malbec Argentino 2017   $54.000",
            "Nicasia Vineyard Malbec 2018   $40.000",
            "SANTA RITA",
            "Casa Real Cabernet Sauvignon 2019   $45.000",
        ],
        expected: [
            Expectation(label: "Malbec Argentino", winery: "Catena Zapata", name: "Malbec Argentino"),
            Expectation(label: "Nicasia", winery: "Catena Zapata", name: "Nicasia"),
            Expectation(label: "Casa Real", winery: "Santa Rita", name: "Casa Real"),
        ]),
    MenuCase(
        title: "Two-line wrap: winery line, then variety+region line",
        lines: [
            "Marques de Casa Concha",
            "Cabernet Sauvignon, Valle del Maipo   $25.000",
            "Luigi Bosca",
            "Malbec, Mendoza   $22.000",
        ],
        expected: [
            Expectation(label: "MCC Cab", winery: "Marques de Casa Concha", name: "Cabernet Sauvignon"),
            Expectation(label: "Luigi Bosca Malbec", winery: "Luigi Bosca", name: "Malbec"),
        ]),
    MenuCase(
        title: "Bin numbers + bottle/glass double price",
        lines: [
            "12. Catena Zapata Malbec Argentino   $54.000   $13.000",
            "14. Emiliana Coyam   $28.000   $7.500",
        ],
        expected: [
            Expectation(label: "Malbec Argentino", winery: "Catena Zapata", name: "Malbec Argentino"),
            Expectation(label: "Coyam", winery: "Emiliana", name: "Coyam"),
        ]),
    MenuCase(
        title: "Noise only: prices and section headers (expect nothing)",
        lines: [
            "VINOS POR COPA", "$9.500", "$8.000", "39.000", "MEDIAS BOTELLAS",
            "www.restaurant.cl", "Follow us on instagram",
        ],
        expected: [],
        expectNoFalseMatches: true),
]

var totalExpected = 0, totalMatched = 0, totalFalse = 0

for c in cases {
    print("\n=== \(c.title)")
    let entries = MenuScanEngine.extractWineNames(from: c.lines)
    print("  extracted \(entries.count): \(entries.map { $0.replacingOccurrences(of: "\t", with: " ⟨v:") + ($0.contains("\t") ? "⟩" : "") })")

    var matches: [(entry: String, wine: CatalogWine)] = []
    for entry in entries {
        let parts = entry.components(separatedBy: MenuScanEngine.varietySeparator)
        let name = parts[0]
        let variety = parts.count > 1 ? parts[1] : nil
        if let m = MenuScanEngine.findCatalogMatch(for: name, variety: variety) {
            matches.append((name, m))
            print("  MATCH \"\(name.prefix(40))\" -> \(m.winery ?? "?") | \(m.name)")
        } else {
            print("  none  \"\(name.prefix(40))\"")
        }
    }

    for exp in c.expected {
        totalExpected += 1
        let hit = matches.contains { (_, w) in
            (w.winery ?? "").localizedCaseInsensitiveContains(exp.winery) &&
            w.name.localizedCaseInsensitiveContains(exp.name)
        }
        if hit { totalMatched += 1 }
        print("  [\(hit ? "PASS" : "FAIL")] expected \(exp.label)")
    }

    // False match = a catalog hit whose winery matches no expectation
    for (entry, w) in matches {
        let legit = c.expected.contains { (w.winery ?? "").localizedCaseInsensitiveContains($0.winery) }
        if !legit {
            totalFalse += 1
            print("  [FALSE] \"\(entry.prefix(30))\" -> \(w.winery ?? "?") | \(w.name)")
        }
    }
}

print("\n================================")
print("expected wines matched: \(totalMatched)/\(totalExpected)   false matches: \(totalFalse)")
