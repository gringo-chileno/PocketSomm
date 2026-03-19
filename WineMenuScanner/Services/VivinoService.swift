import Foundation

/// Lightweight result from Vivino search
struct VivinoWine {
    let name: String
    let winery: String
    let rating: Double
    let ratingsCount: Int
    let region: String?
    let country: String?
    let variety: String?
    let imageURL: String?
    let vivinoURL: String?
}

/// Fetches wine data from Vivino's search page (embedded JSON in preloaded state)
class VivinoService {
    static let shared = VivinoService()
    private init() {}

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9"
        ]
        return URLSession(configuration: config)
    }()

    /// Search Vivino for wines matching query. Returns top matches.
    func search(query: String, limit: Int = 5) async -> [VivinoWine] {
        guard !query.isEmpty else { return [] }

        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://www.vivino.com/search/wines?q=\(encoded)") else {
            return []
        }

        do {
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else {
                return []
            }

            return parseSearchResults(from: html, limit: limit)
        } catch {
            print("Vivino search error: \(error.localizedDescription)")
            return []
        }
    }

    /// Parse wine data from the data-preloaded-state JSON embedded in the HTML
    private func parseSearchResults(from html: String, limit: Int) -> [VivinoWine] {
        // Find all data-preloaded-state="..." attributes and look for the one with search_results
        let marker = "data-preloaded-state=\""
        var searchRange = html.startIndex..<html.endIndex
        var matches: [[String: Any]]?

        while let startMarker = html.range(of: marker, range: searchRange) {
            let jsonStart = startMarker.upperBound
            guard let endQuote = html[jsonStart...].range(of: "\"") else { break }

            let encodedJSON = String(html[jsonStart..<endQuote.lowerBound])
            let decodedJSON = encodedJSON
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&#39;", with: "'")

            if let jsonData = decodedJSON.data(using: .utf8),
               let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let searchResults = root["search_results"] as? [String: Any],
               let foundMatches = searchResults["matches"] as? [[String: Any]] {
                matches = foundMatches
                break
            }

            searchRange = endQuote.upperBound..<html.endIndex
        }

        guard let matches = matches else { return [] }

        var results: [VivinoWine] = []

        for match in matches.prefix(limit) {
            guard let vintage = match["vintage"] as? [String: Any],
                  let wine = vintage["wine"] as? [String: Any],
                  let stats = vintage["statistics"] as? [String: Any],
                  let wineName = wine["name"] as? String else {
                continue
            }

            let winery = (wine["winery"] as? [String: Any])?["name"] as? String ?? ""
            let rating = stats["ratings_average"] as? Double ?? 0
            let ratingsCount = stats["ratings_count"] as? Int ?? 0

            // Skip results with no ratings
            guard rating > 0 && ratingsCount > 0 else { continue }

            let region = (wine["region"] as? [String: Any])?["name"] as? String
            let country = ((wine["region"] as? [String: Any])?["country"] as? [String: Any])?["name"] as? String
            let variety = (wine["style"] as? [String: Any])?["varietal_name"] as? String

            // Build image URL
            let imageURL: String?
            if let image = vintage["image"] as? [String: Any],
               let location = image["location"] as? String {
                imageURL = location.hasPrefix("//") ? "https:" + location : location
            } else {
                imageURL = nil
            }

            // Build Vivino URL from seo_name
            let vivinoURL: String?
            if let seoName = vintage["seo_name"] as? String {
                vivinoURL = "https://www.vivino.com/w/\(seoName)"
            } else {
                vivinoURL = nil
            }

            results.append(VivinoWine(
                name: wineName,
                winery: winery,
                rating: rating,
                ratingsCount: ratingsCount,
                region: region,
                country: country,
                variety: variety,
                imageURL: imageURL,
                vivinoURL: vivinoURL
            ))
        }

        return results
    }
}
