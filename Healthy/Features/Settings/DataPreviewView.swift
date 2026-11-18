import SwiftUI

struct DataPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let json: String

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(json)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("将发送给 AI 的数据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    DataPreviewView(json: "{\n  \"date\": \"2026-10-30\"\n}")
}
