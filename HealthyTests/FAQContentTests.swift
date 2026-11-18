import Foundation
import Testing

struct FAQContentTests {
    @Test func itemIDsAreUnique() {
        let ids = FAQContent.all.map(\.id)
        #expect(!ids.isEmpty)
        #expect(Set(ids).count == ids.count)
    }

    @Test func itemsHaveNonEmptyText() {
        for item in FAQContent.all {
            #expect(!item.question.isEmpty)
            #expect(!item.answer.isEmpty)
        }
    }

    @Test func everyTopicHasItems() {
        for topic in FAQTopic.allCases {
            #expect(!FAQContent.items(for: topic).isEmpty)
        }
    }

    @Test func topicFilterOnlyReturnsMatchingItems() {
        let items = FAQContent.items(for: .sleep)
        #expect(!items.isEmpty)
        #expect(items.allSatisfy { $0.topic == .sleep })
    }
}

// configured by qoder