import Foundation
import SwiftData

@Model
final class UserRating {
    var wine: Wine?
    var rating: Double
    var dateRated: Date
    var notes: String?
    var vintage: Int?

    init(
        wine: Wine? = nil,
        rating: Double,
        dateRated: Date = Date(),
        notes: String? = nil,
        vintage: Int? = nil
    ) {
        self.wine = wine
        self.rating = rating
        self.dateRated = dateRated
        self.notes = notes
        self.vintage = vintage
    }
}
