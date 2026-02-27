import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScanHistory.date, order: .reverse) private var scans: [ScanHistory]

    var body: some View {
        NavigationStack {
            Group {
                if scans.isEmpty {
                    EmptyHistoryView()
                } else {
                    List {
                        ForEach(scans) { scan in
                            NavigationLink(destination: ScanResultsView(scan: scan)) {
                                ScanHistoryRowView(scan: scan)
                            }
                        }
                        .onDelete(perform: deleteScans)
                    }
                }
            }
            .navigationTitle("Scan History")
            .toolbar {
                if !scans.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        EditButton()
                    }
                }
            }
        }
    }

    private func deleteScans(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(scans[index])
        }
    }
}

struct ScanHistoryRowView: View {
    let scan: ScanHistory

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let photoData = scan.photoData,
               let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 70, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: 70, height: 70)
                    .overlay(
                        Image(systemName: "doc.text.viewfinder")
                            .font(.nyTitle2)
                            .foregroundColor(.gray)
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(scan.date.formatted(date: .long, time: .shortened))
                    .font(.nySubheadline)
                    .fontWeight(.medium)

                Text("\(scan.detectedWineNames.count) wines detected")
                    .font(.nyCaption)
                    .foregroundColor(.secondary)

                if !scan.detectedWineNames.isEmpty {
                    Text(scan.detectedWineNames.prefix(3).joined(separator: ", "))
                        .font(.nyCaption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct EmptyHistoryView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock")
                .font(.system(size: 60))
                .foregroundColor(.wineRed.opacity(0.5))

            Text("No Scans Yet")
                .font(.nyTitle2)
                .fontWeight(.semibold)

            Text("Scan a wine menu to see your history here.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 32)
        }
    }
}

#Preview {
    HistoryView()
        .modelContainer(for: [Wine.self, UserRating.self, ScanHistory.self], inMemory: true)
}
