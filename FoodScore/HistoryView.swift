//
//  HistoryView.swift
//  FoodScore
//
//  Shows a list of past scan results saved on-device.
//

import SwiftUI

struct HistoryView: View {
    @State private var entries: [ScanHistoryEntry] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    emptyState
                } else {
                    historyList
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                entries = HistoryStore.loadAll()
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            Text("No scans yet")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Your past scans will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - List

    private var historyList: some View {
        List {
            ForEach(entries) { entry in
                NavigationLink {
                    // Reconstruct a ResultView from the saved entry
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
                } label: {
                    historyRow(entry)
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    HistoryStore.deleteEntry(entries[index])
                }
                entries.remove(atOffsets: indexSet)
            }

            Section {
                NavigationLink {
                    FeedbackReviewView()
                } label: {
                    Label("Review Feedback", systemImage: "hand.thumbsup")
                }
            }
        }
    }

    // MARK: - Row

    private func historyRow(_ entry: ScanHistoryEntry) -> some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let thumb = HistoryStore.thumbnailImage(for: entry.id) {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.systemGray5))
                    .frame(width: 52, height: 52)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }

            // Details
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    // Score badge
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

                    // Purpose pill
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
                    .lineLimit(2)

                Text(entry.date, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func scoreColor(for score: Int) -> Color {
        switch score {
        case 8...10: .green
        case 6...7: .blue
        case 4...5: .orange
        default: .red
        }
    }
}

#Preview {
    HistoryView()
}
