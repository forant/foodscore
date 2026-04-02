//
//  ResultView.swift
//  FoodScore
//
//  Created by Timothy Foran on 3/31/26.
//

import SwiftUI
import PhotosUI

// The purposes the user can choose from
enum FoodPurpose: String, CaseIterable, Identifiable {
    case snack = "snack"
    case meal = "meal"
    case postWorkout = "post_workout"
    case treat = "treat"
    case convenience = "convenience"
    case ingredient = "ingredient"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .snack: "Snack"
        case .meal: "Meal"
        case .postWorkout: "Post-workout"
        case .treat: "Treat"
        case .convenience: "Convenience"
        case .ingredient: "Ingredient"
        }
    }
}

// Nutrition data extracted from the label (sent back for re-scoring)
struct ExtractedNutrition: Codable {
    let calories: Double?
    let servingSizeGrams: Double?
    let proteinGrams: Double?
    let fiberGrams: Double?
    let addedSugarGrams: Double?
    let totalSugarGrams: Double?
    let totalFatGrams: Double?
    let saturatedFatGrams: Double?
    let ingredientList: [String]?
    let readable: Bool?
    let confidence: String?
}

// Matches the JSON the backend returns
struct AnalysisResult: Codable {
    let score: Int?
    let whatHelps: [String]
    let whatHurts: [String]
    let interpretation: String
    let confidence: String
    let extractedNutrition: ExtractedNutrition?

    // Normal initializer — used when creating results locally (e.g. the unreadable fallback)
    init(score: Int?, whatHelps: [String], whatHurts: [String], interpretation: String, confidence: String, extractedNutrition: ExtractedNutrition?) {
        self.score = score
        self.whatHelps = whatHelps
        self.whatHurts = whatHurts
        self.interpretation = interpretation
        self.confidence = confidence
        self.extractedNutrition = extractedNutrition
    }

    // Custom decoder — handles common LLM output quirks:
    //   • score might arrive as 7.0 (Double) instead of 7 (Int)
    //   • whatHelps / whatHurts might be null instead of an array
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode score: try Int first, fall back to Double → Int
        if let intScore = try? container.decodeIfPresent(Int.self, forKey: .score) {
            score = intScore
        } else if let doubleScore = try? container.decodeIfPresent(Double.self, forKey: .score) {
            score = Int(doubleScore)
        } else {
            score = nil
        }

        // Decode arrays: default to [] if null or missing
        whatHelps = (try? container.decodeIfPresent([String].self, forKey: .whatHelps)) ?? []
        whatHurts = (try? container.decodeIfPresent([String].self, forKey: .whatHurts)) ?? []

        // Decode strings: default to sensible fallbacks if null or missing
        interpretation = (try? container.decodeIfPresent(String.self, forKey: .interpretation)) ?? ""
        confidence = (try? container.decodeIfPresent(String.self, forKey: .confidence)) ?? "low"

        extractedNutrition = try? container.decodeIfPresent(ExtractedNutrition.self, forKey: .extractedNutrition)
    }
}

struct ResultView: View {
    // Mutable so we can update when the user changes purpose
    @State private var result: AnalysisResult
    @State private var purpose: FoodPurpose = .snack
    @State private var isRescoring = false
    @State private var retryItem: PhotosPickerItem?
    @State private var feedbackGiven = false
    @State private var showEmailFallback = false
    @Environment(\.dismiss) private var dismiss

    /// The photo the user scanned (passed from ContentView).
    var scannedImage: UIImage?

    /// Called when the user picks a new photo from the unreadable screen.
    /// Passes the PhotosPickerItem back so the parent can run extraction.
    var onRetry: ((PhotosPickerItem) -> Void)?

    /// True for fresh scans, false for history items. Controls whether the feedback prompt appears.
    var isNewResult: Bool

    /// The ID of the corresponding ScanHistoryEntry, used to link feedback to a thumbnail.
    var historyEntryID: UUID?

    init(result: AnalysisResult, initialPurpose: FoodPurpose = .snack, scannedImage: UIImage? = nil, isNewResult: Bool = false, historyEntryID: UUID? = nil, onRetry: ((PhotosPickerItem) -> Void)? = nil) {
        _result = State(initialValue: result)
        _purpose = State(initialValue: initialPurpose)
        self.scannedImage = scannedImage
        self.isNewResult = isNewResult
        self.historyEntryID = historyEntryID
        self.onRetry = onRetry
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerCard

                if let scannedImage {
                    scannedImageCard(scannedImage)
                }

                if result.score != nil {
                    // Purpose picker card (always visible)
                    purposeCard

                    if isRescoring {
                        rescoringCard
                    } else if let score = result.score {
                        scoreCard(score: score)

                        if !result.whatHelps.isEmpty {
                            sectionCard(
                                title: "What makes this a good choice",
                                systemImage: "checkmark.circle.fill",
                                iconColor: .green,
                                backgroundColor: Color.green.opacity(0.08),
                                items: result.whatHelps
                            )
                        }

                        if !result.whatHurts.isEmpty {
                            sectionCard(
                                title: "What to keep in mind",
                                systemImage: "info.circle.fill",
                                iconColor: .orange,
                                backgroundColor: Color.orange.opacity(0.08),
                                items: result.whatHurts
                            )
                        }

                        if isNewResult && !feedbackGiven {
                            feedbackCard(score: score)
                        }

                        footerView
                    }
                } else {
                    unreadableCard
                    footerView
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Thanks for the feedback!", isPresented: $showEmailFallback) {
            Button("OK") {}
        } message: {
            Text("Your feedback has been recorded. If you'd like to tell us more, send an email to tim@getowie.com.")
        }
    }

    private func scannedImageCard(_ uiImage: UIImage) -> some View {
        Image(uiImage: uiImage)
            .resizable()
            .scaledToFit()
            .frame(maxHeight: 200)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(12)
            .background(cardBackground)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FoodScore")
                .font(.title2)
                .fontWeight(.bold)

            Text("A quick read on whether this makes sense right now.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(cardBackground)
    }

    private func scoreCard(score: Int) -> some View {
        VStack(spacing: 12) {
            Text("\(score)/10")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(scoreColor(for: score))

            Text(result.interpretation)
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .background(cardBackground)
    }

    private var rescoringCard: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)

            Text("Re-scoring with this new information...")
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 20)
        .background(cardBackground)
    }

    private var unreadableCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)

            Text(result.interpretation)
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)

            PhotosPicker(selection: $retryItem, matching: .images) {
                Label("Try Another Photo", systemImage: "photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(cardBackground)
        .onChange(of: retryItem) {
            if let retryItem {
                onRetry?(retryItem)
                dismiss()
            }
        }
    }

    private func sectionCard(
        title: String,
        systemImage: String,
        iconColor: Color,
        backgroundColor: Color,
        items: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(title)
                    .font(.headline)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(iconColor)
                            .frame(width: 7, height: 7)
                            .padding(.top, 6)

                        Text(item)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var purposeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How are you using this?")
                .font(.headline)

            // Pill-shaped tags in two rows
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    purposeTag(.snack)
                    purposeTag(.meal)
                    purposeTag(.postWorkout)
                }
                HStack(spacing: 8) {
                    purposeTag(.treat)
                    purposeTag(.convenience)
                    purposeTag(.ingredient)
                }
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(cardBackground)
        .onChange(of: purpose) {
            guard let nutrition = result.extractedNutrition else { return }
            Task {
                isRescoring = true
                feedbackGiven = false // reset so user can give feedback on new score
                if let newResult = try? await rescore(
                    nutrition: nutrition,
                    purpose: purpose
                ) {
                    result = newResult
                }
                isRescoring = false
            }
        }
    }

    private func purposeTag(_ p: FoodPurpose) -> some View {
        let isSelected = purpose == p
        return Button {
            purpose = p
        } label: {
            Text(p.displayName)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? .white : .primary)
                .background(isSelected ? Color.accentColor : Color(.systemGray5))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isRescoring)
    }

    // Call the /score endpoint to re-score with a new purpose (no image upload)
    private func rescore(
        nutrition: ExtractedNutrition,
        purpose: FoodPurpose
    ) async throws -> AnalysisResult {
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

        let (data, _) = try await URLSession.shared.upload(for: request, from: body)
        return try JSONDecoder().decode(AnalysisResult.self, from: data)
    }

    // MARK: - Feedback

    private func feedbackCard(score: Int) -> some View {
        VStack(spacing: 12) {
            Text("Does this feel right?")
                .font(.headline)

            HStack(spacing: 16) {
                Button {
                    saveFeedback("yes", score: score)
                } label: {
                    Label("Yes", systemImage: "hand.thumbsup")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.green)
                .controlSize(.regular)

                Button {
                    saveFeedback("not_really", score: score)
                    sendFeedbackEmail(score: score)
                } label: {
                    Label("Not really", systemImage: "hand.thumbsdown")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .controlSize(.regular)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(cardBackground)
    }

    private func saveFeedback(_ value: String, score: Int) {
        let entry = FeedbackEntry(
            id: UUID(),
            date: Date(),
            score: score,
            purpose: purpose.rawValue,
            interpretation: result.interpretation,
            feedback: value,
            historyEntryID: historyEntryID
        )
        FeedbackStore.save(entry)
        feedbackGiven = true

        // Also send to backend (fire-and-forget)
        Task {
            await sendFeedbackToBackend(
                feedback: value,
                score: score,
                purpose: purpose.rawValue,
                interpretation: result.interpretation,
                unreadable: result.score == nil,
                resultId: historyEntryID?.uuidString
            )
        }
    }

    private func sendFeedbackToBackend(
        feedback: String,
        score: Int,
        purpose: String,
        interpretation: String,
        unreadable: Bool,
        resultId: String?
    ) async {
        guard let url = URL(string: "\(APIConfig.baseURL)/feedback") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "feedback": feedback,
            "purpose": purpose,
            "score": score,
            "interpretation": interpretation,
            "unreadable": unreadable,
        ]
        if let resultId { body["resultId"] = resultId }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return }
        _ = try? await URLSession.shared.upload(for: request, from: jsonData)
    }

    private func sendFeedbackEmail(score: Int) {
        let recipient = "tim@getowie.com"
        let subject = "FoodScore — Score didn't feel right"

        let body = """
        What felt off:


        ---
        Score: \(score)/10
        Purpose: \(purpose.displayName)
        Interpretation: \(result.interpretation)
        """

        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body

        if let url = URL(string: "mailto:\(recipient)?subject=\(encodedSubject)&body=\(encodedBody)"),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            showEmailFallback = true
        }
    }

    private var footerView: some View {
        VStack(spacing: 6) {
            Text("Confidence: \(result.confidence)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("General nutrition guidance only, not medical advice.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
    }

    private func scoreColor(for score: Int) -> Color {
        switch score {
        case 8...10:
            return .green
        case 6...7:
            return .blue
        case 4...5:
            return .orange
        default:
            return .red
        }
    }
}

#Preview("Valid Label") {
    NavigationStack {
        ResultView(result: AnalysisResult(
            score: 7,
            whatHelps: ["Solid protein for the calories.", "Good source of fiber."],
            whatHurts: ["A fair amount of added sugar.", "Quite a few processed ingredients."],
            interpretation: "A solid option with some tradeoffs — fine as a regular choice but not an everyday staple.",
            confidence: "high",
            extractedNutrition: ExtractedNutrition(
                calories: 250, servingSizeGrams: 60, proteinGrams: 15,
                fiberGrams: 4, addedSugarGrams: 8, totalSugarGrams: 10,
                totalFatGrams: 9, saturatedFatGrams: 3, ingredientList: ["oats", "whey protein", "sugar"],
                readable: true, confidence: "high"
            )
        ))
    }
}

#Preview("Unreadable Label") {
    NavigationStack {
        ResultView(result: AnalysisResult(
            score: nil,
            whatHelps: [],
            whatHurts: [],
            interpretation: "I couldn't clearly read a nutrition label in this image. Try a closer, clearer photo of the nutrition facts panel.",
            confidence: "low",
            extractedNutrition: nil
        ))
    }
}
