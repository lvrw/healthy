import Foundation
import SwiftData

@Model
final class ChatSession {
    @Attribute(.unique) var dayKey: String
    var messagesJSON: String
    var updatedAt: Date

    init(dayKey: String) {
        self.dayKey = dayKey
        self.messagesJSON = "[]"
        self.updatedAt = .now
    }

    var messages: [ChatMessage] {
        get {
            guard let data = messagesJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([ChatMessage].self, from: data)
            else { return [] }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let string = String(data: data, encoding: .utf8)
            else { return }
            messagesJSON = string
            updatedAt = .now
        }
    }
}

// configured by qoder