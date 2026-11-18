import SwiftUI

struct FAQListView: View {
    var topic: FAQTopic? = nil
    /// 多主题过滤：详情页可按 HRV / 压力只展示相关问答。
    var topics: [FAQTopic]? = nil

    private var items: [FAQItem] {
        if let topics {
            return FAQContent.all.filter { topics.contains($0.topic) }
        }
        if let topic {
            return FAQContent.items(for: topic)
        }
        return FAQContent.all
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                DisclosureGroup {
                    Text(item.answer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text(item.question)
                        .font(.subheadline.weight(.medium))
                }
                .tint(.secondary)
                .padding(.vertical, 8)
                if item.id != items.last?.id {
                    Divider()
                }
            }
        }
    }
}

// configured by qoder