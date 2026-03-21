import SwiftUI

struct WineBottleImage: View {
    let wine: Wine
    var size: CGFloat = 120

    var body: some View {
        WinePlaceholder(wineType: wine.wineType, size: size)
            .frame(width: size, height: size * 1.5)
    }
}

struct WinePlaceholder: View {
    let wineType: String?
    var size: CGFloat = 120

    private var bottleColor: Color {
        switch wineType?.lowercased() {
        case "red":
            return .wineRed
        case "white":
            return Color(red: 0.95, green: 0.9, blue: 0.7) // Pale gold
        case "rosé", "rose":
            return Color(red: 0.95, green: 0.7, blue: 0.75) // Pink
        case "sparkling":
            return Color(red: 0.85, green: 0.85, blue: 0.75) // Champagne
        case "dessert":
            return Color(red: 0.8, green: 0.6, blue: 0.3) // Amber
        default:
            return .wineRed
        }
    }

    private var bottleIcon: String {
        switch wineType?.lowercased() {
        case "sparkling":
            return "party.popper" // Champagne-ish
        default:
            return "wineglass.fill"
        }
    }

    var body: some View {
        ZStack {
            // Bottle shape background
            RoundedRectangle(cornerRadius: size * 0.1)
                .fill(
                    LinearGradient(
                        colors: [
                            bottleColor.opacity(0.3),
                            bottleColor.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.1)
                        .stroke(bottleColor.opacity(0.3), lineWidth: 1)
                )

            // Wine icon
            VStack(spacing: size * 0.05) {
                Image(systemName: bottleIcon)
                    .font(.system(size: size * 0.35))
                    .foregroundColor(bottleColor.opacity(0.6))

                if let type = wineType {
                    Text(type)
                        .font(.system(size: size * 0.1, weight: .medium, design: .serif))
                        .foregroundColor(bottleColor.opacity(0.8))
                }
            }
        }
        .frame(width: size, height: size * 1.5)
    }
}

// Compact version for lists and cards
struct WineBottleImageCompact: View {
    let wine: Wine
    var size: CGFloat = 50

    private var placeholderColor: Color {
        switch wine.wineType?.lowercased() {
        case "red": return .wineRed
        case "white": return Color(red: 0.8, green: 0.7, blue: 0.4)
        case "rosé", "rose": return Color(red: 0.9, green: 0.5, blue: 0.6)
        default: return .wineRed
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(placeholderColor.opacity(0.2))

            Image(systemName: "wineglass.fill")
                .font(.system(size: size * 0.4))
                .foregroundColor(placeholderColor.opacity(0.5))
        }
        .frame(width: size, height: size * 1.3)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

#Preview {
    VStack(spacing: 20) {
        WineBottleImage(
            wine: Wine(name: "Test Red", wineType: "Red"),
            size: 100
        )

        WineBottleImage(
            wine: Wine(name: "Test White", wineType: "White"),
            size: 100
        )

        WineBottleImage(
            wine: Wine(name: "Test Sparkling", wineType: "Sparkling"),
            size: 100
        )

        HStack {
            WineBottleImageCompact(
                wine: Wine(name: "Compact", wineType: "Red"),
                size: 40
            )
            WineBottleImageCompact(
                wine: Wine(name: "Compact", wineType: "White"),
                size: 40
            )
        }
    }
    .padding()
}
