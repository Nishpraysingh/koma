import XCTest
@testable import MihonMac

private final class CatalogURLProtocol: URLProtocol {
    static var response: (URLRequest) throws -> (Int, Data) = { _ in (500, Data()) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.response(request)
            let reply = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: reply, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor
final class NetworkServiceTests: XCTestCase {
    private func service() -> NetworkService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CatalogURLProtocol.self]
        return NetworkService(session: URLSession(configuration: configuration))
    }

    func testSearchMapsRelationshipsAndEncodesTitle() async throws {
        CatalogURLProtocol.response = { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(query.first { $0.name == "title" }?.value, "A & B")
            let body = #"{"result":"ok","data":[{"id":"manga-id","attributes":{"title":{"ja":"日本語","en":"A & B"},"description":{"en":"A quiet story"},"tags":[{"attributes":{"name":{"en":"Adventure"}}}]},"relationships":[{"type":"author","attributes":{"name":"An Author"}},{"type":"cover_art","attributes":{"fileName":"cover.png"}}]}]}"#
            return (200, Data(body.utf8))
        }
        let result = try await service().search("A & B")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].title, "A & B")
        XCTAssertEqual(result[0].author, "An Author")
        XCTAssertEqual(result[0].tags, ["Adventure"])
        XCTAssertEqual(result[0].coverURL, "https://uploads.mangadex.org/covers/manga-id/cover.png.256.jpg")
    }

    func testRefreshPreservesOfflineProgressAndAddsNewChapter() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(rootURL: root)
        let chapter = Chapter(title: "Old title", number: 1, relativePath: "books/test/chapter", pageCount: 8, lastPage: 4, isRead: true, remoteID: "chapter-1")
        let removed = Chapter(title: "Removed at source", number: 0, relativePath: "books/test/removed", remoteID: "old")
        let book = Book(title: "Fixture", chapters: [removed, chapter], source: "MangaDex", remoteID: "manga-id")
        store.addBook(book)
        CatalogURLProtocol.response = { _ in
            let body = #"{"result":"ok","total":2,"data":[{"id":"chapter-1","attributes":{"chapter":"1","title":"Updated title","pages":9}},{"id":"chapter-2","attributes":{"chapter":"2","title":"Next","pages":4}}]}"#
            return (200, Data(body.utf8))
        }
        await service().refresh(bookID: book.id, store: store)
        let updated = try XCTUnwrap(store.book(id: book.id))
        XCTAssertEqual(updated.chapters.count, 3)
        let preserved = try XCTUnwrap(updated.chapters.first { $0.remoteID == "chapter-1" })
        XCTAssertEqual(preserved.id, chapter.id)
        XCTAssertTrue(preserved.isRead)
        XCTAssertEqual(preserved.lastPage, 4)
        XCTAssertEqual(preserved.pageCount, 8)
        XCTAssertEqual(preserved.relativePath, chapter.relativePath)
        XCTAssertTrue(updated.chapters.contains { $0.remoteID == "old" })
        XCTAssertTrue(updated.chapters.contains { $0.remoteID == "chapter-2" && !$0.isDownloaded })
    }

    func testRateLimitProducesActionableError() async throws {
        CatalogURLProtocol.response = { _ in (429, Data("{}".utf8)) }
        do { _ = try await service().search("Test"); XCTFail("Expected rate-limit error") }
        catch { XCTAssertTrue(error.localizedDescription.contains("rate limit")) }
    }

    func testRefreshFailureDoesNotReplaceExistingChapters() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(rootURL: root)
        let chapter = Chapter(title: "Keep me", isRead: true, remoteID: "chapter-1")
        let book = Book(title: "Fixture", chapters: [chapter], source: "MangaDex", remoteID: "manga-id")
        store.addBook(book)
        CatalogURLProtocol.response = { _ in (503, Data("{}".utf8)) }
        let network = service()
        await network.refresh(bookID: book.id, store: store)
        XCTAssertEqual(store.book(id: book.id)?.chapters, [chapter])
        XCTAssertNotNil(network.message)
        XCTAssertFalse(network.isWorking)
    }
}
