import SwiftUI

// Wine app color theme - dark cabernet red
extension Color {
    static let wineRed = Color(red: 0.45, green: 0.12, blue: 0.16)
    static let wineRedLight = Color(red: 0.55, green: 0.18, blue: 0.22)
    static let wineRedDark = Color(red: 0.35, green: 0.08, blue: 0.12)
}

extension ShapeStyle where Self == Color {
    static var wineRed: Color { Color.wineRed }
    static var wineRedLight: Color { Color.wineRedLight }
    static var wineRedDark: Color { Color.wineRedDark }
}
