import SwiftUI
import UIKit

struct ChatView: View {
    let dayKey: String

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var service: ChatService?
    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var showReference = false
    @State private var referenceText: String?
    @State private var copiedMessageID: UUID?

    private var questions: [String] {
        ChatPromptBuilder.recommendedQuestions(dayKey: dayKey)
    }

    var body: some View {
        VStack(spacing: 0) {
            referenceBlock
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        if messages.isEmpty {
                            emptyHints
                        }
                        ForEach(messages) { message in
                            bubble(message)
                                .id(message.id)
                        }
                    }
                    .padding(16)
                }
                // 逐句输出时消息条数不变，但内容在变，因此监听整个数组。
                .onChange(of: messages) {
                    if let last = messages.last {
                        withAnimation(reduceMotion ? nil : .snappy) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            Divider()
            inputBar
        }
        .background(AppScreenBackground(tone: .white))
        .navigationTitle("问问 AI")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if service == nil {
                let created = ChatService(context: context)
                service = created
                messages = created.session(for: dayKey).messages
            }
            guard let service else { return }
            // 等待思考 → 逐句追加 → 完成都通过同一条更新流推到界面。
            for await updated in service.messageUpdates() {
                messages = updated
            }
        }
    }

    // MARK: - 今日数据引用

    private var referenceBlock: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy) {
                    showReference.toggle()
                    if showReference, referenceText == nil {
                        referenceText = service?.referencePayload(dayKey: dayKey) ?? "暂无当日数据引用。"
                    }
                }
            } label: {
                HStack {
                    Label("今日数据引用", systemImage: showReference ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.medium))
                    Spacer()
                    Text(ChatService.settingsSummary())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(AppPalette.surface)
            }
            if showReference {
                ScrollView {
                    Text(referenceText ?? "加载中…")
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxHeight: 140)
                .background(AppPalette.line2)
            }
        }
    }

    // MARK: - 空状态与推荐问题

    private var emptyHints: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(
                    LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: Circle()
                )
                .shadow(color: Color.orange.opacity(0.3), radius: 12, y: 4)
            VStack(spacing: 4) {
                Text("问问 AI")
                    .font(.title3.bold())
                Text("基于你今天的健康数据回答问题")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 10) {
                ForEach(questions, id: \.self) { question in
                    Button {
                        send(question)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "text.bubble")
                                .font(.caption)
                                .foregroundStyle(AppPalette.greenDeep)
                            Text(question)
                                .font(.subheadline)
                                .foregroundStyle(AppPalette.ink)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppPalette.ink4)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(AppPalette.line, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 40)
        .padding(.horizontal, 4)
    }

    // MARK: - 消息气泡

    @ViewBuilder
    private func bubble(_ message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            userBubble(message)
        case .assistant:
            assistantBubble(message)
        }
    }

    private func userBubble(_ message: ChatMessage) -> some View {
        HStack(alignment: .bottom) {
            Spacer(minLength: 56)
            VStack(alignment: .trailing, spacing: 4) {
                Text(message.content)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [AppPalette.greenDeep, AppPalette.green],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .fixedSize(horizontal: false, vertical: true)
                timeStamp(message.createdAt)
            }
        }
    }

    private func assistantBubble(_ message: ChatMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            assistantAvatar
            VStack(alignment: .leading, spacing: 5) {
                Group {
                    switch message.status {
                    case .pending, .thinking:
                        HStack(spacing: 10) {
                            TypingIndicator()
                            VStack(alignment: .leading, spacing: 2) {
                                Text("深度思考中")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Text("正在结合今天的健康数据分析…")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                    case .streaming:
                        VStack(alignment: .leading, spacing: 8) {
                            FormattedMessageText(content: message.content)
                                .font(.subheadline)
                                .textSelection(.enabled)
                            HStack(spacing: 8) {
                                TypingIndicator()
                                Text("正在逐句生成…")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(14)
                    case .success, .failed:
                        FormattedMessageText(content: message.content)
                            .font(.subheadline)
                            .textSelection(.enabled)
                            .padding(14)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    message.status == .failed
                        ? Color.red.opacity(0.06)
                        : AppPalette.surface,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            message.status == .failed ? Color.red.opacity(0.25) : AppPalette.line,
                            lineWidth: 1
                        )
                )
                .shadow(color: message.status == .failed ? .clear : AppPalette.cardShadow, radius: 10, y: 2)
                .padding(.trailing, 36)

                if message.status == .failed {
                    HStack(spacing: 10) {
                        Text("回答失败")
                            .font(.caption2)
                            .foregroundStyle(.red)
                        Button {
                            retry()
                        } label: {
                            Label("重试", systemImage: "arrow.clockwise")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                    }
                } else if message.status == .success {
                    actionsRow(message)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var assistantAvatar: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(
                LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: Circle()
            )
    }

    private func actionsRow(_ message: ChatMessage) -> some View {
        HStack(spacing: 16) {
            actionIcon("hand.thumbsup", active: message.liked == true, tint: .green) {
                service?.toggleLike(dayKey: dayKey, messageID: message.id, liked: true)
            }
            actionIcon("hand.thumbsdown", active: message.liked == false, tint: .orange) {
                service?.toggleLike(dayKey: dayKey, messageID: message.id, liked: false)
            }
            Button {
                copyMessage(message)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: copiedMessageID == message.id ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                    if copiedMessageID == message.id {
                        Text("已拷贝")
                            .font(.caption2.weight(.medium))
                    }
                }
                .foregroundStyle(copiedMessageID == message.id ? AppPalette.greenDeep : AppPalette.ink4)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            timeStamp(message.createdAt)
        }
        .padding(.leading, 2)
    }

    private func actionIcon(
        _ symbol: String,
        active: Bool,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: active ? "\(symbol).fill" : symbol)
                .font(.caption)
                .foregroundStyle(active ? tint : AppPalette.ink4)
        }
        .buttonStyle(.plain)
    }

    private func timeStamp(_ date: Date) -> some View {
        Text(date.formatted(date: .omitted, time: .shortened))
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    private func copyMessage(_ message: ChatMessage) {
        UIPasteboard.general.string = message.content
        copiedMessageID = message.id
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if copiedMessageID == message.id {
                copiedMessageID = nil
            }
        }
    }

    // MARK: - 输入栏

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("问问今天的健康数据…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(AppPalette.line, lineWidth: 1)
                )
            Button {
                submit()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        canSend
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [AppPalette.greenDeep, AppPalette.green],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            : AnyShapeStyle(AppPalette.ink4.opacity(0.45)),
                        in: Circle()
                    )
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var canSend: Bool {
        !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        send(draft)
    }

    private func send(_ text: String) {
        guard !isSending, let service else { return }
        draft = ""
        isSending = true
        Task {
            await service.send(dayKey: dayKey, text: text)
            isSending = false
        }
    }

    private func retry() {
        guard !isSending, let service else { return }
        isSending = true
        Task {
            await service.retry(dayKey: dayKey)
            isSending = false
        }
    }

}

/// AI 回复的轻量 Markdown 渲染：粗体/斜体/行内代码交给 AttributedString 解析，
/// 列表前缀（- / * / · / •）统一成圆点；不引入第三方依赖。
struct FormattedMessageText: View {
    let content: String

    var body: some View {
        Text(Self.attributed(content))
    }

    static func attributed(_ content: String) -> AttributedString {
        var result = AttributedString()
        let lines = content.components(separatedBy: "\n")
        for (index, rawLine) in lines.enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            var line = rawLine
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("• ") || trimmed.hasPrefix("· ") || trimmed.hasPrefix("* ") {
                line = "•  " + trimmed.dropFirst(2)
            }
            // markdown 解析失败时回退为纯文本，保证内容始终可见。
            let attributed = (try? AttributedString(
                markdown: line,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                )
            )) ?? AttributedString(line)
            result.append(attributed)
            if index < lines.count - 1 {
                result.append(AttributedString("\n"))
            }
        }
        return result
    }
}

/// 「正在思考」三点动效。
private struct TypingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(AppPalette.ink3)
                    .frame(width: 6.5, height: 6.5)
                    .opacity(animating ? 1 : 0.3)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.55).repeatForever().delay(Double(index) * 0.18),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

#Preview {
    NavigationStack {
        ChatView(dayKey: DayKey.key(for: .now))
    }
}
