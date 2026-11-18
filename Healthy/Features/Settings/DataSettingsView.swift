import SwiftData
import SwiftUI

/// 数据管理子页面：本地数据统计、示例数据与删除。
struct DataSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \DailyMetrics.dayKey) private var metrics: [DailyMetrics]
    @Query private var scores: [DailyScore]
    @Query private var reports: [DailyReport]
    @Query private var chatSessions: [ChatSession]
    @Query private var checkIns: [ActionCheckIn]
    @State private var message: String?

    var body: some View {
        Form {
            Section("本地数据") {
                LabeledContent("健康数据", value: "\(metrics.count) 天")
                LabeledContent("评分记录", value: "\(scores.count) 天")
                LabeledContent("智能评分", value: "\(reports.count) 天")
                LabeledContent("AI 对话", value: "\(chatSessions.count) 天")
                LabeledContent("本地打卡", value: "\(checkIns.count) 条")
            }
            #if DEBUG
            Section {
                Button("载入示例数据（118 天）") {
                    Task { await installSamples() }
                }
            } footer: {
                Text("仅调试构建可用：写入 118 天演示数据并重算评分。")
            }
            #endif
            Section {
                Button("删除全部数据", role: .destructive) {
                    deleteAll()
                }
            }
            if let message {
                Section {
                    Text(message)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("数据管理")
    }

    @MainActor
    private func installSamples() async {
        #if DEBUG
        do {
            let inserted = try DemoDataInstaller.install(into: context)
            try await ScoreStore.recomputeAll(in: context)
            message = "已载入示例数据，新增 \(inserted) 天。"
        } catch {
            message = "载入失败：\(error.localizedDescription)"
        }
        #endif
    }

    private func deleteAll() {
        do {
            try context.delete(model: DailyMetrics.self)
            try context.delete(model: DailyScore.self)
            try context.delete(model: DailyReport.self)
            try context.delete(model: ChatSession.self)
            try context.delete(model: ActionCheckIn.self)
            try context.delete(model: MoodEntry.self)
            try context.save()
            message = "已删除全部本地数据。"
        } catch {
            message = "删除失败：\(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack {
        DataSettingsView()
    }
    .modelContainer(for: [DailyMetrics.self, DailyScore.self, DailyReport.self, ChatSession.self, ActionCheckIn.self, MoodEntry.self, CustomFood.self, FrequentFood.self, FoodGroup.self], inMemory: true)
}
