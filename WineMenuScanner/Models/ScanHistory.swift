import Foundation
import SwiftData

@Model
final class ScanHistory {
    var date: Date
    var photoData: Data?
    var detectedWineNames: [String]

    @Relationship
    var matchedWines: [Wine]?

    init(
        date: Date = Date(),
        photoData: Data? = nil,
        detectedWineNames: [String] = [],
        matchedWines: [Wine]? = nil
    ) {
        self.date = date
        self.photoData = photoData
        self.detectedWineNames = detectedWineNames
        self.matchedWines = matchedWines
    }
}
