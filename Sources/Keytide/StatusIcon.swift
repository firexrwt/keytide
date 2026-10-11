import AppKit

enum StatusIcon {
    // The app icon's key with F and А as an 18 pt template: macOS tints it for light and dark menu bars.
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            guard let c = NSGraphicsContext.current?.cgContext else { return false }
            c.setStrokeColor(.black); c.setFillColor(.black)
            c.setLineWidth(1.5); c.stroke(CGRect(x: 1.75, y: 1.75, width: 14.5, height: 14.5))
            c.fill([CGRect(x: 4.5, y: 4.5, width: 1.5, height: 6), CGRect(x: 4.5, y: 4.5, width: 4, height: 1.5),
                    CGRect(x: 4.5, y: 7, width: 3, height: 1.25),
                    CGRect(x: 9.5, y: 7.5, width: 1.5, height: 6), CGRect(x: 12, y: 7.5, width: 1.5, height: 6),
                    CGRect(x: 9.5, y: 7.5, width: 4, height: 1.5), CGRect(x: 9.5, y: 10.5, width: 4, height: 1.25)])
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Keytide"
        return image
    }()
}
