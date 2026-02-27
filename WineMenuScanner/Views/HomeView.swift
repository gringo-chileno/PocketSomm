import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScanHistory.date, order: .reverse) private var recentScans: [ScanHistory]
    @Query(sort: \UserRating.dateRated, order: .reverse) private var recentRatings: [UserRating]

    @State private var showingScanner = false
    @State private var showingSearch = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Search Button (primary action)
                    Button(action: { showingSearch = true }) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .font(.nyTitle2)
                            Text("Search Wines")
                                .font(.nyHeadline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(
                            LinearGradient(
                                colors: [.wineRed, .wineRedLight],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(16)
                    }
                    .padding(.horizontal)

                    // Scan Button (secondary action)
                    Button(action: { showingScanner = true }) {
                        HStack {
                            Image(systemName: "camera.fill")
                            Text("Scan Wine Menu")
                                .font(.nySubheadline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.black)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .padding(.horizontal)

                    // Your Stats
                    if !recentRatings.isEmpty {
                        YourStatsCard(ratings: recentRatings)
                            .padding(.horizontal)
                    }

                    // Recent Ratings Section
                    if !recentRatings.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recent Ratings")
                                .font(.nyHeadline)
                                .padding(.horizontal)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(recentRatings.prefix(5)) { rating in
                                        if let wine = rating.wine {
                                            NavigationLink(destination: WineDetailView(wine: wine)) {
                                                RecentRatingCard(rating: rating, wine: wine)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }

                    // Recent Scans Section
                    if !recentScans.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recent Scans")
                                .font(.nyHeadline)
                                .padding(.horizontal)

                            ForEach(recentScans.prefix(3)) { scan in
                                NavigationLink(destination: ScanResultsView(scan: scan)) {
                                    RecentScanCard(scan: scan)
                                }
                                .padding(.horizontal)
                            }
                        }
                    }

                    // Empty State
                    if recentScans.isEmpty && recentRatings.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "wineglass")
                                .font(.system(size: 60))
                                .foregroundColor(.wineRed.opacity(0.5))

                            Text("I am Pocket Somm.")
                                .font(.nyTitle2)
                                .fontWeight(.semibold)

                            Text("Scan a wine menu or search for wines to get started.")
                                .font(.nyBody)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 40)
                        .padding(.horizontal, 32)
                    }

                    Spacer(minLength: 50)
                }
                .padding(.top)
            }
            .navigationTitle("Pocket Somm")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape")
                            .foregroundColor(.wineRed)
                    }
                }
            }
            .sheet(isPresented: $showingScanner) {
                ScannerView()
            }
            .sheet(isPresented: $showingSearch) {
                WineSearchView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }
}

struct RecentRatingCard: View {
    let rating: UserRating
    let wine: Wine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(wine.name)
                .font(.nySubheadline)
                .fontWeight(.medium)
                .lineLimit(2)
                .foregroundColor(.primary)

            if let winery = wine.winery {
                Text(winery)
                    .font(.nyCaption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 2) {
                ForEach(0..<5) { index in
                    Image(systemName: index < Int(rating.rating) ? "star.fill" : "star")
                        .font(.system(size: 10))
                        .foregroundColor(.wineRed)
                }
                Text(String(format: "%.1f", rating.rating))
                    .font(.nyCaption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
        }
        .padding()
        .frame(width: 160, height: 100, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct RecentScanCard: View {
    let scan: ScanHistory

    var body: some View {
        HStack {
            if let photoData = scan.photoData,
               let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.tertiarySystemBackground))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "doc.text")
                            .foregroundColor(.gray)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(scan.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.nySubheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                Text("\(scan.detectedWineNames.count) wines detected")
                    .font(.nyCaption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct YourStatsCard: View {
    let ratings: [UserRating]

    private var averageRating: Double {
        guard !ratings.isEmpty else { return 0 }
        return ratings.reduce(0) { $0 + $1.rating } / Double(ratings.count)
    }

    private var topVariety: String? {
        let varieties = ratings.compactMap { $0.wine?.grapeVariety }
        return mostFrequent(in: varieties)
    }

    private var topCountry: String? {
        let countries = ratings.compactMap { $0.wine?.country }
        return mostFrequent(in: countries)
    }

    private var topRegion: String? {
        let regions = ratings.compactMap { $0.wine?.region }
        return mostFrequent(in: regions)
    }

    private func mostFrequent(in array: [String]) -> String? {
        let counts = array.reduce(into: [:]) { $0[$1, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Stats")
                .font(.nyHeadline)

            // Centered stats row
            HStack {
                Spacer()
                StatItem(value: "\(ratings.count)", label: "Rated")
                Spacer()
                StatItem(value: String(format: "%.1f", averageRating), label: "Avg")
                Spacer()
            }

            if topVariety != nil || topCountry != nil || topRegion != nil {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    if let variety = topVariety {
                        StatRow(icon: "leaf.fill", label: "Top Grape", value: variety)
                    }
                    if let country = topCountry {
                        StatRow(icon: "flag.fill", label: "Top Country", value: country)
                    }
                    if let region = topRegion {
                        StatRow(icon: "mappin.circle.fill", label: "Top Region", value: region)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct StatItem: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.nyTitle2)
                .fontWeight(.bold)
                .foregroundColor(.wineRed)
            Text(label)
                .font(.nyCaption)
                .foregroundColor(.secondary)
        }
    }
}

struct StatRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.wineRed)
                .frame(width: 20)
            Text(label)
                .font(.nyCaption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.nySubheadline)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [Wine.self, UserRating.self, ScanHistory.self], inMemory: true)
}
