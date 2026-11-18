import Foundation

/// 把一段完整回复切成「句子」，用于服务端不支持流式时的逐句回放，
/// 以及流式增量按句末标点决定何时刷新到界面。
enum SentenceSplitter {
    private static let terminators: Set<Character> = ["。", "！", "？", "!", "?", "；", ";", "\n"]

    /// 保留句末标点；连续的换行不会产出空句；没有标点的长文本整体作为一句。
    static func split(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if terminators.contains(character) {
                appendIfNeeded(current, to: &result)
                current = ""
            }
        }
        appendIfNeeded(current, to: &result)
        return result
    }

    /// 是否包含句末标点，用于流式增量触发一次刷新。
    static func endsSentence(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return terminators.contains(last)
    }

    private static func appendIfNeeded(_ text: String, to result: inout [String]) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        result.append(text)
    }
}

// configured by qoder
