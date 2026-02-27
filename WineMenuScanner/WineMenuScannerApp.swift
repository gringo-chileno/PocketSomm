import SwiftUI
import SwiftData

@main
struct WineMenuScannerApp: App {
    let sharedModelContainer: ModelContainer

    init() {
        let schema = Schema([
            Wine.self,
            UserRating.self,
            ScanHistory.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            sharedModelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }

        // Configure New York font for navigation bars
        let nyFont = UIFont(descriptor: UIFontDescriptor.preferredFontDescriptor(withTextStyle: .largeTitle).withDesign(.serif)!, size: 34)
        let nyInlineFont = UIFont(descriptor: UIFontDescriptor.preferredFontDescriptor(withTextStyle: .headline).withDesign(.serif)!, size: 17)

        UINavigationBar.appearance().largeTitleTextAttributes = [.font: nyFont]
        UINavigationBar.appearance().titleTextAttributes = [.font: nyInlineFont]

        // Configure New York font for tab bar
        let nyTabFont = UIFont(descriptor: UIFontDescriptor.preferredFontDescriptor(withTextStyle: .caption2).withDesign(.serif)!, size: 10)
        UITabBarItem.appearance().setTitleTextAttributes([.font: nyTabFont], for: .normal)
        UITabBarItem.appearance().setTitleTextAttributes([.font: nyTabFont], for: .selected)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
