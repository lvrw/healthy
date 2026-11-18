import SwiftUI

/// 关于子页面：版本与免责声明。
struct AboutSettingsView: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("版本", value: "0.1.0")
            }
            Section {
                Text("本 App 仅用于个人健康数据参考，不提供医疗诊断。评分、身体年龄等均为相对个人基线的娱乐性估算，不构成医学指标；如有不适请咨询医生。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("说明")
            }
        }
        .navigationTitle("关于")
    }
}

#Preview {
    NavigationStack {
        AboutSettingsView()
    }
}
