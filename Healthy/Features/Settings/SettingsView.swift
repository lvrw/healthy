import SwiftData
import SwiftUI

/// 设置根页面：只保留下钻入口，各项功能收进对应子页面。
struct SettingsView: View {
    @State private var aiSummary = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        BasicSettingsView()
                    } label: {
                        Label("基础设置", systemImage: "slider.horizontal.3")
                    }
                }
                Section {
                    NavigationLink {
                        ProfileSettingsView()
                    } label: {
                        Label("基本资料", systemImage: "person.crop.circle")
                    }
                    NavigationLink {
                        HealthDataSettingsView()
                    } label: {
                        Label("健康数据", systemImage: "heart.text.square")
                    }
                    NavigationLink {
                        AISettingsView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AI 服务")
                                if !aiSummary.isEmpty {
                                    Text(aiSummary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: "sparkles")
                        }
                    }
                    NavigationLink {
                        FoodLibraryView()
                    } label: {
                        Label("本地营养库", systemImage: "books.vertical")
                    }
                }
                Section {
                    NavigationLink {
                        DataSettingsView()
                    } label: {
                        Label("数据管理", systemImage: "externaldrive")
                    }
                    NavigationLink {
                        AboutSettingsView()
                    } label: {
                        Label("关于", systemImage: "info.circle")
                    }
                }
                Section {
                    NavigationLink {
                        PerformanceView()
                    } label: {
                        Label("性能监控", systemImage: "gauge.with.dots.needle.33percent")
                    }
                    NavigationLink {
                        DebugLogView()
                    } label: {
                        Label("调试日志", systemImage: "doc.text.magnifyingglass")
                    }
                } footer: {
                    Text("性能监控按页面 / 接口统计调用耗时（平均、P95、最大），用于定位卡顿；调试日志记录同步、HealthKit 读取与错误，两者都可在手机内查看和导出。")
                }
            }
            .navigationTitle("设置")
            .onAppear {
                aiSummary = BriefingService.settingsSummary()
            }
        }
    }
}

/// 基础设置子页面：夜间模式（跟随系统 / 浅色 / 深色），切换后全 App 立即生效。
struct BasicSettingsView: View {
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system

    var body: some View {
        Form {
            Section {
                Picker(selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Label(option.title, systemImage: option.symbol)
                            .tag(option)
                    }
                } label: {
                    Label("夜间模式", systemImage: appearance.symbol)
                }
                .pickerStyle(.inline)
            } header: {
                Text("外观")
            } footer: {
                Text("「跟随系统」会随 iPhone 的浅色 / 深色外观自动切换；手动选择浅色或深色后，App 内所有页面保持该外观。")
            }
        }
        .navigationTitle("基础设置")
    }
}

#Preview {
    SettingsView()
}
