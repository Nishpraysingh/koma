import AppKit
import PDFKit
import XCTest
@testable import MihonMac

final class ReaderContentTests: XCTestCase {
    func testImagePagesUseNaturalOrderAndIgnoreUnrelatedFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try image(width: 100, height: 200).write(to: root.appendingPathComponent("10.png"))
        try image(width: 200, height: 100).write(to: root.appendingPathComponent("2.png"))
        try Data("ignored".utf8).write(to: root.appendingPathComponent("ComicInfo.xml"))
        let document = try await ContentLoader.shared.load(root)
        XCTAssertEqual(document.pageCount, 2)
        XCTAssertEqual(document.images.map(\.lastPathComponent), ["2.png", "10.png"])
        XCTAssertEqual(document.aspectRatio(at: 0), 2, accuracy: 0.01)
        let rendered = try await ContentLoader.shared.image(in: document, page: 0, maxPixel: 600)
        XCTAssertGreaterThan(rendered.size.width, 0)
        do {
            _ = try await ContentLoader.shared.image(in: document, page: 2)
            XCTFail("Out-of-range page should fail")
        } catch { XCTAssertTrue(error is ReaderContentError) }
    }

    func testPDFPagesAreCountedAndRendered() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("chapter.pdf")
        let data = NSMutableData()
        let consumer = try XCTUnwrap(CGDataConsumer(data: data))
        var box = CGRect(x: 0, y: 0, width: 400, height: 600)
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
        for _ in 0..<3 {
            context.beginPDFPage(nil)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(box)
            context.endPDFPage()
        }
        context.closePDF()
        try (data as Data).write(to: url)
        let document = try await ContentLoader.shared.load(url)
        XCTAssertTrue(document.isPDF)
        XCTAssertEqual(document.pageCount, 3)
        XCTAssertEqual(document.aspectRatio(at: 0), 2.0 / 3, accuracy: 0.01)
        let rendered = try await ContentLoader.shared.image(in: document, page: 2, maxPixel: 600)
        XCTAssertGreaterThan(rendered.size.height, 0)
    }

    func testEmptyAndMissingContentReportErrors() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            _ = try await ContentLoader.shared.load(root)
            XCTFail("Missing content should fail")
        } catch { XCTAssertTrue(error is ReaderContentError) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            _ = try await ContentLoader.shared.load(root)
            XCTFail("Empty folder should fail")
        } catch { XCTAssertTrue(error is ReaderContentError) }
    }

    private func image(width: Int, height: Int) throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32))
        memset(bitmap.bitmapData, 255, width * height * 4)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}
