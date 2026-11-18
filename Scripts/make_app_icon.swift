#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let supersample = 4
let canvas = size * supersample
let space = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255
    let g = CGFloat((hex >> 8) & 0xFF) / 255
    let b = CGFloat(hex & 0xFF) / 255
    return CGColor(colorSpace: space, components: [r, g, b, alpha])!
}

guard let ctx = CGContext(
    data: nil,
    width: canvas,
    height: canvas,
    bitsPerComponent: 8,
    bytesPerRow: canvas * 4,
    space: space,
    bitmapInfo: bitmapInfo
) else {
    fatalError("无法创建绘图上下文")
}

ctx.setAllowsAntialiasing(true)
ctx.interpolationQuality = .high

// ============================================================
// 背景：Apple 健康风 —— 鲜活玫红对角渐变（底左深、顶右亮）
// ============================================================
let background = CGGradient(
    colorsSpace: space,
    colors: [rgb(0xC2185B), rgb(0xFF2D55), rgb(0xFF7E9A)] as CFArray,
    locations: [0, 0.55, 1]
)!
ctx.drawLinearGradient(
    background,
    start: CGPoint(x: 0, y: 0),
    end: CGPoint(x: CGFloat(canvas), y: CGFloat(canvas)),
    options: [.drawsAfterEndLocation, .drawsBeforeStartLocation]
)

// 顶部柔光（玻璃质感顶光）
let topSheen = CGGradient(
    colorsSpace: space,
    colors: [rgb(0xFFFFFF, alpha: 0.16), rgb(0xFFFFFF, alpha: 0.0)] as CFArray,
    locations: [0, 1]
)!
ctx.drawRadialGradient(
    topSheen,
    startCenter: CGPoint(x: CGFloat(canvas) * 0.5, y: CGFloat(canvas) * 0.92),
    startRadius: 0,
    endCenter: CGPoint(x: CGFloat(canvas) * 0.5, y: CGFloat(canvas) * 0.92),
    endRadius: CGFloat(canvas) * 0.55,
    options: []
)

// 底部微暗（增加纵深）
let bottomShade = CGGradient(
    colorsSpace: space,
    colors: [rgb(0x000000, alpha: 0.0), rgb(0x000000, alpha: 0.12)] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    bottomShade,
    start: CGPoint(x: 0, y: CGFloat(canvas) * 0.75),
    end: CGPoint(x: 0, y: 0),
    options: []
)

let center = CGPoint(x: CGFloat(canvas) / 2, y: CGFloat(canvas) / 2)
// 心形视觉重心下移一点点（心尖偏重，bbox 居中会显得偏高）
let heartCenterY = center.y - CGFloat(canvas) * 0.020

// ============================================================
// 标准心形路径（参数方程，严格对称）
// ============================================================
let samples = 240
var raw: [CGPoint] = []
for i in 0...samples {
    let t = Double(i) / Double(samples) * 2 * Double.pi
    let s = sin(t)
    let mx = 16 * s * s * s
    let my = 13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)
    raw.append(CGPoint(x: mx, y: my))
}
let xs = raw.map { $0.x }
let ys = raw.map { $0.y }
let minX = xs.min()!, maxX = xs.max()!
let minY = ys.min()!, maxY = ys.max()!
let bw = maxX - minX
let bh = maxY - minY
let scale = (CGFloat(canvas) * 0.56) / CGFloat(bw)
let cxShape = (minX + maxX) / 2
let cyShape = (minY + maxY) / 2
let path = CGMutablePath()
for (i, p) in raw.enumerated() {
    let sx = center.x + (p.x - cxShape) * scale
    let sy = heartCenterY + (p.y - cyShape) * scale
    if i == 0 { path.move(to: CGPoint(x: sx, y: sy)) }
    else { path.addLine(to: CGPoint(x: sx, y: sy)) }
}
path.closeSubpath()
let heart = path

let heartRect = CGRect(
    x: center.x - bw * scale / 2,
    y: heartCenterY - bh * scale / 2,
    width: bw * scale,
    height: bh * scale
)

// ============================================================
// 柔和投影：先把心形剪影铺一层深色（带阴影），再叠白渐变
// ============================================================
ctx.saveGState()
ctx.setShadow(
    offset: CGSize(width: 0, height: -CGFloat(canvas) * 0.016),
    blur: CGFloat(canvas) * 0.030,
    color: rgb(0x000000, alpha: 0.34)
)
ctx.addPath(heart)
ctx.setFillColor(rgb(0x000000))
ctx.fillPath()
ctx.restoreGState()

// 纯白心形 + 极轻体积极光（垂直白→近白灰，制造圆润体积）
ctx.saveGState()
ctx.addPath(heart)
ctx.clip()
let heartFill = CGGradient(
    colorsSpace: space,
    colors: [rgb(0xFFFFFF), rgb(0xF2F2F7)] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    heartFill,
    start: CGPoint(x: 0, y: heartRect.minY),
    end: CGPoint(x: 0, y: heartRect.maxY),
    options: []
)
ctx.restoreGState()

// ============================================================
// 输出 1024
// ============================================================
guard let rendered = ctx.makeImage() else {
    fatalError("无法生成图像")
}

guard let outputContext = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: size * 4,
    space: space,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    fatalError("无法创建输出上下文")
}
outputContext.interpolationQuality = .high
outputContext.draw(rendered, in: CGRect(x: 0, y: 0, width: size, height: size))
guard let output = outputContext.makeImage() else {
    fatalError("无法缩放图像")
}

let outputPath = FileManager.default.currentDirectoryPath
    + "/Healthy/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
try FileManager.default.createDirectory(
    atPath: (outputPath as NSString).deletingLastPathComponent,
    withIntermediateDirectories: true
)
guard let destination = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: outputPath) as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    fatalError("无法创建 PNG 输出")
}
CGImageDestinationAddImage(destination, output, nil)
guard CGImageDestinationFinalize(destination) else {
    fatalError("无法写入 PNG")
}
print("已生成 \(outputPath)")
