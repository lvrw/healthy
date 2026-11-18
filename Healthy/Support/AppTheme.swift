import SwiftUI
import UIKit

/// 原型（prototype/）设计系统色板。
/// 取自 docs/ 下 53 张截图还原的 base.css :root 变量，作为全 App 唯一视觉色源。
/// 文字与分割线全部改用系统语义色，跟随浅色 / 深色模式自动切换。
enum AppPalette {
    /// 按浅色 / 深色分别给值的动态颜色。
    static func adaptive(
        light: (CGFloat, CGFloat, CGFloat),
        dark: (CGFloat, CGFloat, CGFloat)
    ) -> Color {
        Color(uiColor: UIColor { trait in
            let value = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: value.0, green: value.1, blue: value.2, alpha: 1)
        })
    }

    /// 带透明度的自适应色（深色卡片上的白色描边等）。
    static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    static let ink = Color(uiColor: .label)                       // 主文字
    static let ink2 = Color(uiColor: .secondaryLabel)            // 次级文字
    static let ink3 = Color(uiColor: .tertiaryLabel)             // 辅助文字
    static let ink4 = Color(uiColor: .quaternaryLabel)           // 最弱文字 / 占位
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let line = Color(uiColor: .separator)
    static let line2 = Color(uiColor: .tertiarySystemFill)

    static let green = Color(red: 0.475, green: 0.788, blue: 0.557)     // #79C98E 状态优秀
    static let greenDeep = Color(red: 0.306, green: 0.663, blue: 0.455) // #4EA974
    static let greenSoft = adaptive(
        light: (0.906, 0.961, 0.925),   // #E7F5EC
        dark: (0.114, 0.196, 0.145)     // #1D3225
    )
    static let lav = Color(red: 0.553, green: 0.565, blue: 0.894)       // #8D90E4 状态正常
    static let purple = Color(red: 0.424, green: 0.353, blue: 0.851)    // #6C5AD9 睡眠主色
    static let purpleSoft = Color(red: 0.929, green: 0.910, blue: 0.988) // #EDE8FC
    static let orange = Color(red: 0.969, green: 0.608, blue: 0.384)    // #F79B62 注意压力
    static let pink = Color(red: 0.933, green: 0.431, blue: 0.533)      // #EE6E88 压力过载
    static let teal = Color(red: 0.482, green: 0.827, blue: 0.769)      // #7BD3C4
    static let sky = Color(red: 0.341, green: 0.749, blue: 0.902)       // #57BFE6
    static let red = Color(red: 0.941, green: 0.404, blue: 0.494)       // #F0677E

    /// 页面模块底色（浅色模式），深色模式统一压暗。
    static let toneWhite = adaptive(
        light: (0.973, 0.980, 0.976),   // #F8FAF9
        dark: (0.110, 0.110, 0.118)     // #1C1C1E
    )
    static let toneMint = adaptive(
        light: (0.918, 0.965, 0.937),   // #EAF6EF
        dark: (0.086, 0.141, 0.110)
    )
    static let toneLavender = adaptive(
        light: (0.937, 0.918, 0.988),   // #EFEAFC
        dark: (0.118, 0.106, 0.176)
    )
    static let tonePeach = adaptive(
        light: (1.0, 0.949, 0.925),     // #FFF2EC
        dark: (0.157, 0.110, 0.090)
    )

    /// 卡片阴影：浅色为极淡投影，深色加重以在纯黑底上分层。
    static let cardShadow = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.black.withAlphaComponent(0.45)
            : UIColor(red: 0.149, green: 0.196, blue: 0.173, alpha: 0.045)
    })

    /// 行动页卡片底色：浅色仍是系统白卡；深色与睡眠 / 健身深色卡完全同色，
    /// 避免同一页出现两种深浅不同的深灰。
    static let actionCard = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.106, green: 0.133, blue: 0.118, alpha: 1)
            : UIColor.secondarySystemGroupedBackground
    })
}

/// App 内夜间模式：跟随系统 / 浅色 / 深色。
/// 设置页写入 UserDefaults（key: `healthy.appearance`），根视图据此设置窗口外观。
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    /// nil 表示跟随系统，不强制覆盖。
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    static let storageKey = "healthy.appearance"

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}

extension View {
    /// App 内夜间模式：统一走窗口级 overrideUserInterfaceStyle。
    /// 不再使用 preferredColorScheme——它的 nil（跟随系统）不会把窗口外观真正
    /// 重置回系统设置，导致「深色 → 跟随系统」后界面仍停留在深色。
    /// 窗口级外观还能让 sheet / 弹层跟着一起切换。
    func appAppearance(_ appearance: AppAppearance) -> some View {
        modifier(AppAppearanceModifier(appearance: appearance))
    }
}

private struct AppAppearanceModifier: ViewModifier {
    let appearance: AppAppearance

    func body(content: Content) -> some View {
        content
            // 0 尺寸宿主视图只负责把外观写到窗口，不参与布局。
            .background(AppAppearanceHost(appearance: appearance).frame(width: 0, height: 0))
    }
}

private struct AppAppearanceHost: UIViewRepresentable {
    let appearance: AppAppearance

    func makeUIView(context: Context) -> AppAppearanceWindowView {
        AppAppearanceWindowView(appearance: appearance)
    }

    func updateUIView(_ uiView: AppAppearanceWindowView, context: Context) {
        uiView.apply(appearance)
    }
}

/// 把 App 内选择的外观写到所在窗口（以及同场景的其它窗口），
/// 保证 sheet、弹窗、键盘之外的呈现层与页面外观一致。
final class AppAppearanceWindowView: UIView {
    private var appearance: AppAppearance

    init(appearance: AppAppearance) {
        self.appearance = appearance
        super.init(frame: .zero)
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        apply(appearance)
    }

    func apply(_ appearance: AppAppearance) {
        self.appearance = appearance
        let style = appearance.interfaceStyle
        window?.overrideUserInterfaceStyle = style
        // 同场景下可能还有独立的浮层窗口（弹窗 / 提示），一并统一。
        window?.windowScene?.windows.forEach { other in
            guard other !== window else { return }
            other.overrideUserInterfaceStyle = style
        }
    }
}

/// 原型字号层级：页面标题 27 / 卡片标题 17 / 大数值 32 / 指标值 25 / 正文 13.5 / 辅助 12.5 / 最小 11.5。
enum AppType {
    static let pageTitle = Font.system(size: 27, weight: .bold, design: .default)
    static let cardTitle = Font.system(size: 17, weight: .bold, design: .default)
    static let bigValue = Font.system(size: 32, weight: .bold, design: .default)
    static let metricValue = Font.system(size: 25, weight: .bold, design: .default)
    static let body = Font.system(size: 13.5)
    static let small = Font.system(size: 12.5)
    static let tiny = Font.system(size: 11.5)

    /// 全 App 大数值统一字体：SF Rounded + Bold，层级差异只体现在字号上。
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}

/// 所有页面统一使用系统分组背景：浅色为浅白灰、深色为纯黑。
enum AppScreenTone {
    case white
    case mint
    case lavender
    case peach

    var color: Color { Color(uiColor: .systemGroupedBackground) }
}

enum AppTheme {
    static let cornerRadius: CGFloat = 22
    static let cardShadow = AppPalette.cardShadow
    /// 原型卡片内边距 20px。
    static let cardPadding: CGFloat = 20
    /// 原型卡片左右外边距 20px。
    static let cardMargin: CGFloat = 20
}

struct AppCardModifier: ViewModifier {
    var padding: CGFloat = AppTheme.cardPadding
    var background: Color = Color(.secondarySystemGroupedBackground)

    func body(content: Content) -> some View {
        content
            .padding(padding)
            // 浅色模式下 secondarySystemGroupedBackground 即纯白，深色模式保留系统自适应。
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            // 原型卡片无描边，仅极浅阴影。
            .shadow(color: AppTheme.cardShadow, radius: 22, x: 0, y: 6)
    }
}

extension View {
    func appCard(
        padding: CGFloat = AppTheme.cardPadding,
        background: Color = Color(.secondarySystemGroupedBackground)
    ) -> some View {
        modifier(AppCardModifier(padding: padding, background: background))
    }

    /// 卡片滚动渐显。原先还叠加 scaleEffect：滚动时每张卡都要重新做几何计算
    /// 并重新光栅化 22pt 阴影，是长列表掉帧的主要来源。这里只保留纯合成的
    /// opacity 过渡，视觉上仍是「进入视口时轻微淡入」。
    func cardScrollEffect() -> some View {
        scrollTransition(.interactive, axis: .vertical) { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0.9)
        }
    }

}

/// 原型页面底色为模块纯色，不再叠加系统强调色的径向渐变。
struct AppScreenBackground: View {
    var tone: AppScreenTone = .white

    var body: some View {
        tone.color.ignoresSafeArea()
    }
}

struct AppSectionHeader: View {
    let title: String
    let icon: String
    let tint: Color
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: Circle())
            Text(title)
                .font(.headline)
            Spacer()
            if let trailing {
                trailing
            }
        }
    }
}

struct ChartCallout: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .font(index == 0 ? .caption2.weight(.semibold) : .caption2)
                    .foregroundStyle(index == 0 ? Color.primary : Color.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
    }
}

struct ChartCalloutOverlay: View {
    let lines: [String]
    let anchor: CGPoint
    let containerSize: CGSize

    var body: some View {
        let halfWidth: CGFloat = 80
        let x = min(
            max(anchor.x, halfWidth + 4),
            max(halfWidth + 4, containerSize.width - halfWidth - 4)
        )
        let y = anchor.y > 72 ? anchor.y - 46 : anchor.y + 46
        ChartCallout(lines: lines)
            .fixedSize()
            .position(
                x: x,
                y: min(max(y, 28), max(28, containerSize.height - 28))
            )
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}
