// Draws the Keytide app icon with CoreGraphics and writes an .iconset directory for iconutil.
// Usage: swift scripts/make-icon.swift <out.iconset>
// One key with both legends: F (EN, cream) and А (RU, orange) share a key; a square wave is the tide.
// C-deep language inside: near-black field, cream lines, orange fills, no radius, no gradient. The container is
// Apple's grid (824 shape on a 1024 canvas, rounded): macOS 26+ jails full-bleed square icons in a grey plate.
import AppKit

let background = CGColor(srgbRed: 0x05 / 255, green: 0x08 / 255, blue: 0x0d / 255, alpha: 1)
let cream = CGColor(srgbRed: 1, green: 0xf5 / 255, blue: 0xb3 / 255, alpha: 1)
let orange = CGColor(srgbRed: 1, green: 0xb8 / 255, blue: 0x4d / 255, alpha: 1)
let line = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.13)

// Canvas 1024, origin top-left. The shape is 824 wide at offset 100; the artwork is laid out in a 1024 design
// square and scaled into it.
func draw(_ c: CGContext, detail: Bool) {
    c.addPath(CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185,
                     transform: nil))
    c.setFillColor(background); c.fillPath()
    c.translateBy(x: 100, y: 100); c.scaleBy(x: 824 / 1024, y: 824 / 1024)
    // Keycap: thick outer frame, hairline inner face.
    c.setStrokeColor(cream); c.setLineWidth(detail ? 34 : 48); c.setLineJoin(.miter)
    c.stroke(CGRect(x: 212, y: 150, width: 600, height: 600))
    if detail {
        c.setStrokeColor(line); c.setLineWidth(8)
        c.stroke(CGRect(x: 272, y: 210, width: 480, height: 480))
    }
    // F, top left of the face.
    c.setFillColor(cream)
    c.fill(CGRect(x: 304, y: 242, width: 50, height: 240))
    c.fill(CGRect(x: 304, y: 242, width: 170, height: 50))
    c.fill(CGRect(x: 304, y: 342, width: 130, height: 44))
    // А (block form), bottom right of the face.
    c.setFillColor(orange)
    c.fill(CGRect(x: 536, y: 418, width: 50, height: 242))
    c.fill(CGRect(x: 678, y: 418, width: 50, height: 242))
    c.fill(CGRect(x: 536, y: 418, width: 192, height: 50))
    c.fill(CGRect(x: 536, y: 528, width: 192, height: 44))
    if detail {
        // Tide: a square wave under the key, symmetric around the centre.
        c.setStrokeColor(orange); c.setLineWidth(26); c.setLineJoin(.miter); c.setLineCap(.butt)
        let low = 892.0, high = 832.0
        c.move(to: CGPoint(x: 152, y: low))
        var y = low
        for x in stride(from: 212.0, through: 812.0, by: 120) {
            c.addLine(to: CGPoint(x: x, y: y))
            y = y == low ? high : low
            c.addLine(to: CGPoint(x: x, y: y))
        }
        c.addLine(to: CGPoint(x: 872, y: y))
        c.strokePath()
    }
}

func render(_ pixels: Int) -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let c = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = CGFloat(pixels) / 1024
    c.translateBy(x: 0, y: CGFloat(pixels)); c.scaleBy(x: scale, y: -scale)
    // Small sizes keep only the key and its legends: hairlines and the wave would turn into noise.
    draw(c, detail: pixels >= 64)
    return NSBitmapImageRep(cgImage: c.makeImage()!).representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try render(points * scale).write(to: out.appendingPathComponent(name))
    }
}
