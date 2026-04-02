//
//  FeedbackReviewView.swift
//  FoodScore
//
//  Internal review screen for "Does this feel right?" feedback.
//

import SwiftUI

struct FeedbackReviewView: View {
    @State private var entries: [FeedbackEntry] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if entries.isEmpty {
                emptyState
            } else {
                feedbackList
            }
        }
        .navigationTitle("Feedback")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            entries = FeedbackStore.loadAll()
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "hand.thumbsup")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            Text("No feedback yet")
                .font(.title3)
                .fontWeight(.semibold)

            Text("User feedback will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - List

    private var feedbackList: some View {
        List {
            ForEach(entries) { entry in
                feedbackRow(entry)
            }
            .onDelete { indexSet in
                for index in indexSet {
                    FeedbackStore.deleteEntry(entries[index])
                }
                entries.remove(atOffsets: indexSet)
            }
        }
    }

    // MARK: - Row

    private func feedbackRow(_ entry: FeedbackEntry) -> some View {
        HStack(spacing: 12) {
            // Feedback indicator
            Image(systemName: entry.feedback == "yes" ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                .font(.title3)
                .foregroundStyle(entry.feedback == "yes" ? .green : .orange)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let score = entry.score {
                        Text("\(score)/10")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(scoreColor(for: score))
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
    NavigationStack {
        FeedbackReviewView()
    }
}
