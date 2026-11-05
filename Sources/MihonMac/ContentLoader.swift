import AppKit
import Foundation
import ImageIO
import PDFKit

struct ReaderDocument {
    let url: URL
    let images: [URL]
    let pageSizes: [CGSize]
    let isPDF: Bool
    var pageCount: Int { pageSizes.count }
    func aspectRatio(at index: Int) -> CGFloat {
        guard pageSizes.indices.contains(index), pageSizes[index].height > 0 else { return 0.7 }
        return max(0.1, min(10, pageSizes[index].width / pageSizes[index].height))
    }
}

enum ReaderContentError: LocalizedError {
    case missingContent, invalidPDF, noImages, invalidPage, decodingFailed
    var errorDescription: String? {
        switch self {
        case .missingContent: return "This chapter’s files are missing. Import it again or download the chapter."
        case .invalidPDF: return "This PDF could not be opened. It may be damaged or password protected."
        case .noImages: return "No supported page images were found in this chapter."
        case .invalidPage: return "This page is outside the chapter."
        case .decodingFailed: return "This page image could not be decoded."
        }
    }
}

/// Runs file inspection and bounded page rendering away from the main actor.
actor ContentLoader {
    static let shared = ContentLoader()
    private let cache = NSCache<NSString, NSImage>()
    private let supported = Set(["jpg", "jpeg", "png", "webp", "gif", "heic", "heif", "tif", "tiff", "bmp", "avif"])

    init() {
        cache.countLimit = 16
        cache.totalCostLimit = 120 * 1024 * 1024
    }

    func load(_ url: URL) throws -> ReaderDocument {
        guard FileManager.default.fileExists(atPath: url.path) else { throw ReaderContentError.missingContent }
        if url.pathExtension.lowercased() == "pdf" {
            guard let pdf = PDFDocument(url: url), !pdf.isLocked, pdf.pageCount > 0 else {
                throw ReaderContentError.invalidPDF
            }
            let sizes = (0..<pdf.pageCount).map { pdf.page(at: $0)?.bounds(for: .cropBox).size ?? CGSize(width: 700, height: 1000) }
            return ReaderDocument(url: url, images: [], pageSizes: sizes, isPDF: true)
        }
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
        var images: [URL] = []
        while let file = enumerator?.nextObject() as? URL {
            guard supported.contains(file.pathExtension.lowercased()),
                  let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            images.append(file)
        }
        images.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        guard !images.isEmpty else { throw ReaderContentError.noImages }
        let sizes = images.map { file -> CGSize in
            guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                  let info = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = info[kCGImagePropertyPixelWidth] as? NSNumber,
                  let height = info[kCGImagePropertyPixelHeight] as? NSNumber else { return CGSize(width: 700, height: 1000) }
            let orientation = (info[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
            return (5...8).contains(orientation) ? CGSize(width: height.doubleValue, height: width.doubleValue) : CGSize(width: width.doubleValue, height: height.doubleValue)
        }
        return ReaderDocument(url: url, images: images, pageSizes: sizes, isPDF: false)
    }

    func image(in document: ReaderDocument, page: Int, maxPixel: Int = 2600) throws -> NSImage {
        guard document.pageSizes.indices.contains(page) else { throw ReaderContentError.invalidPage }
        let maxPixel = min(4000, max(600, maxPixel))
        let key = "\(document.url.path)#\(page)#\(maxPixel)" as NSString
        if let existing = cache.object(forKey: key) { return existing }
        let image: NSImage
        if document.isPDF {
            guard let pdf = PDFDocument(url: document.url), let pdfPage = pdf.page(at: page) else { throw ReaderContentError.invalidPDF }
            let size = document.pageSizes[page]
            let scale = CGFloat(maxPixel) / max(size.width, size.height)
            image = pdfPage.thumbnail(of: NSSize(width: size.width * scale, height: size.height * scale), for: .cropBox)
        } else {
            guard let source = CGImageSourceCreateWithURL(document.images[page] as CFURL, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                    kCGImageSourceShouldCacheImmediately: true,
                  ] as CFDictionary) else { throw ReaderContentError.decodingFailed }
            image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        let size = image.representations.first.map { $0.pixelsWide * $0.pixelsHigh * 4 } ?? maxPixel * maxPixel * 4
        cache.setObject(image, forKey: key, cost: size)
        return image
    }

    func clearCache() { cache.removeAllObjects() }
}
