import Foundation

private final class SmokeCatalogURLProtocol: URLProtocol {
    static var response: (URLRequest) throws -> (Int, Data) = { _ in (500, Data()) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.response(request)
            let mime = request.url!.host == "pages.example.test" ? "image/png" : "application/json"
            let reply = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": mime, "Content-Length": String(data.count)])!
            client?.urlProtocol(self, didReceive: reply, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private func networkCheck(_ condition: @autoclosure () -> Bool, _ explanation: String) throws {
    if !condition() { throw NSError(domain: "NetworkSmokeChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: explanation]) }
}

@MainActor
func runNetworkSmokeChecks() async throws {
    func service() -> NetworkService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SmokeCatalogURLProtocol.self]
        return NetworkService(session: URLSession(configuration: configuration))
    }

    SmokeCatalogURLProtocol.response = { request in
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        try networkCheck(query.first { $0.name == "title" }?.value == "A & B", "Catalog query encoding changed")
        let body = #"{"result":"ok","data":[{"id":"manga-id","attributes":{"title":{"ja":"日本語","en":"A & B"},"description":{"en":"A quiet story"},"tags":[{"attributes":{"name":{"en":"Adventure"}}}]},"relationships":[{"type":"author","attributes":{"name":"An Author"}},{"type":"cover_art","attributes":{"fileName":"cover.png"}}]}]}"#
        return (200, Data(body.utf8))
    }
    let result = try await service().search("A & B")
    try networkCheck(result.count == 1, "Catalog result count")
    try networkCheck(result.first?.title == "A & B", "Catalog English title")
    try networkCheck(result.first?.author == "An Author", "Catalog author relationship")
    try networkCheck(result.first?.tags == ["Adventure"], "Catalog tag relationship")
    try networkCheck(result.first?.coverURL == "https://uploads.mangadex.org/covers/manga-id/cover.png.256.jpg", "Catalog cover URL")
    print("PASS catalog relationships and encoded query")

    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Koma-network-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = LibraryStore(rootURL: root)
    let chapter = Chapter(title: "Old title", number: 1, relativePath: "books/test/chapter", pageCount: 8, lastPage: 4, isRead: true, remoteID: "chapter-1")
    let removed = Chapter(title: "Removed at source", number: 0, relativePath: "books/test/removed", remoteID: "old")
    let book = Book(title: "Fixture", chapters: [removed, chapter], source: "MangaDex", remoteID: "manga-id")
    store.addBook(book)
    SmokeCatalogURLProtocol.response = { _ in
        let body = #"{"result":"ok","total":2,"data":[{"id":"chapter-1","attributes":{"chapter":"1","title":"Updated title","pages":9}},{"id":"chapter-2","attributes":{"chapter":"2","title":"Next","pages":4}}]}"#
        return (200, Data(body.utf8))
    }
    await service().refresh(bookID: book.id, store: store)
    guard let updated = store.book(id: book.id), let preserved = updated.chapters.first(where: { $0.remoteID == "chapter-1" }) else {
        throw NSError(domain: "NetworkSmokeChecks", code: 2, userInfo: [NSLocalizedDescriptionKey: "Refresh removed the title or read chapter"])
    }
    try networkCheck(updated.chapters.count == 3, "Refresh chapter count")
    try networkCheck(preserved.id == chapter.id && preserved.isRead && preserved.lastPage == 4, "Refresh lost reading progress")
    try networkCheck(preserved.pageCount == 8 && preserved.relativePath == chapter.relativePath, "Refresh replaced offline content")
    try networkCheck(updated.chapters.contains { $0.remoteID == "old" }, "Refresh removed cached source-deleted chapter")
    try networkCheck(updated.chapters.contains { $0.remoteID == "chapter-2" && !$0.isDownloaded }, "Refresh did not add new chapter")
    print("PASS refresh preserves offline reading state and adds chapters")

    SmokeCatalogURLProtocol.response = { _ in (429, Data("{}".utf8)) }
    var rateLimited = false
    do { _ = try await service().search("Test") }
    catch { rateLimited = error.localizedDescription.contains("rate limit") }
    try networkCheck(rateLimited, "HTTP 429 must give actionable rate limit error")
    print("PASS rate-limit error")

    let before = store.book(id: book.id)?.chapters
    SmokeCatalogURLProtocol.response = { _ in (503, Data("{}".utf8)) }
    let network = service()
    await network.refresh(bookID: book.id, store: store)
    try networkCheck(store.book(id: book.id)?.chapters == before, "Failed refresh replaced existing chapters")
    try networkCheck(network.message != nil && !network.isWorking, "Failed refresh must surface error and clear busy state")
    print("PASS failed refresh integrity")

    let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l9sAAAAASUVORK5CYII=")!
    let downloadable = Chapter(title: "Download fixture", remoteID: "download-1")
    let downloadBook = Book(title: "Download fixture", chapters: [downloadable], source: "MangaDex", remoteID: "download-manga")
    store.addBook(downloadBook)
    SmokeCatalogURLProtocol.response = { request in
        if request.url!.path.hasPrefix("/at-home/server/") {
            return (200, Data(#"{"result":"ok","baseUrl":"https://pages.example.test","chapter":{"hash":"fixture-hash","data":["page.png"],"dataSaver":["page.png"]}}"#.utf8))
        }
        return (200, png)
    }
    let downloader = service()
    await downloader.download(bookID: downloadBook.id, chapterID: downloadable.id, store: store)
    let local = store.book(id: downloadBook.id)?.chapters.first
    try networkCheck(local?.isDownloaded == true && local?.pageCount == 1, "Download did not persist chapter path/page count: \(downloader.message ?? "no message")")
    if let relative = local?.relativePath {
        let image = store.url(for: relative).appendingPathComponent("00001.png")
        try networkCheck(FileManager.default.fileExists(atPath: image.path), "Downloaded chapter page missing")
        let imageData = try Data(contentsOf: image)
        try networkCheck(imageData == png, "Downloaded image bytes changed")
    }
    try networkCheck(downloader.jobs.last?.state == "Complete", "Download job did not complete")
    let reopened = LibraryStore(rootURL: root)
    try networkCheck(reopened.book(id: downloadBook.id)?.chapters.first?.isDownloaded == true, "Download was not persisted across relaunch")
    print("PASS staged offline download and persistence")

    let failed = Chapter(title: "Failed fixture", remoteID: "download-fail")
    let failedBook = Book(title: "Failed download", chapters: [failed], source: "MangaDex", remoteID: "failed-manga")
    store.addBook(failedBook)
    SmokeCatalogURLProtocol.response = { request in
        if request.url!.path.hasPrefix("/at-home/server/") {
            return (200, Data(#"{"result":"ok","baseUrl":"https://pages.example.test","chapter":{"hash":"fixture-hash","data":["page.png"],"dataSaver":["page.png"]}}"#.utf8))
        }
        return (503, Data())
    }
    await downloader.download(bookID: failedBook.id, chapterID: failed.id, store: store)
    try networkCheck(store.book(id: failedBook.id)?.chapters.first?.relativePath == nil, "Failed download marked as offline")
    try networkCheck(downloader.jobs.last?.state == "Failed", "Failed download job state")
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: store.contentURL.path).filter { $0.hasPrefix(".download-") }
    try networkCheck(leftovers.isEmpty, "Failed download left staged content behind")
    print("PASS failed download leaves no offline path or staging files")
}
