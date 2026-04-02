//
//  HistoryStore.swift
//  FoodScore
//
//  Stores past scan results locally on-device using a JSON file
//  and JPEG thumbnails in the app's Documents directory.
//

import UIKit

// MARK: - Model

/// A single saved scan result.
struct ScanHistoryEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let score: Int?
    let interpretation: String
    let purpose: String            // FoodPurpose.rawValue
    let confidence: String
    let whatHelps: [String]
    let whatHurts: [String]
    let extractedNutrition: ExtractedNutrition?

    /// Create a history entry from an analysis result and purpose.
    init(from result: AnalysisResult, purpose: FoodPurpose) {
        self.id = UUID()
        self.date = Date()
        self.score = result.score
        self.interpretation = result.interpretation
        self.purpose = purpose.rawValue
        self.confidence = result.confidence
        self.whatHelps = result.whatHelps
        self.whatHurts = result.whatHurts
        self.extractedNutrition = result.extractedNutrition
    }
}

// MARK: - Persistence

/// Simple file-based storage for scan history.
/// Uses a JSON array in Documents/scan_history.json and
/// JPEG thumbnails in Documents/thumbnails/<uuid>.jpg.
enum HistoryStore {

    // MARK: Public API

    /// Save a new entry and its thumbnail to disk.
    static func save(entry: ScanHistoryEntry, thumbnail: UIImage?) {
        var entries = loadAll()
        entries.insert(entry, at: 0)    // newest first
        writeAll(entries)

        if let thumbnail {
            saveThumbnail(thumbnail, for: entry.id)
        }
    }

    /// Load all saved entries, newest first.
    static func loadAll() -> [ScanHistoryEntry] {
        guard let data = try? Data(contentsOf: historyFileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ScanHistoryEntry].self, from: data)) ?? []
    }

    /// Load the thumbnail image for a given entry.
    static func thumbnailImage(for entryID: UUID) -> UIImage? {
        let url = thumbnailsDirectory.appendingPathComponent("\(entryID.uuidString).jpg")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Delete a single entry and its thumbnail.
    static func deleteEntry(_ entry: ScanHistoryEntry) {
        var entries = loadAll()
        entries.removeAll { $0.id == entry.id }
        writeAll(entries)

        let thumbURL = thumbnailsDirectory.appendingPathComponent("\(entry.id.uuidString).jpg")
        try? FileManager.default.removeItem(at: thumbURL)
    }

    // MARK: Private helpers

    private static var historyFileURL: URL {
        documentsDirectory.appendingPathComponent("scan_history.json")
    }

    private static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static var thumbnailsDirectory: URL {
        let url = documentsDirectory.appendingPathComponent("thumbnails")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    private static func writeAll(_ entries: [ScanHistoryEntry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: historyFileURL, options: .atomic)
    }

    /// Downscale image to ~150px wide and save as compressed JPEG.
    private static func saveThumbnail(_ image: UIImage, for entryID: UUID) {
        let maxWidth: CGFloat = 150
        let scale = min(maxWidth / image.size.width, 1.0)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let thumbnail = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        let url = thumbnailsDirectory.appendingPathComponent("\(entryID.uuidString).jpg")
        if let jpegData = thumbnail.jpegData(compressionQuality: 0.7) {
            try? jpegData.write(to: url, options: .atomic)
        }
    }
}
