import Foundation
import SwiftData

@Model
final class MoodEntry {
    @Attribute(.unique) var dayKey: String
    var valence: Double
    var note: String?
    var tagsJSON: String?
    var createdAt: Date

    init(dayKey: String, valence: Double, note: String? = nil, tagsJSON: String? = nil) {
        self.dayKey = dayKey
        self.valence = valence
        self.note = note
        self.tagsJSON = tagsJSON
        self.createdAt = .now
    }

    var tags: [String] {
        get {
            guard let tagsJSON, let data = tagsJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let string = String(data: data, encoding: .utf8) {
                tagsJSON = string
            }
        }
    }
}

// configured by qoder
