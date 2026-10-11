// Draws the dmg window background (640x440 pt) in the C-deep language and writes background.png + background@2x.png.
// Usage: swift scripts/make-dmg-background.swift <out dir>
// then:  tiffutil -cathidpicheck <out>/background.png <out>/background@2x.png -out Resources/dmg/background.tiff
// Finder draws the two icons and their names on top: icon centres and label plates must match scripts/make-dmg-layout.sh.
// Finder colours those names by the system appearance, not by this image, so they sit on mid-grey plates that keep
// both black (light mode) and white (dark mode) text at about 4.5:1.
import AppKit

let width: CGFloat = 640, height: CGFloat = 440
let background = NSColor(srgbRed: 0x05 / 255, green: 0x08 / 255, blue: 0x0d / 255, alpha: 1)
let panel = NSColor(srgbRed: 0x08 / 255, green: 0x0b / 255, blue: 0x11 / 255, alpha: 1)
let cream = NSColor(srgbRed: 1, green: 0xf5 / 255, blue: 0xb3 / 255, alpha: 1)
let orange = NSColor(srgbRed: 1, green: 0xb8 / 255, blue: 0x4d / 255, alpha: 1)
let ink = NSColor(srgbRed: 0x0a / 255, green: 0x07 / 255, blue: 0x03 / 255, alpha: 1)
let line = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.13)
let text = NSColor(srgbRed: 0xe8 / 255, green: 0xe8 / 255, blue: 0xe8 / 255, alpha: 1)
let dim = NSColor(srgbRed: 0x8e / 255, green: 0x8e / 255, blue: 0x8e / 255, alpha: 1)
let plate = NSColor(srgbRed: 0x76 / 255, green: 0x76 / 255, blue: 0x76 / 255, alpha: 1)

// Shared with make-dmg-layout.sh: icon centres and the label plates under them.
let iconCentres = [CGPoint(x: 136, y: 150), CGPoint(x: 504, y: 150)]
let plateSize = CGSize(width: 132, height: 20), plateTop: CGFloat = 212

let display = NSFont.systemFont(ofSize: 14, weight: .bold, width: .condensed)
let mono = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .medium)
let prose = NSFont.systemFont(ofSize: 11)
let proseRU = NSFont.systemFont(ofSize: 10.5)

func write(_ string: String, _ font: NSFont, _ color: NSColor, at point: CGPoint, align: NSTextAlignment = .left,
           kern: CGFloat = 0) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: kern]
    let size = (string as NSString).size(withAttributes: attributes)
    let x = align == .right ? point.x - size.width : align == .center ? point.x - size.width / 2 : point.x
    (string as NSString).draw(at: CGPoint(x: x, y: point.y - size.height / 2), withAttributes: attributes)
}

func paragraph(_ string: String, _ font: NSFont, _ color: NSColor, in rect: CGRect) -> CGFloat {
    let style = NSMutableParagraphStyle(); style.lineSpacing = 2
    let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color,
                                                                      .paragraphStyle: style])
    let used = attributed.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin, .usesFontLeading])
    attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    return ceil(used.height)
}

func frame(_ rect: CGRect) {
    line.setStroke()
    let path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5)); path.lineWidth = 1; path.stroke()
}

func rule(_ y: CGFloat, from x0: CGFloat, to x1: CGFloat) {
    line.setFill(); NSBezierPath(rect: CGRect(x: x0, y: y, width: x1 - x0, height: 1)).fill()
}

// A module: hairline frame, header with /NN in orange, name, rule and a mono tag on the right.
func module(_ rect: CGRect, number: String?, name: String, tag: String) {
    panel.setFill(); NSBezierPath(rect: rect).fill()
    frame(rect)
    rule(rect.minY + 22, from: rect.minX, to: rect.maxX)
    var x = rect.minX + 10
    if let number {
        write(number, display, orange, at: CGPoint(x: x, y: rect.minY + 11.5))
        x += (number as NSString).size(withAttributes: [.font: display]).width + 6
    }
    write(name, display, text, at: CGPoint(x: x, y: rect.minY + 11.5))
    write(tag, mono, dim, at: CGPoint(x: rect.maxX - 10, y: rect.minY + 11.5), align: .right, kern: 0.6)
}

func cross(_ p: CGPoint) {
    cream.withAlphaComponent(0.55).setFill()
    NSBezierPath(rect: CGRect(x: p.x - 4, y: p.y - 0.5, width: 9, height: 1)).fill()
    NSBezierPath(rect: CGRect(x: p.x - 0.5, y: p.y - 4, width: 1, height: 9)).fill()
}

func draw() {
    background.setFill(); NSBezierPath(rect: CGRect(x: 0, y: 0, width: width, height: height)).fill()

    // Machine line.
    write("KEYTIDE // INSTALL", mono, cream, at: CGPoint(x: 16, y: 16), kern: 0.8)
    write("RU/EN LAYOUT SWITCHER · MACOS 13+ · APPLE SILICON", mono, dim, at: CGPoint(x: 624, y: 16), align: .right,
          kern: 0.6)
    rule(30, from: 0, to: width)

    // Drag row: source, arrow, target, docked frame to frame.
    let top: CGFloat = 46, bottom: CGFloat = 262
    module(CGRect(x: 16, y: top, width: 240, height: bottom - top), number: "/01", name: "KEYTIDE.APP", tag: "SOURCE")
    module(CGRect(x: 255, y: top, width: 130, height: bottom - top), number: nil, name: "", tag: "")
    module(CGRect(x: 384, y: top, width: 240, height: bottom - top), number: "/02", name: "APPLICATIONS", tag: "TARGET")
    for centre in iconCentres {
        plate.setFill()
        NSBezierPath(rect: CGRect(x: centre.x - plateSize.width / 2, y: plateTop, width: plateSize.width,
                                  height: plateSize.height)).fill()
    }
    let arrowY = iconCentres[0].y
    orange.setFill()
    NSBezierPath(rect: CGRect(x: 272, y: arrowY - 1.5, width: 82, height: 3)).fill()
    let head = NSBezierPath()
    head.move(to: CGPoint(x: 368, y: arrowY)); head.line(to: CGPoint(x: 352, y: arrowY - 8))
    head.line(to: CGPoint(x: 352, y: arrowY + 8)); head.close(); head.fill()
    write("DRAG", mono, cream, at: CGPoint(x: 320, y: arrowY - 18), align: .center, kern: 1.2)
    write("ПЕРЕТАЩИТЕ", mono, dim, at: CGPoint(x: 320, y: arrowY + 18), align: .center, kern: 0.6)

    // First launch.
    let lower: CGFloat = 278, end: CGFloat = 400
    let launch = CGRect(x: 16, y: lower, width: 305, height: end - lower)
    let access = CGRect(x: 320, y: lower, width: 304, height: end - lower)
    module(launch, number: "/03", name: "FIRST LAUNCH", tag: "NOT NOTARIZED")
    module(access, number: "/04", name: "ACCESS", tag: "ACCESSIBILITY")
    for (rect, en, ru) in [
        (launch, "If macOS refuses to open Keytide: System Settings > Privacy & Security > Open Anyway.",
         "Если macOS не открывает Keytide: Системные настройки > Конфиденциальность и безопасность > Всё равно открыть."),
        (access, "Allow Keytide in System Settings > Privacy & Security > Accessibility.",
         "Разрешите Keytide: Системные настройки > Конфиденциальность и безопасность > Универсальный доступ."),
    ] {
        let body = CGRect(x: rect.minX + 12, y: rect.minY + 32, width: rect.width - 24, height: rect.height - 40)
        let used = paragraph(en, prose, text, in: body)
        _ = paragraph(ru, proseRU, dim, in: CGRect(x: body.minX, y: body.minY + used + 6, width: body.width,
                                                   height: body.height - used - 6))
    }

    for x in [16.0, 255, 385, 624] { cross(CGPoint(x: x, y: top)); cross(CGPoint(x: x, y: bottom)) }
    for x in [16.0, 320.5, 624] { cross(CGPoint(x: x, y: lower)); cross(CGPoint(x: x, y: end)) }

    // Footer and hazard.
    write("GITHUB.COM/FIREXRWT/KEYTIDE", mono, dim, at: CGPoint(x: 16, y: 415), kern: 0.6)
    write("MIT · NO TELEMETRY", mono, dim, at: CGPoint(x: 624, y: 415), align: .right, kern: 0.6)
    let hazard = CGRect(x: 0, y: 430, width: width, height: 10)
    orange.setFill(); NSBezierPath(rect: hazard).fill()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: hazard).addClip()
    ink.setFill()
    for x in stride(from: -20.0, to: width + 20, by: 16) {
        let bar = NSBezierPath()
        bar.move(to: CGPoint(x: x, y: hazard.maxY)); bar.line(to: CGPoint(x: x + 8, y: hazard.maxY))
        bar.line(to: CGPoint(x: x + 18, y: hazard.minY)); bar.line(to: CGPoint(x: x + 10, y: hazard.minY)); bar.close()
        bar.fill()
    }
    NSGraphicsContext.restoreGraphicsState()
}

func render(scale: CGFloat) -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let c = CGContext(data: nil, width: Int(width * scale), height: Int(height * scale), bitsPerComponent: 8,
                      bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.translateBy(x: 0, y: height * scale); c.scaleBy(x: scale, y: -scale)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: true)
    draw()
    NSGraphicsContext.current = nil
    let rep = NSBitmapImageRep(cgImage: c.makeImage()!)
    // Point size on the image: Finder shows the 2x rep at 640x440 points on Retina screens.
    rep.size = NSSize(width: width, height: height)
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
try render(scale: 1).write(to: out.appendingPathComponent("background.png"))
try render(scale: 2).write(to: out.appendingPathComponent("background@2x.png"))
