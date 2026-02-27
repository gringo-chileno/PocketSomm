import SwiftUI

enum AppColorScheme: String, CaseIterable, Identifiable {
    case system = "System"
    case dark = "Dark"
    case light = "Light"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }

    var description: String {
        switch self {
        case .system: return "Follow device settings"
        case .dark: return "Always dark mode"
        case .light: return "Always light mode"
        }
    }
}

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("appColorScheme") var colorScheme: AppColorScheme = .dark

    private init() {}
}

// MARK: - New York Font Styles
extension Font {
    static let nyTitle = Font.system(.title, design: .serif)
    static let nyTitle2 = Font.system(.title2, design: .serif)
    static let nyTitle3 = Font.system(.title3, design: .serif)
    static let nyHeadline = Font.system(.headline, design: .serif)
    static let nySubheadline = Font.system(.subheadline, design: .serif)
    static let nyBody = Font.system(.body, design: .serif)
    static let nyCaption = Font.system(.caption, design: .serif)
    static let nyCaption2 = Font.system(.caption2, design: .serif)
}
