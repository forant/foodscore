//
//  ContentView.swift
//  FoodScore
//
//  Created by Timothy Foran on 3/31/26.
//

import SwiftUI
import PhotosUI

struct ContentView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: Image?
    @State private var selectedUIImage: UIImage?
    @State private var isExtracting = false
    @State private var isScoring = false
    @State private var showResult = false
    @State private var extractedNutrition: ExtractedNutrition?
    @State private var selectedPurpose: FoodPurpose?
    @State private var analysisResult: AnalysisResult?
    @State private var errorMessage: String?
    @State private var showHistory = false
    @State private var recentHistory: [ScanHistoryEntry] = []
    @State private var selectedHistoryEntry: ScanHistoryEntry?
    @State private var showScanOptions = false
    @State private var feedbackAlertMessage: String?
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var lastHistoryEntryID: UUID?

    // True when extraction is done and the label was readable
    private var showPurposePicker: Bool {
        extractedNutrition != nil && extractedNutrition?.readable == true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    heroCard

                    if let selectedImage {
                        imagePreviewCard(selectedImage)
                    }

                    // Show purpose picker after extraction, before first score
                    if showPurposePicker {
                        purposePickerCard
                    }

                    actionCard

                    if !recentHistory.isEmpty {
                        recentScansCard
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("FoodScore")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showResult) {
                if let analysisResult {
                    ResultView(result: analysisResult, initialPurpose: selectedPurpose ?? .snack, scannedImage: selectedUIImage, isNewResult: true, historyEntryID: lastHistoryEntryID) { newItem in
                        selectedItem = newItem
                    }
                }
            }
            .onAppear {
                recentHistory = Array(HistoryStore.loadAll().prefix(3))
            }
            .onChange(of: showResult) {
                if !showResult {
                    // User navigated back — reset to a clean state for the next scan
                    selectedItem = nil
                    selectedImage = nil
                    selectedUIImage = nil
                    extractedNutrition = nil
                    selectedPurpose = nil
                    analysisResult = nil
                    isExtracting = false
                    isScoring = false
                    lastHistoryEntryID = nil
                    recentHistory = Array(HistoryStore.loadAll().prefix(3))
                }
            }
            .navigationDestination(item: $selectedHistoryEntry) { entry in
                ResultView(
                    result: AnalysisResult(
                        score: entry.score,
                        whatHelps: entry.whatHelps,
                        whatHurts: entry.whatHurts,
                        interpretation: entry.interpretation,
                        confidence: entry.confidence,
                        extractedNutrition: entry.extractedNutrition
                    ),
                    initialPurpose: FoodPurpose(rawValue: entry.purpose) ?? .snack,
                    scannedImage: HistoryStore.thumbnailImage(for: entry.id)
                )
            }
            .alert("Analysis Failed", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("We want your feedback!", isPresented: .init(
                get: { feedbackAlertMessage != nil },
                set: { if !$0 { feedbackAlertMessage = nil } }
            )) {
                Button("OK") { feedbackAlertMessage = nil }
            } message: {
                Text(feedbackAlertMessage ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { openFeedbackEmail() } label: {
                        Image(systemName: "bubble.left.and.bubble.right")
                    }
                }
            }
            .sheet(isPresented: $showHistory) {
                HistoryView()
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedItem, matching: .images)
            .onChange(of: selectedItem) {
                Task {
                    if let data = try? await selectedItem?.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        processNewImage(uiImage, data: data)
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraView { uiImage in
                    if let data = uiImage.jpegData(compressionQuality: 0.9) {
                        processNewImage(uiImage, data: data)
                    }
                }
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Is this a good choice right now?")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Snap a nutrition label and get a quick, practical read — not rules, not guilt, just clarity.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("How it works")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 10) {
                    Label("Scan a nutrition label", systemImage: "camera.viewfinder")
                    Label("Get a practical score and explanation", systemImage: "chart.bar.doc.horizontal")
                    Label("See what makes it a good choice — and what to keep in mind", systemImage: "checkmark.circle")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(cardBackground)
    }

    private func imagePreviewCard(_ selectedImage: Image) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Selected image")
                .font(.headline)

            selectedImage
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 250)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(cardBackground)
    }

    private var actionCard: some View {
        VStack(spacing: 16) {
            if isExtracting {
                ProgressView("Reading label...")
            }

            Button {
                showScanOptions = true
            } label: {
                Label("Scan nutrition label", systemImage: "camera.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isExtracting || isScoring)
            .confirmationDialog("Scan nutrition label", isPresented: $showScanOptions) {
                Button("Take Photo") {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        showCamera = true
                    } else {
                        errorMessage = "Camera is not available on this device."
                    }
                }
                Button("Choose from Library") {
                    showPhotoPicker = true
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(cardBackground)
    }

    /// Shared logic for processing an image from either the camera or the photo library.
    private func processNewImage(_ uiImage: UIImage, data: Data) {
        selectedUIImage = uiImage
        selectedImage = Image(uiImage: uiImage)

        // Reset state for a new photo
        extractedNutrition = nil
        selectedPurpose = nil
        analysisResult = nil

        Task {
            isExtracting = true
            do {
                let nutrition = try await extractFromImage(data: data)
                extractedNutrition = nutrition

                // If unreadable, skip purpose picker and go straight to result
                if nutrition.readable != true {
                    let unreadableResult = AnalysisResult(
                        score: nil,
                        whatHelps: [],
                        whatHurts: [],
                        interpretation: "I couldn't clearly read a nutrition label in this image. Try a closer, clearer photo of the nutrition facts panel.",
                        confidence: "low",
                        extractedNutrition: nutrition
                    )
                    analysisResult = unreadableResult
                    let historyEntry = ScanHistoryEntry(from: unreadableResult, purpose: .snack)
                    HistoryStore.save(entry: historyEntry, thumbnail: selectedUIImage)
                    lastHistoryEntryID = historyEntry.id
                    showResult = true
                }
                // Otherwise the purpose picker card will appear
            } catch {
                errorMessage = error.localizedDescription
            }
            isExtracting = false
        }
    }

    // MARK: - Purpose picker (shown after extraction)

    private var purposePickerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How are you using this?")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    purposeButton(.snack)
                    purposeButton(.meal)
                    purposeButton(.postWorkout)
                }
                HStack(spacing: 8) {
                    purposeButton(.treat)
                    purposeButton(.convenience)
                    purposeButton(.ingredient)
                }
            }

            if isScoring {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Scoring...")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(cardBackground)
    }

    private func purposeButton(_ p: FoodPurpose) -> some View {
        Button {
            selectPurpose(p)
        } label: {
            Text(p.displayName)
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .foregroundStyle(.primary)
                .background(Color(.systemGray5))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isScoring)
    }

    private func selectPurpose(_ purpose: FoodPurpose) {
        guard let nutrition = extractedNutrition else { return }
        selectedPurpose = purpose
        Task {
            isScoring = true
            do {
                analysisResult = try await scoreNutrition(nutrition: nutrition, purpose: purpose)
                if let analysisResult {
                    let historyEntry = ScanHistoryEntry(from: analysisResult, purpose: purpose)
                    HistoryStore.save(entry: historyEntry, thumbnail: selectedUIImage)
                    lastHistoryEntryID = historyEntry.id
                }
                showResult = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isScoring = false
        }
    }

    // MARK: - Recent scans

    private var recentScansCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent")
                    .font(.headline)

                Spacer()

                Button("See all") { showHistory = true }
                    .font(.subheadline)
            }

            ForEach(recentHistory) { entry in
                Button {
                    selectedHistoryEntry = entry
                } label: {
                    recentRow(entry)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(cardBackground)
    }

    private func recentRow(_ entry: ScanHistoryEntry) -> some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let thumb = HistoryStore.thumbnailImage(for: entry.id) {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.systemGray5))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
            }

            // Score + purpose
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let score = entry.score {
                        Text("\(score)/10")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(scoreColor(for: score))
                    } else {
                        Text("Unreadable")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(.orange)
                    }

                    Text(FoodPurpose(rawValue: entry.purpose)?.displayName ?? entry.purpose)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }

                Text(entry.interpretation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func scoreColor(for score: Int) -> Color {
        switch score {
        case 8...10: .green
        case 6...7: .blue
        case 4...5: .orange
        default: .red
        }
    }

    // MARK: - Feedback

    private func openFeedbackEmail() {
        let recipient = "tim@getowie.com"
        let subject = "FoodScore Feedback"

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let device = UIDevice.current.model
        let systemVersion = UIDevice.current.systemVersion

        let body = """
        What I tried:

        What happened:

        What I expected:

        ---
        App: \(appVersion) (\(buildNumber))
        Device: \(device), iOS \(systemVersion)
        """

        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body

        if let url = URL(string: "mailto:\(recipient)?subject=\(encodedSubject)&body=\(encodedBody)"),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            feedbackAlertMessage = "No email app is set up on this device. You can send feedback to \(recipient) manually."
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
    }

    // MARK: - Network calls

    /// Step 1: Upload the image to /extract — returns nutrition data only, no score
    func extractFromImage(data: Data) async throws -> ExtractedNutrition {
        let url = URL(string: "\(APIConfig.baseURL)/extract")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"image\"; filename=\"photo.jpg\"\r\n".utf8))
        body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        let (responseData, _) = try await URLSession.shared.upload(for: request, from: body)
        return try JSONDecoder().decode(ExtractedNutrition.self, from: responseData)
    }

    /// Step 2: Send extracted nutrition + purpose to /score — returns the scored result
    func scoreNutrition(nutrition: ExtractedNutrition, purpose: FoodPurpose) async throws -> AnalysisResult {
        let url = URL(string: "\(APIConfig.baseURL)/score")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct ScoreRequest: Encodable {
            let extractedNutrition: ExtractedNutrition
            let purpose: String
        }

        let body = try JSONEncoder().encode(
            ScoreRequest(extractedNutrition: nutrition, purpose: purpose.rawValue)
        )

        let (responseData, _) = try await URLSession.shared.upload(for: request, from: body)
        return try JSONDecoder().decode(AnalysisResult.self, from: responseData)
    }
}

// MARK: - Camera wrapper

/// Wraps UIImagePickerController for camera capture.
struct CameraView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    var onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView

        init(_ parent: CameraView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    ContentView()
}
