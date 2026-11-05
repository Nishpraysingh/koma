import Foundation
import AppKit

@MainActor
enum SampleLibrary {
    static func create(at contentURL: URL) throws -> [Book] {
        let examples: [(String, String, String, NSColor, NSColor)] = [
            ("The Quiet Orbit", "A small journey beyond the familiar.", "Science fiction", NSColor(red: 0.22, green: 0.26, blue: 0.62, alpha: 1), NSColor(red: 0.86, green: 0.49, blue: 0.34, alpha: 1)),
            ("After the Rain", "Finding a little wonder in ordinary days.", "Slice of life", NSColor(red: 0.16, green: 0.46, blue: 0.42, alpha: 1), NSColor(red: 0.78, green: 0.86, blue: 0.61, alpha: 1)),
            ("Paper Mountains", "Every path begins with a single page.", "Adventure", NSColor(red: 0.65, green: 0.34, blue: 0.29, alpha: 1), NSColor(red: 0.94, green: 0.77, blue: 0.52, alpha: 1)),
        ]
        return try examples.enumerated().map { index, entry in
            let (title, summary, tag, primary, accent) = entry
            let id = UUID(), base = "books/\(UUID().uuidString)"
            let baseURL = contentURL.appendingPathComponent(base, isDirectory: true)
            try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
            var chapters: [Chapter] = []
            for chapterIndex in 0..<2 {
                let chapterPath = base + "/chapter-\(chapterIndex + 1)"
                let chapterURL = contentURL.appendingPathComponent(chapterPath)
                try FileManager.default.createDirectory(at: chapterURL, withIntermediateDirectories: true)
                for pageIndex in 0..<5 {
                    let data = renderPage(title: title, subtitle: summary, index: index, chapter: chapterIndex, page: pageIndex, primary: primary, accent: accent, cover: false)
                    try data.write(to: chapterURL.appendingPathComponent(String(format: "%03d.png", pageIndex + 1)))
                }
                chapters.append(Chapter(title: chapterIndex == 0 ? "A beginning" : "Beyond the horizon", number: Double(chapterIndex + 1), relativePath: chapterPath, pageCount: 5))
            }
            let coverPath = base + "/cover.png"
            try renderPage(title: title, subtitle: summary, index: index, chapter: 0, page: 0, primary: primary, accent: accent, cover: true).write(to: contentURL.appendingPathComponent(coverPath))
            return Book(id: id, title: title, author: "Koma · Original sample", summary: summary + "\n\nAn original illustrated sample generated locally to help you explore the reader. These sample pages are included with the app, not downloaded manga.", coverPath: coverPath, categories: ["Samples"], tags: [tag, "Original sample"], chapters: chapters, source: "Sample")
        }
    }

    private static func renderPage(title: String, subtitle: String, index: Int, chapter: Int, page: Int, primary: NSColor, accent: NSColor, cover: Bool) -> Data {
        let size = NSSize(width: 720, height: 1020)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGradient(starting: primary, ending: primary.blended(withFraction: 0.55, of: .black)!)!.draw(in: NSRect(origin: .zero, size: size), angle: -90)
        let seed = page + chapter * 5
        accent.withAlphaComponent(0.10).setFill()
        NSBezierPath(ovalIn: NSRect(x: -180, y: 250, width: 900, height: 900)).fill()
        for i in 0..<38 {
            let x = CGFloat((i * 173 + seed * 43) % 700)
            let y = CGFloat((i * 277 + seed * 23) % 980)
            NSColor.white.withAlphaComponent(CGFloat((i % 3) + 1) * 0.12).setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: i % 3 == 0 ? 4 : 2, height: i % 3 == 0 ? 4 : 2)).fill()
        }
        accent.setFill()
        if index == 0 {
            NSBezierPath(ovalIn: NSRect(x: 174, y: 310, width: 370, height: 370)).fill()
            let ring = NSBezierPath(ovalIn: NSRect(x: 85, y: 425, width: 550, height: 120))
            ring.lineWidth = 16; NSColor.white.withAlphaComponent(0.5).setStroke(); ring.stroke()
            primary.withAlphaComponent(0.35).setFill()
            NSBezierPath(ovalIn: NSRect(x: 240, y: 490, width: 85, height: 85)).fill()
        } else if index == 1 {
            for i in 0..<6 {
                let path = NSBezierPath()
                path.move(to: NSPoint(x: -100, y: 150 + i * 70))
                path.curve(to: NSPoint(x: 850, y: 150 + i * 70), controlPoint1: NSPoint(x: 100, y: 600 + i * 20), controlPoint2: NSPoint(x: 430, y: -100 + i * 60))
                path.lineWidth = 28; accent.withAlphaComponent(CGFloat(i + 2) / 10).setStroke(); path.stroke()
            }
            accent.setFill(); NSBezierPath(ovalIn: NSRect(x: 470, y: 540, width: 110, height: 110)).fill()
        } else {
            for i in 0..<4 {
                let path = NSBezierPath(); let x = CGFloat(i * 190) - 100
                path.move(to: NSPoint(x: x, y: 250)); path.line(to: NSPoint(x: x + 230, y: CGFloat(650 - i * 65))); path.line(to: NSPoint(x: x + 500, y: 250)); path.close()
                accent.blended(withFraction: CGFloat(i) * 0.18, of: primary)!.setFill(); path.fill()
            }
        }
        let white = NSColor.white
        draw("ORIGINAL SAMPLE  /  KOMA", at: NSRect(x: 54, y: 926, width: 620, height: 24), size: 12, color: white.withAlphaComponent(0.65), weight: .medium)
        draw(title, at: NSRect(x: 54, y: 720, width: 610, height: 175), size: cover ? 60 : 48, color: white, weight: .bold)
        if cover {
            draw(subtitle, at: NSRect(x: 54, y: 145, width: 600, height: 70), size: 23, color: white.withAlphaComponent(0.85), weight: .regular)
            draw("VOL. 01", at: NSRect(x: 54, y: 60, width: 400, height: 30), size: 15, color: white.withAlphaComponent(0.55), weight: .semibold)
        } else {
            let lines = ["The world was quiet.\nA new page was waiting.", "A little curiosity\ncan take you a long way.", "Some journeys are best taken\none moment at a time.", "There is always something\nbeyond the familiar.", "And every ending\nis another beginning."]
            draw(lines[page], at: NSRect(x: 54, y: 115, width: 610, height: 105), size: 29, color: white.withAlphaComponent(0.90), weight: .medium)
            draw("CHAPTER \(chapter + 1)   ·   PAGE \(page + 1) / 5", at: NSRect(x: 54, y: 50, width: 600, height: 22), size: 12, color: white.withAlphaComponent(0.55), weight: .medium)
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return bitmap.representation(using: .png, properties: [:])!
    }

    private static func draw(_ text: String, at rect: NSRect, size: CGFloat, color: NSColor, weight: NSFont.Weight) {
        (text as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
    }
}
