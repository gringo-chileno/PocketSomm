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
            // OCR line filtering + winery lookups run off the main thread —
            // views are MainActor, so Task {} here would otherwise freeze the UI
            let wineNames = await Task.detached(priority: .userInitiated) {
                MenuScanEngine.extractWineNames(from: texts)
            }.value
            // Store a downscaled photo: full camera resolution was ~2-6MB per
            // scan inside the SwiftData store, decoded whole for 60pt thumbnails
            let photoData = await Task.detached(priority: .userInitiated) {
                image.downscaled(maxDimension: 1200).jpegData(compressionQuality: 0.7)
            }.value

            await MainActor.run {
                // Create scan history
                let scan = ScanHistory(
                    date: Date(),
                    photoData: photoData,
                    detectedWineNames: wineNames
                )

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

            // Convert UIImage orientation to CGImagePropertyOrientation so
            // Vision correctly handles rotated/sideways photos
            let cgOrientation: CGImagePropertyOrientation
            switch image.imageOrientation {
            case .up: cgOrientation = .up
            case .down: cgOrientation = .down
            case .left: cgOrientation = .left
            case .right: cgOrientation = .right
            case .upMirrored: cgOrientation = .upMirrored
            case .downMirrored: cgOrientation = .downMirrored
            case .leftMirrored: cgOrientation = .leftMirrored
            case .rightMirrored: cgOrientation = .rightMirrored
            @unknown default: cgOrientation = .up
            }
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: cgOrientation, options: [:])

            // Vision's accurate OCR takes 1-3s — keep it off the main thread
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    print("Text recognition error: \(error)")
                    continuation.resume(returning: [])
                }
            }
        }
    }

    // Separator used to encode variety context with wine names: "name\tvariety"
    static let varietySeparator = MenuScanEngine.varietySeparator

    private func extractWineNames(from texts: [String]) -> [String] {
        MenuScanEngine.extractWineNames(from: texts)
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


extension UIImage {
    /// Longest side capped at maxDimension; returns self if already smaller
    func downscaled(maxDimension: CGFloat) -> UIImage {
        let largest = max(size.width, size.height)
        guard largest > maxDimension else { return self }
        let scaleFactor = maxDimension / largest
        let newSize = CGSize(width: size.width * scaleFactor, height: size.height * scaleFactor)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
