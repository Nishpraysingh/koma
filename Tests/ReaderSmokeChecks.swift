import AppKit
import Foundation
import PDFKit

@MainActor
func runReaderSmokeChecks() async throws {
    func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw NSError(domain: "ReaderSmokeChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    func png(_ width: Int, _ height: Int) throws -> Data {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32),
              let bytes = bitmap.bitmapData else { throw ReaderContentError.decodingFailed }
        memset(bytes, 255, width * height * 4)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw ReaderContentError.decodingFailed }
        return data
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("koma-reader-smoke-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("pages")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try png(100, 200).write(to: folder.appendingPathComponent("10.png"))
    try png(200, 100).write(to: folder.appendingPathComponent("2.png"))
    try Data("ignored".utf8).write(to: folder.appendingPathComponent("ComicInfo.xml"))
    let images = try await ContentLoader.shared.load(folder)
    try check(images.pageCount == 2, "Image page count")
    try check(images.images.map(\.lastPathComponent) == ["2.png", "10.png"], "Natural page order")
    try check(abs(images.aspectRatio(at: 0) - 2) < 0.01, "Image aspect ratio")
    let rendered = try await ContentLoader.shared.image(in: images, page: 0, maxPixel: 600)
    try check(rendered.size.width > 0, "Image decoding")
    do {
        _ = try await ContentLoader.shared.image(in: images, page: 2)
        throw NSError(domain: "ReaderSmokeChecks", code: 2, userInfo: [NSLocalizedDescriptionKey: "Out-of-range page accepted"])
    } catch is ReaderContentError {}
    let pdf = PDFDocument()
    guard let nsImage = NSImage(data: try png(120, 180)) else { throw ReaderContentError.decodingFailed }
    for index in 0..<3 {
        guard let page = PDFPage(image: nsImage) else { throw ReaderContentError.invalidPDF }
        pdf.insert(page, at: index)
    }
    let pdfURL = root.appendingPathComponent("chapter.pdf")
    try check(pdf.write(to: pdfURL), "PDF fixture creation")
    let pdfContent = try await ContentLoader.shared.load(pdfURL)
    try check(pdfContent.isPDF && pdfContent.pageCount == 3, "PDF page count")
    let renderedPDF = try await ContentLoader.shared.image(in: pdfContent, page: 2, maxPixel: 600)
    try check(renderedPDF.size.height > 0, "PDF rendering")
    do {
        _ = try await ContentLoader.shared.load(root.appendingPathComponent("missing"))
        throw NSError(domain: "ReaderSmokeChecks", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing folder accepted"])
    } catch is ReaderContentError {}
    print("Reader smoke checks passed: image order, decode, bounds, PDF count/render, missing content")
}
