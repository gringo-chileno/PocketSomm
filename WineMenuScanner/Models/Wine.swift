import Foundation
import SwiftData

@Model
final class Wine {
    var name: String
    var vintage: Int?
    var region: String?
    var grapeVariety: String?
    var averageRating: Double?
    var winery: String?
    var country: String?
    var priceUSD: Double?
    var wineType: String?  // Red, White, Rosé, Sparkling, Dessert
    var body: String?  // Light-bodied, Medium-bodied, Full-bodied
    var acidity: String?  // Low, Medium, High
    var foodPairings: String?  // JSON array of food pairings

    // Inverse relationship
    @Relationship(deleteRule: .cascade, inverse: \UserRating.wine)
    var userRatings: [UserRating]?

    init(
        name: String,
        vintage: Int? = nil,
        region: String? = nil,
        grapeVariety: String? = nil,
        averageRating: Double? = nil,
        winery: String? = nil,
        country: String? = nil,
        priceUSD: Double? = nil,
        wineType: String? = nil,
        body: String? = nil,
        acidity: String? = nil,
        foodPairings: String? = nil
    ) {
        self.name = name
        self.vintage = vintage
        self.region = region
        self.grapeVariety = grapeVariety
        self.averageRating = averageRating
        self.winery = winery
        self.country = country
        self.priceUSD = priceUSD
        self.wineType = wineType
        self.body = body
        self.acidity = acidity
        self.foodPairings = foodPairings
    }

    var displayName: String {
        if let vintage = vintage {
            return "\(name) (\(vintage))"
        }
        return name
    }

    var userRating: UserRating? {
        userRatings?.sorted { $0.dateRated > $1.dateRated }.first
    }
}
