// Renders the minimalist app icon: three text lines and a caret on a dark
// macOS-style rounded square. Usage: swift scripts/make-icon.swift OUT.png
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon-1024.png"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Top-left origin so coordinates read like the design.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

// Background squircle on the macOS icon grid (824pt body, 100pt margin).
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: color(0x000000, 0.3))
ctx.addPath(bodyPath)
ctx.setFillColor(color(0x1C1C1E))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
let background = CGGradient(colorsSpace: space, colors: [color(0x2C2C2E), color(0x161618)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(background, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
ctx.restoreGState()

// Three lines of text, then a caret: the whole idea of a text editor.
func bar(_ rect: CGRect, _ fill: CGColor) {
    let radius = min(rect.width, rect.height) / 2
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(fill)
    ctx.fillPath()
}

let left: CGFloat = 272
let thickness: CGFloat = 56
let gap: CGFloat = 64
let top: CGFloat = 512 - (thickness * 3 + gap * 2) / 2

bar(CGRect(x: left, y: top, width: 480, height: thickness), color(0xF5F5F7))
bar(CGRect(x: left, y: top + thickness + gap, width: 360, height: thickness), color(0xF5F5F7, 0.75))
let lastY = top + 2 * (thickness + gap)
bar(CGRect(x: left, y: lastY, width: 220, height: thickness), color(0xF5F5F7, 0.5))
bar(CGRect(x: left + 220 + 40, y: lastY - 34, width: 28, height: thickness + 68), color(0x0A84FF))

let image = ctx.makeImage()!
try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
