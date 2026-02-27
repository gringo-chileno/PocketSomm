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
        .tint(.white)
        .onAppear {
            UITabBar.appearance().tintColor = UIColor(red: 0.45, green: 0.12, blue: 0.16, alpha: 1.0)
        }
        .preferredColorScheme(settings.colorScheme.colorScheme)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Wine.self, UserRating.self, ScanHistory.self], inMemory: true)
}
