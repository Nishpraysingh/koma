import Foundation
import AppKit

private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw NSError(domain: "KomaSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

@main
enum SmokeMain {
    @MainActor static func main() async {
        do {
            try await runStorageChecks()
            print("PASS: managed imports, natural sorting, progress, categories, bookmark/history integrity")
            print("PASS: full portable backup/restore, rejected unsafe backups and preserved original data")
            try await runReaderSmokeChecks()
            print("PASS: image/PDF page inspection, rendering and missing-content errors")
            try await runNetworkSmokeChecks()
            print("PASS: network fixtures, refresh preservation, HTTP errors, offline download persistence and cleanup")
            print("All local smoke checks passed.")
        } catch {
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    @MainActor private static func runStorageChecks() async throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("koma-smoke-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        let original = base.appendingPathComponent("My Comic", isDirectory: true)
        try fm.createDirectory(at: original, withIntermediateDirectories: true)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 150, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 400, bitsPerPixel: 32)!
        memset(bitmap.bitmapData, 255, 100 * 150 * 4)
        let image = bitmap.representation(using: .png, properties: [:])!
        try image.write(to: original.appendingPathComponent("10.png"))
        try image.write(to: original.appendingPathComponent("2.png"))
        let store = LibraryStore(rootURL: base.appendingPathComponent("library"))
        await store.importURLs([original])
        try check(store.books.count == 1, "Image folder import failed: \(store.statusMessage ?? "")")
        var book = store.books[0]
        let chapter = book.chapters[0]
        try check(chapter.pageCount == 2 && chapter.isDownloaded, "Imported page count is incorrect")
        try check(fm.fileExists(atPath: original.appendingPathComponent("2.png").path), "Import changed original files")
        let managed = store.url(for: chapter.relativePath!)
        try check(managed.path.hasPrefix(store.contentURL.path + "/"), "Import escaped the managed folder")
        let managedData = try Data(contentsOf: managed.appendingPathComponent("000001.png"))
        try check(managedData == image, "Managed page missing")
        store.addCategory("Favorites"); book.categories = ["Favorites"]; book.notes = "A note"; store.updateBook(book)
        store.recordProgress(bookID: book.id, chapterID: chapter.id, page: 1, pageCount: 2, allowCompletion: false)
        store.toggleBookmark(bookID: book.id, chapterID: chapter.id, page: 1)
        try check(!store.books[0].chapters[0].isRead, "Progress unexpectedly marked a chapter complete")
        try check(store.history.count == 1 && store.bookmarks.count == 1, "History/bookmark persistence failed")
        let reopened = LibraryStore(rootURL: store.rootURL)
        try check(reopened.books[0].chapters[0].lastPage == 1 && reopened.books[0].notes == "A note", "Relaunch lost saved metadata")
        store.markChapter(bookID: book.id, chapterID: chapter.id, read: true)
        try check(store.books[0].status == .completed, "Complete title status was not updated")
        store.markChapter(bookID: book.id, chapterID: chapter.id, read: false)
        try check(store.books[0].status == .reading, "Unread title remained complete")

        let backup = base.appendingPathComponent("backup.zip")
        try store.exportBackup(to: backup)
        let restored = LibraryStore(rootURL: base.appendingPathComponent("restored"))
        try restored.restoreBackup(from: backup)
        try check(restored.books.count == 1 && restored.bookmarks.count == 1 && restored.history.count == 1, "Backup metadata did not restore")
        try check(fm.fileExists(atPath: restored.url(for: chapter.relativePath!).appendingPathComponent("000001.png").path), "Backup omitted chapter files")
        let snapshotBefore = try Data(contentsOf: restored.rootURL.appendingPathComponent("library.json"))
        let unsafe = base.appendingPathComponent("unsafe", isDirectory: true)
        try fm.createDirectory(at: unsafe.appendingPathComponent("content"), withIntermediateDirectories: true)
        var bad = book; bad.coverPath = "../escape.png"
        try JSONEncoder().encode(LibrarySnapshot(books: [bad])).write(to: unsafe.appendingPathComponent("library.json"))
        let unsafeZip = base.appendingPathComponent("unsafe.zip")
        try ArchiveUtility.createZip(from: unsafe, to: unsafeZip)
        var rejected = false
        do { try restored.restoreBackup(from: unsafeZip) } catch { rejected = true }
        try check(rejected, "Restore accepted an unsafe path")
        let snapshotAfter = try Data(contentsOf: restored.rootURL.appendingPathComponent("library.json"))
        try check(snapshotBefore == snapshotAfter, "Failed restore changed the original snapshot")
        try check(fm.fileExists(atPath: restored.url(for: chapter.relativePath!).appendingPathComponent("000001.png").path), "Failed restore removed original content")

        let archive = base.appendingPathComponent("Comic.cbz")
        try ArchiveUtility.createZip(from: original, to: archive)
        await store.importURLs([archive, original.appendingPathComponent("2.png")])
        try check(store.books.count == 3, "CBZ or single-image import failed: \(store.statusMessage ?? "")")
        // A filesystem failure before old data moves must never delete the old library.
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: restored.rootURL.path)
        var permissionRejected = false
        do { try restored.restoreBackup(from: backup) } catch { permissionRejected = true }
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: restored.rootURL.path)
        try check(permissionRejected, "Read-only destination unexpectedly accepted restore")
        try check(fm.fileExists(atPath: restored.url(for: chapter.relativePath!).appendingPathComponent("000001.png").path), "Restore permission failure removed original files")
        let intactSnapshot = try Data(contentsOf: restored.rootURL.appendingPathComponent("library.json"))
        try check(intactSnapshot == snapshotBefore, "Restore permission failure altered original metadata")
        var maliciousZip = try Data(contentsOf: archive)
        let safeName = Data("2.png".utf8), unsafeName = Data("../xx".utf8)
        var start = maliciousZip.startIndex
        while let range = maliciousZip.range(of: safeName, in: start..<maliciousZip.endIndex) {
            maliciousZip.replaceSubrange(range, with: unsafeName)
            start = range.upperBound
        }
        var traversalRejected = false
        do { try ArchiveUtility.validateZip(maliciousZip) } catch { traversalRejected = true }
        try check(traversalRejected, "ZIP directory validation accepted traversal paths")
        let corruptRoot = base.appendingPathComponent("corrupt", isDirectory: true)
        try fm.createDirectory(at: corruptRoot, withIntermediateDirectories: true)
        let corrupt = Data("{broken-json".utf8)
        try corrupt.write(to: corruptRoot.appendingPathComponent("library.json"))
        let brokenStore = LibraryStore(rootURL: corruptRoot)
        brokenStore.save()
        let preserved = try Data(contentsOf: corruptRoot.appendingPathComponent("library.json"))
        try check(preserved == corrupt && brokenStore.statusMessage != nil, "Malformed metadata was silently overwritten")
        store.removeCategory("Favorites")
        try check(!store.books[0].categories.contains("Favorites"), "Removed category retained stale title membership")
        store.deleteBook(book.id)
        try check(!store.history.contains { $0.bookID == book.id } && !store.bookmarks.contains { $0.bookID == book.id }, "Removing a title left orphan history/bookmarks")
        try check(fm.fileExists(atPath: original.appendingPathComponent("2.png").path), "Removing managed title deleted original file")
    }
}
