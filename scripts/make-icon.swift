import AppKit
import Foundation

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let factor = CGFloat(pixels) / 1024
        let transform = NSAffineTransform()
        transform.scale(by: factor)
        transform.concat()
        NSColor(red: 0.85, green: 0.32, blue: 0.17, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 50, y: 50, width: 924, height: 924), xRadius: 205, yRadius: 205).fill()
        NSColor(red: 0.97, green: 0.92, blue: 0.83, alpha: 1).setFill()
        let left = NSBezierPath(); left.move(to: NSPoint(x: 225, y: 300)); left.line(to: NSPoint(x: 225, y: 755)); left.curve(to: NSPoint(x: 487, y: 700), controlPoint1: NSPoint(x: 325, y: 780), controlPoint2: NSPoint(x: 430, y: 765)); left.line(to: NSPoint(x: 487, y: 250)); left.curve(to: NSPoint(x: 225, y: 300), controlPoint1: NSPoint(x: 415, y: 315), controlPoint2: NSPoint(x: 320, y: 330)); left.close(); left.fill()
        let right = NSBezierPath(); right.move(to: NSPoint(x: 799, y: 300)); right.line(to: NSPoint(x: 799, y: 755)); right.curve(to: NSPoint(x: 537, y: 700), controlPoint1: NSPoint(x: 699, y: 780), controlPoint2: NSPoint(x: 594, y: 765)); right.line(to: NSPoint(x: 537, y: 250)); right.curve(to: NSPoint(x: 799, y: 300), controlPoint1: NSPoint(x: 609, y: 315), controlPoint2: NSPoint(x: 704, y: 330)); right.close(); right.fill()
        NSColor(red: 0.85, green: 0.32, blue: 0.17, alpha: 0.3).setStroke()
        for y in [450, 520, 590] {
            let line = NSBezierPath(); line.move(to: NSPoint(x: 285, y: y + 30)); line.line(to: NSPoint(x: 430, y: y)); line.lineWidth = 18; line.lineCapStyle = .round; line.stroke()
        }
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let data = rep.representation(using: .png, properties: [:])!
        try data.write(to: destination.appendingPathComponent("icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
    }
}
