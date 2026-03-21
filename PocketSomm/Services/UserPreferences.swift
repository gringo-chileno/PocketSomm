import Foundation

struct UserPreferences {
    var varietyScores: [String: Double] = [:]
    var regionScores: [String: Double] = [:]
    var countryScores: [String: Double] = [:]
    var wineryScores: [String: Double] = [:]
    var ratingCount: Int = 0

    // Track wine color preferences
    var redWineCount: Int = 0
    var whiteWineCount: Int = 0
    var redWineAvgRating: Double = 0.0
    var whiteWineAvgRating: Double = 0.0

    // Wine similarity groups - varieties that share similar characteristics
    static let similarityGroups: [[String]] = [
        // Full-bodied reds
        ["carmenere", "malbec", "syrah", "shiraz", "cabernet sauvignon", "cabernet franc", "petit verdot", "tannat", "mourvedre", "petite sirah"],
        // Medium-bodied reds
        ["merlot", "tempranillo", "sangiovese", "grenache", "zinfandel", "primitivo", "barbera", "dolcetto"],
        // Light-bodied reds
        ["pinot noir", "gamay", "nebbiolo", "zweigelt"],
        // Full-bodied whites
        ["chardonnay", "viognier", "roussanne", "marsanne", "semillon"],
        // Light/crisp whites
        ["sauvignon blanc", "pinot grigio", "pinot gris", "albarino", "vermentino", "gruner veltliner", "muscadet"],
        // Aromatic whites
        ["riesling", "gewurztraminer", "torrontes", "muscat", "moscato"],
        // Rosé styles
        ["rose", "rosé", "rosado"]
    ]

    /// Returns varieties similar to the given variety (0.0-1.0 similarity score)
    static func similarityScore(from ratedVariety: String, to targetVariety: String) -> Double {
        let rated = ratedVariety.lowercased()
        let target = targetVariety.lowercased()

        // Exact match
        if rated == target { return 1.0 }

        // Check if in same similarity group
        for group in similarityGroups {
            let ratedInGroup = group.contains { rated.contains($0) || $0.contains(rated) }
            let targetInGroup = group.contains { target.contains($0) || $0.contains(target) }

            if ratedInGroup && targetInGroup {
                return 0.6 // Same style family gets 60% of the score
            }
        }

        // Check if both are reds or both are whites (weaker similarity)
        let redVarieties = similarityGroups[0] + similarityGroups[1] + similarityGroups[2]
        let whiteVarieties = similarityGroups[3] + similarityGroups[4] + similarityGroups[5]

        let ratedIsRed = redVarieties.contains { rated.contains($0) || $0.contains(rated) }
        let targetIsRed = redVarieties.contains { target.contains($0) || $0.contains(target) }
        let ratedIsWhite = whiteVarieties.contains { rated.contains($0) || $0.contains(rated) }
        let targetIsWhite = whiteVarieties.contains { target.contains($0) || $0.contains(target) }

        if (ratedIsRed && targetIsRed) || (ratedIsWhite && targetIsWhite) {
            return 0.3 // Same color wine gets 30% of the score
        }

        return 0.0 // Different types (red vs white) get no similarity boost
    }

    /// Check if a wine is red (using wineType if available, otherwise variety)
    static func isRedWine(_ variety: String?, wineType: String? = nil) -> Bool {
        if let type = wineType?.lowercased() {
            return type == "red"
        }
        guard let variety = variety else { return false }
        let redVarieties = similarityGroups[0] + similarityGroups[1] + similarityGroups[2]
        let lowercased = variety.lowercased()
        return redVarieties.contains { lowercased.contains($0) || $0.contains(lowercased) }
    }

    /// Check if a wine is white (using wineType if available, otherwise variety)
    static func isWhiteWine(_ variety: String?, wineType: String? = nil) -> Bool {
        if let type = wineType?.lowercased() {
            return type == "white"
        }
        guard let variety = variety else { return false }
        let whiteVarieties = similarityGroups[3] + similarityGroups[4] + similarityGroups[5]
        let lowercased = variety.lowercased()
        return whiteVarieties.contains { lowercased.contains($0) || $0.contains(lowercased) }
    }

    static func calculate(from ratings: [UserRating]) -> UserPreferences {
        var preferences = UserPreferences()
        preferences.ratingCount = ratings.count

        // Group ratings by variety, region, country, winery
        var varietyRatings: [String: [Double]] = [:]
        var regionRatings: [String: [Double]] = [:]
        var countryRatings: [String: [Double]] = [:]
        var wineryRatings: [String: [Double]] = [:]

        // Track red vs white ratings
        var redRatings: [Double] = []
        var whiteRatings: [Double] = []

        for rating in ratings {
            guard let wine = rating.wine else { continue }

            if let variety = wine.grapeVariety?.lowercased() {
                varietyRatings[variety, default: []].append(rating.rating)
            }

            // Track color preferences (using wineType if available)
            if isRedWine(wine.grapeVariety, wineType: wine.wineType) {
                redRatings.append(rating.rating)
            } else if isWhiteWine(wine.grapeVariety, wineType: wine.wineType) {
                whiteRatings.append(rating.rating)
            }

            if let region = wine.region?.lowercased() {
                regionRatings[region, default: []].append(rating.rating)
            }

            if let country = wine.country?.lowercased() {
                countryRatings[country, default: []].append(rating.rating)
            }

            if let winery = wine.winery?.lowercased() {
                wineryRatings[winery, default: []].append(rating.rating)
            }
        }

        // Calculate average scores
        for (variety, ratings) in varietyRatings {
            preferences.varietyScores[variety] = ratings.reduce(0, +) / Double(ratings.count)
        }

        for (region, ratings) in regionRatings {
            preferences.regionScores[region] = ratings.reduce(0, +) / Double(ratings.count)
        }

        for (country, ratings) in countryRatings {
            preferences.countryScores[country] = ratings.reduce(0, +) / Double(ratings.count)
        }

        for (winery, ratings) in wineryRatings {
            preferences.wineryScores[winery] = ratings.reduce(0, +) / Double(ratings.count)
        }

        // Calculate color preferences
        preferences.redWineCount = redRatings.count
        preferences.whiteWineCount = whiteRatings.count
        if !redRatings.isEmpty {
            preferences.redWineAvgRating = redRatings.reduce(0, +) / Double(redRatings.count)
        }
        if !whiteRatings.isEmpty {
            preferences.whiteWineAvgRating = whiteRatings.reduce(0, +) / Double(whiteRatings.count)
        }

        return preferences
    }

    /// Predicts a score for a wine, blending personal preferences with community ratings.
    /// Each rating adds 5% personal weight, capping at 80% (always 20% community influence)
    /// - 1 rating: 5% personal, 95% community
    /// - 10 ratings: 50% personal, 50% community
    /// - 16+ ratings: 80% personal, 20% community (cap)
    func predictScore(for wine: Wine) -> Double? {
        // Calculate personal preference score
        var personalScores: [Double] = []
        var personalWeights: [Double] = []

        // Variety is most predictive (weight 3)
        // First try exact match, then try similar varieties
        if let targetVariety = wine.grapeVariety?.lowercased() {
            if let score = varietyScores[targetVariety] {
                // Exact match
                personalScores.append(score)
                personalWeights.append(3.0)
            } else {
                // Look for similar varieties
                var bestSimilarScore: Double? = nil
                var bestSimilarity: Double = 0.0

                for (ratedVariety, score) in varietyScores {
                    let similarity = UserPreferences.similarityScore(from: ratedVariety, to: targetVariety)
                    if similarity > bestSimilarity {
                        bestSimilarity = similarity
                        bestSimilarScore = score
                    }
                }

                if let similarScore = bestSimilarScore, bestSimilarity > 0 {
                    // Apply similarity-adjusted score with reduced weight
                    personalScores.append(similarScore)
                    personalWeights.append(3.0 * bestSimilarity)
                }
            }
        }

        // Winery preference (weight 2.5) - if they like wines from this winery
        if let winery = wine.winery?.lowercased(),
           let score = wineryScores[winery] {
            personalScores.append(score)
            personalWeights.append(2.5)
        }

        // Region is moderately predictive (weight 2)
        if let region = wine.region?.lowercased(),
           let score = regionScores[region] {
            personalScores.append(score)
            personalWeights.append(2.0)
        }

        // Country is least predictive (weight 1)
        if let country = wine.country?.lowercased(),
           let score = countryScores[country] {
            personalScores.append(score)
            personalWeights.append(1.0)
        }

        // Calculate weighted personal score
        var personalScore: Double? = nil
        if !personalScores.isEmpty {
            var weightedSum = 0.0
            var totalWeight = 0.0
            for i in 0..<personalScores.count {
                weightedSum += personalScores[i] * personalWeights[i]
                totalWeight += personalWeights[i]
            }
            personalScore = weightedSum / totalWeight
        }

        // Apply color preference penalty
        // If user strongly prefers one color, penalize the other
        let totalColorRatings = redWineCount + whiteWineCount
        if totalColorRatings >= 3 {
            let targetIsRed = UserPreferences.isRedWine(wine.grapeVariety, wineType: wine.wineType)
            let targetIsWhite = UserPreferences.isWhiteWine(wine.grapeVariety, wineType: wine.wineType)

            if targetIsRed || targetIsWhite {

                // Calculate color preference ratio (0-1, where 1 = only rates that color)
                let redRatio = Double(redWineCount) / Double(totalColorRatings)
                let whiteRatio = Double(whiteWineCount) / Double(totalColorRatings)

                // If someone rates 80%+ of one color and the target is the other color, apply penalty
                // Penalty scales: 80% = -0.1, 90% = -0.3, 100% = -0.5
                if targetIsWhite && redRatio >= 0.7 {
                    let penalty = min(0.5, (redRatio - 0.7) * 1.67) // 0 at 70%, 0.5 at 100%
                    if var score = personalScore {
                        score = max(1.0, score - penalty)
                        personalScore = score
                    } else {
                        // If no personal score yet, start from community and apply penalty
                        if let community = wine.averageRating {
                            personalScore = max(1.0, community - penalty)
                        }
                    }
                } else if targetIsRed && whiteRatio >= 0.7 {
                    let penalty = min(0.5, (whiteRatio - 0.7) * 1.67)
                    if var score = personalScore {
                        score = max(1.0, score - penalty)
                        personalScore = score
                    } else {
                        if let community = wine.averageRating {
                            personalScore = max(1.0, community - penalty)
                        }
                    }
                }
            }
        }

        // Get community rating
        let communityScore = wine.averageRating

        // Calculate personal weight based on rating count
        // Each rating adds 5%, caps at 80% (always keeps 20% community influence)
        let personalWeight = min(0.8, Double(ratingCount) * 0.05)

        let communityWeight = 1.0 - personalWeight

        // Calculate blended score
        if let personal = personalScore, let community = communityScore {
            return personal * personalWeight + community * communityWeight
        } else if let personal = personalScore {
            return personal
        } else if let community = communityScore {
            return community
        }

        return nil
    }

    var topVarieties: [(name: String, score: Double)] {
        varietyScores
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { (name: $0.key.capitalized, score: $0.value) }
    }

    var topRegions: [(name: String, score: Double)] {
        regionScores
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { (name: $0.key.capitalized, score: $0.value) }
    }

    var topCountries: [(name: String, score: Double)] {
        countryScores
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { (name: $0.key.capitalized, score: $0.value) }
    }
}
