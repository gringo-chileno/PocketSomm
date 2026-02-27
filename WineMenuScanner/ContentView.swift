import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedTab = 0
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

            MyRatingsView()
                .tabItem {
                    Label("My Ratings", systemImage: "star.fill")
                }
                .tag(1)

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }
                .tag(2)
        }
        .tint(.wineRed)
        .preferredColorScheme(settings.colorScheme.colorScheme)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Wine.self, UserRating.self, ScanHistory.self], inMemory: true)
}
