import SwiftUI

/// 咖啡豆轮廓：两端略尖的椭圆，中央有一条 S 形沟纹。
/// fixedRect 与玻璃杯同理，保证裁剪路径与内容共用同一坐标系。
struct CoffeeBeanShape: Shape {
    var fixedRect: CGRect? = nil

    func path(in rect: CGRect) -> Path {
        let bounds = fixedRect ?? rect
        let w = bounds.width
        let h = bounds.height
        var path = Path()
        path.move(to: CGPoint(x: w * 0.5, y: 0))
        path.addCurve(
            to: CGPoint(x: w, y: h * 0.5),
            control1: CGPoint(x: w * 0.90, y: h * 0.02),
            control2: CGPoint(x: w, y: h * 0.24)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.5, y: h),
            control1: CGPoint(x: w, y: h * 0.76),
            control2: CGPoint(x: w * 0.90, y: h * 0.98)
        )
        path.addCurve(
            to: CGPoint(x: 0, y: h * 0.5),
            control1: CGPoint(x: w * 0.10, y: h * 0.98),
            control2: CGPoint(x: 0, y: h * 0.76)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.5, y: 0),
            control1: CGPoint(x: 0, y: h * 0.24),
            control2: CGPoint(x: w * 0.10, y: h * 0.02)
        )
        path.closeSubpath()
        return path.applying(CGAffineTransform(translationX: bounds.minX, y: bounds.minY))
    }
}

/// 咖啡豆中间的 S 形沟纹。
struct CoffeeBeanCreaseShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: w * 0.54, y: h * 0.05))
        path.addCurve(
            to: CGPoint(x: w * 0.46, y: h * 0.95),
            control1: CGPoint(x: w * 0.22, y: h * 0.34),
            control2: CGPoint(x: w * 0.78, y: h * 0.66)
        )
        return path
    }
}

/// 咖啡因页主图：一个大咖啡豆容器，按完成度从下往上填进一颗颗小咖啡豆。
/// 颜色参数默认对应浅色页面；深色卡片复用时传入白色低透明度即可。
struct CoffeeBeanFillView: View {
    let progress: Double
    let tint: Color
    var emptyColor: Color = Color(red: 0.910, green: 0.902, blue: 0.890)
    var emptyCrease: Color = Color.gray.opacity(0.22)
    var trackColor: Color = Color(uiColor: .tertiarySystemFill)
    var creaseColor: Color = Color.brown.opacity(0.22)

    private let columns = 5
    private let rows = 7

    var body: some View {
        GeometryReader { geo in
            let bounds = CGRect(origin: .zero, size: geo.size)
            let cellWidth = bounds.width / CGFloat(columns)
            let cellHeight = bounds.height / CGFloat(rows)
            let level = min(max(progress, 0), 1)
            let fillHeight = bounds.height * level

            ZStack {
                CoffeeBeanShape(fixedRect: bounds)
                    .fill(trackColor)
                // 空豆层：结构与 progress 无关，SwiftUI 只创建一次，不随动画重建路径。
                beans(filled: false, bounds: bounds, cellWidth: cellWidth, cellHeight: cellHeight)
                // 满豆层：整层固定，只用下方增长的矩形做 mask。
                // 原先每个豆子的 filled 布尔挂在 progress 上，动画期间 70 个自定义
                // Shape 逐帧重建，打卡瞬间明显掉帧；现在动画只改这个简单矩形的高度。
                beans(filled: true, bounds: bounds, cellWidth: cellWidth, cellHeight: cellHeight)
                    .mask(alignment: .bottom) {
                        Rectangle()
                            .frame(height: fillHeight)
                            .animation(.easeInOut(duration: 0.4), value: progress)
                    }
            }
            .clipShape(CoffeeBeanShape(fixedRect: bounds))
            .overlay {
                CoffeeBeanCreaseShape()
                    .stroke(creaseColor, lineWidth: max(3, bounds.width * 0.022))
                    .clipShape(CoffeeBeanShape(fixedRect: bounds))
            }
        }
    }

    /// 一次性生成 35 颗豆子；filled 只决定配色，不参与动画插值。
    private func beans(
        filled: Bool,
        bounds: CGRect,
        cellWidth: CGFloat,
        cellHeight: CGFloat
    ) -> some View {
        ForEach(0..<(columns * rows), id: \.self) { index in
            let row = index / columns
            let column = index % columns
            let center = CGPoint(
                x: (CGFloat(column) + 0.5) * cellWidth,
                y: (CGFloat(row) + 0.5) * cellHeight
            )
            bean(filled: filled, tint: tint)
                .frame(width: cellWidth * 0.86, height: cellHeight * 0.84)
                .position(center)
        }
    }

    private func bean(filled: Bool, tint: Color) -> some View {
        ZStack {
            CoffeeBeanShape()
                .fill(filled ? tint : emptyColor)
            CoffeeBeanCreaseShape()
                .stroke(
                    filled ? Color.white.opacity(0.35) : emptyCrease,
                    lineWidth: 1.4
                )
        }
    }
}
