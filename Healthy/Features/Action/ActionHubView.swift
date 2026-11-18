import SwiftUI

/// 原型中「洞察」不是独立主标签，而是「行动」页顶部与「行动」并列的子页签。
enum ActionSection: String, CaseIterable, Sendable {
    case actions
    case insights

    var title: String {
        switch self {
        case .actions: return "行动"
        case .insights: return "洞察"
        }
    }
}

/// 原型 .page-head 标题式子页签：选中项 27px 加粗深色，未选中 24px 灰色，右侧绿色 ✦。
struct ActionInsightHeader: View {
    @Binding var selection: ActionSection

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            ForEach(ActionSection.allCases, id: \.self) { section in
                let isActive = selection == section
                Button {
                    selection = section
                } label: {
                    Text(section.title)
                        .font(.system(size: isActive ? 27 : 24, weight: isActive ? .bold : .semibold))
                        .foregroundStyle(isActive ? AppPalette.ink : Color(red: 0.659, green: 0.686, blue: 0.671))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isActive ? [.isSelected] : [])
            }
            Text("✦")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppPalette.greenDeep)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }
}

/// 行动主标签容器：复用现有 ActionView / InsightsView 及其数据链路，
/// 仅按原型把两者合并到同一个主标签下。
struct ActionHubView: View {
    @State private var section: ActionSection = .actions

    var body: some View {
        VStack(spacing: 0) {
            ActionInsightHeader(selection: $section)
            Group {
                switch section {
                case .actions:
                    ActionView(showsNavigationTitle: false)
                case .insights:
                    InsightsView(showsNavigationTitle: false)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .background(AppScreenBackground(tone: .mint))
    }
}
