import AppKit
import VigilCore

/// The eye glyphs, drawn from the same paths as the design mockup on an 18 × 16 point grid
/// with the origin at the top left.
enum Glyph {
    static let size = NSSize(width: 18, height: 16)

    /// The menu bar picture for a state. A template image takes the menu bar's own colour.
    static func statusImage(_ kind: IconKind) -> NSImage {
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.set()
            draw(kind, lineWidth: 1.5)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = kind.label
        return image
    }

    /// Strokes and fills the glyph in the current colour.
    static func draw(_ kind: IconKind, lineWidth: CGFloat) {
        switch kind {
        case .awake: openEye(lineWidth)
        case .asleep: closedEye(lineWidth)
        case .lidIdle: laptop(lineWidth, eyeOpen: false)
        case .lidAwake: laptop(lineWidth, eyeOpen: true)
        }
    }

    private static func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: y) }

    private static func stroke(_ path: NSBezierPath, _ lineWidth: CGFloat) {
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private static func dot(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) {
        NSBezierPath(ovalIn: NSRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)).fill()
    }

    private static func openEye(_ lineWidth: CGFloat) {
        let lid = NSBezierPath()
        lid.move(to: point(1.5, 8))
        lid.curve(to: point(9, 3), controlPoint1: point(3.4, 4.6), controlPoint2: point(6, 3))
        lid.curve(to: point(16.5, 8), controlPoint1: point(12, 3), controlPoint2: point(14.6, 4.6))
        lid.curve(to: point(9, 13), controlPoint1: point(14.6, 11.4), controlPoint2: point(12, 13))
        lid.curve(to: point(1.5, 8), controlPoint1: point(6, 13), controlPoint2: point(3.4, 11.4))
        lid.close()
        stroke(lid, lineWidth)
        dot(9, 8, 2.2)
    }

    private static func closedEye(_ lineWidth: CGFloat) {
        let lid = NSBezierPath()
        lid.move(to: point(1.5, 6.5))
        lid.curve(to: point(9, 10.5), controlPoint1: point(3.4, 9.1), controlPoint2: point(6, 10.5))
        lid.curve(to: point(16.5, 6.5), controlPoint1: point(12, 10.5), controlPoint2: point(14.6, 9.1))
        lid.move(to: point(4.4, 9.4))
        lid.line(to: point(3.3, 11.2))
        lid.move(to: point(9, 10.5))
        lid.line(to: point(9, 12.6))
        lid.move(to: point(13.6, 9.4))
        lid.line(to: point(14.7, 11.2))
        stroke(lid, lineWidth)
    }

    private static func laptop(_ lineWidth: CGFloat, eyeOpen: Bool) {
        let body = NSBezierPath(roundedRect: NSRect(x: 3, y: 2.5, width: 12, height: 8.5), xRadius: 1.2, yRadius: 1.2)
        body.move(to: point(1.5, 13.5))
        body.line(to: point(16.5, 13.5))
        stroke(body, lineWidth)

        let eye = NSBezierPath()
        if eyeOpen {
            eye.move(to: point(5.8, 6.8))
            eye.curve(to: point(9, 5), controlPoint1: point(6.7, 5.6), controlPoint2: point(7.8, 5))
            eye.curve(to: point(12.2, 6.8), controlPoint1: point(10.2, 5), controlPoint2: point(11.3, 5.6))
            eye.curve(to: point(9, 8.6), controlPoint1: point(11.3, 8), controlPoint2: point(10.2, 8.6))
            eye.curve(to: point(5.8, 6.8), controlPoint1: point(7.8, 8.6), controlPoint2: point(6.7, 8))
            eye.close()
            stroke(eye, lineWidth * 0.8)
            dot(9, 6.8, 0.9)
        } else {
            eye.move(to: point(6.2, 6.2))
            eye.curve(to: point(9, 7.7), controlPoint1: point(7, 7.2), controlPoint2: point(7.9, 7.7))
            eye.curve(to: point(11.8, 6.2), controlPoint1: point(10.1, 7.7), controlPoint2: point(11, 7.2))
            stroke(eye, lineWidth * 0.8)
        }
    }
}

/// Drawing to files, for the build script (the app icon) and for checking the glyphs by eye.
enum Artwork {
    /// Writes a macOS `.iconset` folder: an amber open eye on a night-blue tile.
    static func writeIconset(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = points * scale
                let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
                try png(pixels: pixels, drawAppIcon).write(to: folder.appendingPathComponent(name))
            }
        }
    }

    /// Writes every menu bar glyph at 1×, 2× and 3×, black on transparent and white on dark grey.
    static func writeGlyphs(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for kind in IconKind.allCases {
            for scale in [1, 2, 3] {
                for dark in [false, true] {
                    let data = try png(width: 18 * scale, height: 16 * scale) { rect in
                        if dark {
                            NSColor(white: 0.17, alpha: 1).setFill()
                            rect.fill()
                        }
                        let transform = NSAffineTransform()
                        transform.translateX(by: 0, yBy: rect.height)
                        transform.scaleX(by: CGFloat(scale), yBy: -CGFloat(scale))
                        transform.concat()
                        (dark ? NSColor.white : NSColor.black).set()
                        Glyph.draw(kind, lineWidth: 1.5)
                    }
                    let name = "\(kind)@\(scale)x\(dark ? "-dark" : "").png"
                    try data.write(to: folder.appendingPathComponent(name))
                }
            }
        }
    }

    /// Apple's icon grid at 1024 pixels: an 824-pixel tile with a 100-pixel margin.
    private static func drawAppIcon(_ rect: NSRect) {
        let unit = rect.width / 1024
        let tile = NSBezierPath(
            roundedRect: NSRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit),
            xRadius: 185 * unit, yRadius: 185 * unit)
        NSColor(srgbRed: 0x1F / 255, green: 0x2A / 255, blue: 0x44 / 255, alpha: 1).setFill()
        tile.fill()

        // The 18 × 16 glyph scaled to 540 pixels wide, centred, top-left origin.
        let scale = 540 * unit / Glyph.size.width
        let transform = NSAffineTransform()
        transform.translateX(
            by: (rect.width - Glyph.size.width * scale) / 2, yBy: (rect.height + Glyph.size.height * scale) / 2)
        transform.scaleX(by: scale, yBy: -scale)
        transform.concat()
        NSColor(srgbRed: 0xF2 / 255, green: 0xA3 / 255, blue: 0x3A / 255, alpha: 1).set()
        Glyph.draw(.awake, lineWidth: 1.1)
    }

    private static func png(pixels: Int, _ draw: (NSRect) -> Void) throws -> Data {
        try png(width: pixels, height: pixels, draw)
    }

    private static func png(width: Int, height: Int, _ draw: (NSRect) -> Void) throws -> Data {
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { throw CocoaError(.fileWriteUnknown) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        return data
    }
}
