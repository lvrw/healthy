import SwiftUI

@main
struct HealthyWatchApp: App {
    @StateObject private var env = AppEnvironment()
    /// 调试用：`-openWater` 启动即进入喝水页，方便在没有 UI 自动化时截图核对目标值。
    @State private var path: [String] = CommandLine.arguments.contains("-openWater") ? ["water"] : []

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $path) {
                DashboardView()
                    .navigationDestination(for: String.self) { destination in
                        if destination == "water" {
                            WaterView()
                        }
                    }
            }
            .environmentObject(env)
        }
    }
}
