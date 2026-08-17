// 生成 DSH 默认应用图标：深蓝渐变 + 白色 "DSH" 字标（原创几何设计，无品牌素材）
// 用法：swift tools/gen-icon.swift <输出.png>
import AppKit

let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// 深蓝对角渐变背景（大图按整幅绘制；macOS 会自动套用系统圆角图标形状）
if let gradient = NSGradient(
    colors: [
        NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.42, alpha: 1),
        NSColor(calibratedRed: 0.04, green: 0.06, blue: 0.16, alpha: 1),
    ]
) {
    gradient.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -60)
}

// 白色粗体 "DSH" 居中
let text = NSAttributedString(
    string: "DSH",
    attributes: [
        .font: NSFont.systemFont(ofSize: 430, weight: .heavy),
        .foregroundColor: NSColor.white,
    ]
)
let textSize = text.size()
text.draw(at: NSPoint(
    x: (CGFloat(size) - textSize.width) / 2,
    y: (CGFloat(size) - textSize.height) / 2
))

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
else {
    fputs("图标生成失败\n", stderr)
    exit(1)
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/dsh-icon.png"
try! png.write(to: URL(fileURLWithPath: out))
print("✅ 图标已生成: \(out)")
