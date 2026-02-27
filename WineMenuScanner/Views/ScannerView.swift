import SwiftUI
import SwiftData
import PhotosUI
import Vision

struct ScannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var isProcessing = false
    @State private var showingCamera = false
    @State private var detectedTexts: [String] = []
    @State private var showingResults = false
    @State private var createdScan: ScanHistory?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let image = selectedImage {
                    // Show selected image
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 400)
                        .cornerRadius(12)
                        .padding()

                    if isProcessing {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Scanning for wines...")
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Button(action: processImage) {
                            HStack {
                                Image(systemName: "text.viewfinder")
                                Text("Scan for Wines")
                            }
                            .font(.nyHeadline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.wineRed)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)

                        Button("Choose Different Photo") {
                            selectedImage = nil
                            selectedItem = nil
                        }
                        .foregroundColor(.wineRed)
                    }
                } else {
                    Spacer()

                    // Icon
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 80))
                        .foregroundColor(.wineRed.opacity(0.6))

                    Text("Scan a Wine Menu")
                        .font(.nyTitle2)
                        .fontWeight(.semibold)

                    Text("Take a photo or choose from your library")
                        .foregroundColor(.secondary)

                    Spacer()

                    // Camera Button
                    Button(action: { showingCamera = true }) {
                        HStack {
                            Image(systemName: "camera.fill")
                            Text("Take Photo")
                        }
                        .font(.nyHeadline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.wineRed)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)

                    // Photo Library Picker
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        HStack {
                            Image(systemName: "photo.on.rectangle")
                            Text("Choose from Library")
                        }
                        .font(.nyHeadline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)

                    Spacer()
                }
            }
            .navigationTitle("Scan Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onChange(of: selectedItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        selectedImage = uiImage
                        // Auto-start scanning
                        processImage()
                    }
                }
            }
            .sheet(isPresented: $showingCamera) {
                CameraView(image: $selectedImage)
            }
            .onChange(of: selectedImage) { oldValue, newValue in
                // Auto-start scanning when image is set from camera (not from photo picker which handles it separately)
                if oldValue == nil && newValue != nil && selectedItem == nil && !isProcessing {
                    processImage()
                }
            }
            .navigationDestination(isPresented: $showingResults) {
                if let scan = createdScan {
                    ScanResultsView(scan: scan, isNewScan: true, onDone: { dismiss() })
                }
            }
        }
    }

    private func processImage() {
        guard let image = selectedImage else { return }

        isProcessing = true

        Task {
            let texts = await recognizeText(in: image)
            let wineNames = extractWineNames(from: texts)

            await MainActor.run {
                // Create scan history
                let scan = ScanHistory(
                    date: Date(),
                    photoData: image.jpegData(compressionQuality: 0.7),
                    detectedWineNames: wineNames
                )

                // Match wines from database
                let matchedWines = matchWinesFromDatabase(names: wineNames)
                scan.matchedWines = matchedWines

                modelContext.insert(scan)

                // Explicitly save to ensure scan history persists
                do {
                    try modelContext.save()
                } catch {
                    print("Error saving scan: \(error)")
                }

                createdScan = scan

                isProcessing = false
                showingResults = true
            }
        }
    }

    private func recognizeText(in image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let texts = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }

                continuation.resume(returning: texts)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                print("Text recognition error: \(error)")
                continuation.resume(returning: [])
            }
        }
    }

    // Separator used to encode variety context with wine names: "name\tvariety"
    static let varietySeparator = "\t"

    private func extractWineNames(from texts: [String]) -> [String] {
        // Filter and clean up detected texts to find wine names
        var wineNames: [String] = []
        var currentVariety: String? = nil

        // Menu section headers and non-wine items to exclude (Spanish/English)
        let excludedPatterns = [
            // Spanish menu terms
            "otros tintos", "otros blancos", "medias botellas", "por copa", "tintos por copa",
            "blancos por copa", "vinos tintos", "vinos blancos", "espumantes", "postres",
            "carta de vinos", "nuestra selección", "selección de", "media botella",
            // English menu terms
            "by the glass", "red wines", "white wines", "sparkling wines", "dessert wines",
            "wine list", "our selection", "half bottle", "bottle", "glass",
            // Common non-wine items
            "appetizers", "entradas", "principales", "main courses", "desserts",
            // Websites and URLs
            ".com", ".net", ".org", "www.", "http", "foodsherpas", "instagram", "facebook"
        ]

        // Price patterns (various currencies)
        let pricePatterns = [
            /^\$\s*\d+/,           // $50, $ 50
            /^\d+\s*\$/,           // 50$
            /^S\s*[\d,\.]+$/,      // S 28,500 (Chilean/Peruvian Sol)
            /^S\/\s*[\d,\.]+$/,    // S/ 28,500 (Sol with slash)
            /^\d+[\.,]\d{3}$/,     // 28,500 or 28.500
            /^[\d,\.]+\s*€/,       // European prices
            /^€\s*[\d,\.]+/,       // €50
            /^\d+\.\d{2}$/,        // 50.00
            /^E\s*[\d,\.]+$/,      // E 38,000 (generic currency)
            /^[A-Z]\s*[\d,\.]+$/   // Single letter + number pattern (currencies)
        ]

        // Grape varieties — used both for section header detection and variety context
        let grapeVarieties: Set<String> = [
            "cabernet sauvignon", "cabernet franc", "cabernet", "merlot",
            "pinot noir", "pinot grigio", "pinot gris", "pinot",
            "chardonnay", "sauvignon blanc", "sauvignon",
            "syrah", "shiraz", "riesling", "malbec", "zinfandel",
            "carmenere", "carménère", "carmenère",
            "tempranillo", "sangiovese", "garnacha", "grenache",
            "cinsault", "cinsaut", "mourvèdre", "mourvedre",
            "pais", "país", "viognier", "gewürztraminer", "gewurztraminer",
            "semillon", "sémillon", "muscat", "moscatel",
            "torrontés", "torrontes", "touriga nacional",
            "carignan", "petit verdot", "petit sirah", "petite sirah",
            "blanc", "rosé", "rose", "tinto", "blanco", "noir",
            "red blend", "white blend"
        ]

        // Common wine regions — skip when standalone
        let regionNames: Set<String> = [
            // Chile
            "cachapoal", "colchagua", "maipo", "casablanca", "aconcagua",
            "cauquenes", "itata", "curicó", "curico", "rapel", "maule",
            "san antonio", "leyda", "limarí", "limari", "elqui", "bío-bío",
            "malleco", "marchigüe", "marchigue", "apalta", "millahue",
            "maipo andes", "central valley", "millahue cachapoal",
            // France
            "bordeaux", "burgundy", "bourgogne", "champagne", "rhône",
            "alsace", "loire", "provence", "languedoc", "roussillon",
            // Italy
            "tuscany", "toscana", "piedmont", "piemonte", "veneto", "sicily",
            // Spain
            "rioja", "ribera del duero", "priorat", "galicia", "penedès",
            // Argentina
            "mendoza", "salta", "patagonia", "uco valley",
            // USA
            "napa valley", "sonoma", "willamette", "paso robles"
        ]

        for text in texts {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip very short or very long strings
            guard trimmed.count >= 4 && trimmed.count <= 100 else { continue }

            let lowercased = trimmed.lowercased()

            // Check if this is a grape variety section header — track it for context
            if grapeVarieties.contains(lowercased) {
                currentVariety = lowercased
                continue
            }

            // Skip excluded menu section headers
            if excludedPatterns.contains(where: { lowercased.contains($0) }) {
                continue
            }

            // Skip strings that look like prices (various formats)
            var isPrice = false
            for pattern in pricePatterns {
                if trimmed.matches(of: pattern).count > 0 {
                    isPrice = true
                    break
                }
            }
            if isPrice { continue }

            // Skip strings that contain $ anywhere
            if trimmed.contains("$") { continue }

            // Skip strings that are just numbers/punctuation
            if trimmed.allSatisfy({ $0.isNumber || $0.isWhitespace || $0 == "," || $0 == "." }) {
                continue
            }

            // Skip very short words that are likely prices or codes
            let words = trimmed.components(separatedBy: .whitespaces)
            if words.count == 1 && trimmed.count < 6 && trimmed.first?.isNumber == true {
                continue
            }

            // Skip standalone region names
            if regionNames.contains(lowercased) {
                continue
            }

            // Wine entry indicators (winery/estate terms, NOT grape varieties)
            let wineEntryKeywords = ["château", "chateau", "domaine", "estate", "vineyard", "winery",
                               "reserve", "reserva", "gran reserva", "grand cru", "premier cru",
                               "viña", "vina", "bodega", "finca", "clos", "casa", "quinta"]

            let hasWineEntryKeyword = wineEntryKeywords.contains { lowercased.contains($0) }
            let hasYear = trimmed.matches(of: /\b(19|20)\d{2}\b/).count > 0
            let hasComma = trimmed.contains(",")

            // Include if: has a winery/estate keyword, has a vintage year, or
            // has a comma (common "Winery, Wine" format on menus)
            if hasWineEntryKeyword || hasYear || hasComma {
                // Encode variety context if we have it (from section header)
                if let variety = currentVariety {
                    wineNames.append(trimmed + ScannerView.varietySeparator + variety)
                } else {
                    wineNames.append(trimmed)
                }
            }
        }

        // Remove duplicates while preserving order (compare by name part only)
        var seen = Set<String>()
        return wineNames.filter { entry in
            let name = entry.components(separatedBy: ScannerView.varietySeparator).first ?? entry
            let lowercased = name.lowercased()
            if seen.contains(lowercased) {
                return false
            }
            seen.insert(lowercased)
            return true
        }
    }

    private func matchWinesFromDatabase(names: [String]) -> [Wine] {
        var matchedWines: [Wine] = []

        for name in names {
            let descriptor = FetchDescriptor<Wine>(
                predicate: #Predicate<Wine> { wine in
                    wine.name.localizedStandardContains(name)
                }
            )

            if let wines = try? modelContext.fetch(descriptor), let wine = wines.first {
                matchedWines.append(wine)
            }
        }

        return matchedWines
    }
}

// MARK: - Camera View
struct CameraView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView

        init(_ parent: CameraView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let uiImage = info[.originalImage] as? UIImage {
                parent.image = uiImage
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    ScannerView()
        .modelContainer(for: [Wine.self, UserRating.self, ScanHistory.self], inMemory: true)
}
