// Generates the default DSH app icon: a deep-blue gradient with a white "DSH" wordmark
// (original geometric design, no branded assets).
// Usage: swift tools/gen-icon.swift <output.png>
import AppKit

let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Deep-blue diagonal gradient background (macOS applies the standard rounded-rect icon mask)
if let gradient = NSGradient(
    colors: [
        NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.42, alpha: 1),
        NSColor(calibratedRed: 0.04, green: 0.06, blue: 0.16, alpha: 1),
    ]
) {
    gradient.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -60)
}

// White heavy "DSH" centered
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
    fputs("icon generation failed\n", stderr)
    exit(1)
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/dsh-icon.png"
try! png.write(to: URL(fileURLWithPath: out))
print("✅ icon written: \(out)")
