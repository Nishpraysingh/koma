import Foundation
import Combine
import AppKit
import PDFKit
import ImageIO

@MainActor
final class LibraryStore: ObservableObject {
    @Published var books: [Book] = []
    @Published var categories: [String] = []
    @Published var bookmarks: [PageBookmark] = []
    @Published var history: [ReadingEvent] = []
    @Published var preferences = ReaderPreferences() { didSet { if !isLoading { save() } } }
    @Published var statusMessage: String?
    @Published var isImporting = false
    let rootURL: URL
    var contentURL: URL { rootURL.appendingPathComponent("content", isDirectory: true) }
    private var isLoading = true
    private var persistenceAvailable = true
    private let fm = FileManager.default

    init(rootURL: URL? = nil, loadDemo: Bool = false) {
        self.rootURL = rootURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Koma", isDirectory: true)
        do {
            try fm.createDirectory(at: contentURL, withIntermediateDirectories: true)
            let snapshotURL = self.rootURL.appendingPathComponent("library.json")
            if fm.fileExists(atPath: snapshotURL.path) {
                let snapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: Data(contentsOf: snapshotURL))
                try Self.validate(snapshot)
                apply(snapshot)
            }
        } catch {
            persistenceAvailable = false
            statusMessage = "Could not load the library. Your files have been preserved. Restore a backup or repair library.json before saving: \(error.localizedDescription)"
        }
        isLoading = false
        if loadDemo && books.isEmpty && persistenceAvailable { Task { await addSampleLibrary() } }
    }

    func url(for relativePath: String) -> URL {
        guard Self.validRelativePath(relativePath) else { return contentURL.appendingPathComponent(".invalid-path") }
        let url = contentURL.appendingPathComponent(relativePath).standardizedFileURL
        guard url.path.hasPrefix(contentURL.standardizedFileURL.path + "/") else { return contentURL.appendingPathComponent(".invalid-path") }
        return url
    }

    func book(id: UUID) -> Book? { books.first { $0.id == id } }

    func addBook(_ book: Book) {
        guard !books.contains(where: { $0.id == book.id || (book.remoteID != nil && $0.remoteID == book.remoteID && $0.source == book.source) }) else { return }
        books.append(book)
        for category in book.categories where !categories.contains(category) { categories.append(category) }
        save()
    }

    func updateBook(_ book: Book) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[index] = book
        for category in book.categories where !categories.contains(category) { categories.append(category) }
        save()
    }

    func deleteBook(_ id: UUID, removeFiles: Bool = true) {
        guard let book = book(id: id) else { return }
        if removeFiles {
            let paths = book.chapters.compactMap(\.relativePath) + [book.coverPath].compactMap { $0 }
            do {
                for path in Set(paths) {
                    let shared = books.filter { $0.id != id }.contains { candidate in
                        candidate.coverPath == path || candidate.chapters.contains { $0.relativePath == path }
                    }
                    if !shared && fm.fileExists(atPath: url(for: path).path) { try fm.removeItem(at: url(for: path)) }
                }
            } catch { statusMessage = "Some files could not be removed: \(error.localizedDescription)"; return }
        }
        books.removeAll { $0.id == id }
        bookmarks.removeAll { $0.bookID == id }
        history.removeAll { $0.bookID == id }
        save()
    }

    func addCategory(_ name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !categories.contains(clean) else { return }
        categories.append(clean); save()
    }

    func removeCategory(_ name: String) {
        categories.removeAll { $0 == name }
        for index in books.indices { books[index].categories.removeAll { $0 == name } }
        save()
    }

    func markChapter(bookID: UUID, chapterID: UUID, read: Bool) {
        guard let b = books.firstIndex(where: { $0.id == bookID }), let c = books[b].chapters.firstIndex(where: { $0.id == chapterID }) else { return }
        books[b].chapters[c].isRead = read
        if !read { books[b].chapters[c].lastPage = 0 }
        if books[b].chapters.allSatisfy(\.isRead) { books[b].status = .completed }
        else if books[b].status == .completed || books[b].status == .planned && read { books[b].status = .reading }
        save()
    }

    func recordProgress(bookID: UUID, chapterID: UUID, page: Int, pageCount: Int, allowCompletion: Bool = true) {
        guard let b = books.firstIndex(where: { $0.id == bookID }), let c = books[b].chapters.firstIndex(where: { $0.id == chapterID }), pageCount > 0 else { return }
        let safePage = min(max(0, page), pageCount - 1)
        books[b].chapters[c].lastPage = safePage
        books[b].chapters[c].pageCount = pageCount
        books[b].chapters[c].lastReadAt = Date()
        books[b].lastOpenedAt = Date()
        if books[b].status == .planned { books[b].status = .reading }
        if allowCompletion && preferences.autoMarkRead && safePage == pageCount - 1 { books[b].chapters[c].isRead = true }
        if books[b].chapters.allSatisfy(\.isRead) { books[b].status = .completed }
        if let existing = history.firstIndex(where: { $0.bookID == bookID && $0.chapterID == chapterID && Date().timeIntervalSince($0.date) < 60 * 30 }) {
            history[existing].page = safePage; history[existing].date = Date()
        } else { history.append(ReadingEvent(bookID: bookID, chapterID: chapterID, page: safePage)) }
        history.sort { $0.date > $1.date }
        if history.count > 5000 { history = Array(history.prefix(5000)) }
        save()
    }

    func toggleBookmark(bookID: UUID, chapterID: UUID, page: Int) {
        guard let book = book(id: bookID), book.chapters.contains(where: { $0.id == chapterID }), page >= 0 else { return }
        if let index = bookmarks.firstIndex(where: { $0.bookID == bookID && $0.chapterID == chapterID && $0.page == page }) { bookmarks.remove(at: index) }
        else { bookmarks.append(PageBookmark(bookID: bookID, chapterID: chapterID, page: page)) }
        save()
    }

    private var snapshot: LibrarySnapshot {
        LibrarySnapshot(books: books, categories: categories, bookmarks: bookmarks, history: history, preferences: preferences)
    }

    func save() {
        guard !isLoading else { return }
        guard persistenceAvailable else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(snapshot).write(to: rootURL.appendingPathComponent("library.json"), options: .atomic)
        } catch { statusMessage = "Your latest changes could not be saved: \(error.localizedDescription)" }
    }

    func importURLs(_ urls: [URL]) async {
        guard !isImporting, persistenceAvailable else { return }
        isImporting = true
        defer { isImporting = false }
        var succeeded = 0
        var failures: [String] = []
        let destination = contentURL
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            do {
                let book = try await Task.detached(priority: .userInitiated) { try LibraryImporter.importItem(url, contentURL: destination) }.value
                addBook(book); succeeded += 1
            } catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            if access { url.stopAccessingSecurityScopedResource() }
        }
        statusMessage = failures.isEmpty ? "Imported \(succeeded) title\(succeeded == 1 ? "" : "s"). Files are copied into your local library." : "Imported \(succeeded) title(s). " + failures.joined(separator: "\n")
    }

    func exportBackup(to destination: URL) throws {
        guard persistenceAvailable else { throw LibraryError.invalid("The current library could not be loaded. Export is disabled to preserve your original data.") }
        let staging = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: staging.appendingPathComponent("library.json"), options: .atomic)
        try fm.copyItem(at: contentURL, to: staging.appendingPathComponent("content"))
        try ArchiveUtility.createZip(from: staging, to: destination)
    }

    func restoreBackup(from source: URL) throws {
        let staging = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        try ArchiveUtility.extractZip(source, to: staging)
        let restored = try JSONDecoder().decode(LibrarySnapshot.self, from: Data(contentsOf: staging.appendingPathComponent("library.json")))
        try Self.validate(restored)
        let stagedContent = staging.appendingPathComponent("content", isDirectory: true)
        guard fm.fileExists(atPath: stagedContent.path) else { throw LibraryError.invalid("This backup does not contain a content folder.") }
        for book in restored.books {
            for path in book.chapters.compactMap(\.relativePath) + [book.coverPath].compactMap({ $0 }) {
                guard fm.fileExists(atPath: stagedContent.appendingPathComponent(path).path) else { throw LibraryError.invalid("The backup is missing a referenced file: \(path)") }
            }
        }
        let oldContent = rootURL.appendingPathComponent("content-before-restore-\(UUID().uuidString)")
        let oldSnapshot = rootURL.appendingPathComponent("library-before-restore-\(UUID().uuidString).json")
        let snapshotURL = rootURL.appendingPathComponent("library.json")
        var movedOldContent = false
        var movedOldSnapshot = false
        var installedContent = false
        var installedSnapshot = false
        do {
            if fm.fileExists(atPath: contentURL.path) { try fm.moveItem(at: contentURL, to: oldContent); movedOldContent = true }
            if fm.fileExists(atPath: snapshotURL.path) { try fm.moveItem(at: snapshotURL, to: oldSnapshot); movedOldSnapshot = true }
            installedContent = true; try fm.moveItem(at: stagedContent, to: contentURL)
            installedSnapshot = true; try fm.copyItem(at: staging.appendingPathComponent("library.json"), to: snapshotURL)
        } catch {
            if installedContent { try? fm.removeItem(at: contentURL) }
            if movedOldContent { try? fm.moveItem(at: oldContent, to: contentURL) }
            if installedSnapshot { try? fm.removeItem(at: snapshotURL) }
            if movedOldSnapshot { try? fm.moveItem(at: oldSnapshot, to: snapshotURL) }
            throw error
        }
        // Keep the previous library recoverable until both replacement steps have succeeded.
        if movedOldContent { try? fm.removeItem(at: oldContent) }
        if movedOldSnapshot { try? fm.removeItem(at: oldSnapshot) }
        isLoading = true; apply(restored); isLoading = false; persistenceAvailable = true
        statusMessage = "Restored \(books.count) titles, their files, and reading progress."
    }

    private func apply(_ snapshot: LibrarySnapshot) {
        books = snapshot.books; categories = snapshot.categories; bookmarks = snapshot.bookmarks
        history = snapshot.history; preferences = snapshot.preferences
    }

    static func validRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") && !path.contains("\0") && !path.split(separator: "/").contains("..") && !path.contains(":")
    }

    private static func validate(_ snapshot: LibrarySnapshot) throws {
        guard snapshot.version == 1 else { throw LibraryError.invalid("Unsupported backup version \(snapshot.version).") }
        guard Set(snapshot.books.map(\.id)).count == snapshot.books.count else { throw LibraryError.invalid("Duplicate title identifiers.") }
        for book in snapshot.books {
            guard Set(book.chapters.map(\.id)).count == book.chapters.count else { throw LibraryError.invalid("Duplicate chapter identifiers.") }
            for path in book.chapters.compactMap(\.relativePath) + [book.coverPath].compactMap({ $0 }) {
                guard validRelativePath(path) else { throw LibraryError.invalid("An unsafe file path was found in the library.") }
            }
        }
        let chapterIDs = Dictionary(uniqueKeysWithValues: snapshot.books.map { ($0.id, Set($0.chapters.map(\.id))) })
        guard snapshot.bookmarks.allSatisfy({ $0.page >= 0 && chapterIDs[$0.bookID]?.contains($0.chapterID) == true }), snapshot.history.allSatisfy({ $0.page >= 0 && chapterIDs[$0.bookID]?.contains($0.chapterID) == true }) else { throw LibraryError.invalid("The library contains invalid reading history or bookmarks.") }
    }

    func addSampleLibrary() async {
        guard !isImporting, persistenceAvailable else { return }
        if books.contains(where: { $0.source == "Sample" }) { statusMessage = "Sample titles are already in your library."; return }
        isImporting = true; defer { isImporting = false }
        do {
            let samples = try SampleLibrary.create(at: contentURL)
            for book in samples { addBook(book) }
            statusMessage = "Added three original sample titles. Open one to try the reader."
        } catch { statusMessage = "Could not create samples: \(error.localizedDescription)" }
    }
}

enum LibraryError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

struct LibraryImporter {
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic", "tif", "tiff", "bmp", "avif"]
    static let archiveExtensions: Set<String> = ["cbz", "zip"]

    static func importItem(_ source: URL, contentURL: URL) throws -> Book {
        let fm = FileManager.default
        let bookID = UUID()
        let base = "books/\(bookID.uuidString)"
        let destination = contentURL.appendingPathComponent(base, isDirectory: true)
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        do {
            var book = Book(id: bookID, title: source.deletingPathExtension().lastPathComponent)
            let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw LibraryError.invalid("Symbolic links cannot be imported.") }
            var chapterSources: [URL]
            if values.isDirectory == true {
                book.title = source.lastPathComponent
                let children = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: .skipsHiddenFiles).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                if children.contains(where: { imageExtensions.contains($0.pathExtension.lowercased()) }) { chapterSources = [source] }
                else { chapterSources = children.filter { url in
                    let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                    return isDirectory || url.pathExtension.lowercased() == "pdf" || archiveExtensions.contains(url.pathExtension.lowercased())
                } }
            } else { chapterSources = [source] }
            guard !chapterSources.isEmpty else { throw LibraryError.invalid("No supported chapters were found. Import PDF, CBZ/ZIP, or a folder of images/chapters.") }
            for (index, chapterSource) in chapterSources.enumerated() {
                let chapter = try copyChapter(chapterSource, index: index, base: base, contentURL: contentURL)
                book.chapters.append(chapter)
            }
            guard !book.chapters.isEmpty else { throw LibraryError.invalid("No readable pages were found.") }
            if let path = book.chapters.first?.relativePath {
                let chapterURL = contentURL.appendingPathComponent(path)
                if let cover = try? makeCover(chapterURL) {
                    let coverPath = base + "/cover.png"
                    try cover.write(to: contentURL.appendingPathComponent(coverPath))
                    book.coverPath = coverPath
                }
            }
            return book
        } catch { try? fm.removeItem(at: destination); throw error }
    }

    private static func copyChapter(_ source: URL, index: Int, base: String, contentURL: URL) throws -> Chapter {
        let fm = FileManager.default
        let chapterName = String(format: "%04d", index + 1)
        let ext = source.pathExtension.lowercased()
        let sourceValues = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard sourceValues.isSymbolicLink != true else { throw LibraryError.invalid("Symbolic links cannot be imported.") }
        let isFolder = sourceValues.isDirectory == true
        let title = source.deletingPathExtension().lastPathComponent
        if ext == "pdf" && !isFolder {
            guard let document = PDFDocument(url: source), !document.isLocked, document.pageCount > 0 else { throw LibraryError.invalid("The PDF is empty, encrypted, or unreadable.") }
            let path = base + "/\(chapterName).pdf"
            try fm.copyItem(at: source, to: contentURL.appendingPathComponent(path))
            return Chapter(title: title, number: Double(index + 1), relativePath: path, pageCount: document.pageCount)
        }
        let path = base + "/\(chapterName)"
        let target = contentURL.appendingPathComponent(path, isDirectory: true)
        var extracted: URL?
        defer { if let extracted { try? fm.removeItem(at: extracted) } }
        let folder: URL
        if !isFolder && imageExtensions.contains(ext) {
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            try fm.copyItem(at: source, to: target.appendingPathComponent("000001." + ext))
            return Chapter(title: title, number: Double(index + 1), relativePath: path, pageCount: 1)
        }
        if isFolder { folder = source }
        else if archiveExtensions.contains(ext) {
            let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            extracted = temp
            try ArchiveUtility.extractZip(source, to: temp)
            folder = temp
        } else { throw LibraryError.invalid("Unsupported format. Use PDF, CBZ/ZIP, or image folders. CBR/RAR and EPUB are not supported.") }
        let images = try imageURLs(in: folder)
        guard !images.isEmpty else { throw LibraryError.invalid("No supported images were found in \(source.lastPathComponent).") }
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        for (page, image) in images.enumerated() {
            let filename = String(format: "%06d", page + 1) + "." + image.pathExtension.lowercased()
            try fm.copyItem(at: image, to: target.appendingPathComponent(filename))
        }
        return Chapter(title: title, number: Double(index + 1), relativePath: path, pageCount: images.count)
    }

    static func imageURLs(in folder: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var images: [URL] = []
        while let item = enumerator.nextObject() as? URL {
            let values = try item.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { throw LibraryError.invalid("Symbolic links are not allowed inside imported folders.") }
            if values.isRegularFile == true && imageExtensions.contains(item.pathExtension.lowercased()) { images.append(item) }
            if images.count > 100_000 { throw LibraryError.invalid("This import contains too many images.") }
        }
        return images.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private static func makeCover(_ chapter: URL) throws -> Data? {
        let image: NSImage?
        if chapter.pathExtension.lowercased() == "pdf" { image = PDFDocument(url: chapter)?.page(at: 0)?.thumbnail(of: NSSize(width: 600, height: 840), for: .mediaBox) }
        else {
            image = try imageURLs(in: chapter).first.flatMap { file in
                guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                      let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 840,
                      ] as CFDictionary) else { return nil }
                return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
        }
        guard let image, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
