//
//  FeedbackStore.swift
//  FoodScore
//
//  Stores "Does this feel right?" feedback locally on-device
//  using a JSON file in the app's Documents directory.
//

import Foundation

// MARK: - Model

/// A single feedback event captured from the result screen.
struct FeedbackEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let score: Int?
    let purpose: String          // FoodPurpose.rawValue
    let interpretation: String
    let feedback: String         // "yes" or "not_really"
    let historyEntryID: UUID?    // links to the scan's thumbnail via HistoryStore
}

// MARK: - Persistence

/// Simple file-based storage for feedback events.
/// Uses a JSON array in Documents/feedback.json.
enum FeedbackStore {

    // MARK: Public API

    /// Save a new feedback entry.
    static func save(_ entry: FeedbackEntry) {
        var entries = loadAll()
        entries.insert(entry, at: 0) // newest first
        writeAll(entries)
    }

    /// Load all feedback entries, newest first.
    static func loadAll() -> [FeedbackEntry] {
        guard let data = try? Data(contentsOf: feedbackFileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([FeedbackEntry].self, from: data)) ?? []
    }

    /// Delete a single feedback entry.
    static func deleteEntry(_ entry: FeedbackEntry) {
        var entries = loadAll()
        entries.removeAll { $0.id == entry.id }
        writeAll(entries)
    }

    // MARK: Private helpers

    private static var feedbackFileURL: URL {
        documentsDirectory.appendingPathComponent("feedback.json")
    }

    private static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static func writeAll(_ entries: [FeedbackEntry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: feedbackFileURL, options: .atomic)
    }
}
