import Foundation
import Combine
import Security

struct DownloadJob: Identifiable {
    var id = UUID()
    var bookID: UUID
    var chapterID: UUID
    var title: String
    var progress: Double = 0
    var state: String = "Queued"
    var error: String? = nil
}

struct CatalogEntry: Identifiable, Hashable {
    var id: String
    var title: String
    var author: String
    var summary: String
    var coverURL: String?
    var tags: [String]
}

enum ServiceError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}

@MainActor
final class NetworkService: ObservableObject {
    @Published var isWorking = false
    @Published var message: String?
    @Published var jobs: [DownloadJob] = []
    private var workCount = 0
    private var activeDownload: UUID?
    private var cancellationGeneration = 0
    private var lastRequest = Date.distantPast
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    private func begin() { workCount += 1; isWorking = true }
    private func end() { workCount = max(0, workCount - 1); isWorking = workCount > 0 }

    func search(_ query: String) async throws -> [CatalogEntry] {
        var parameters = [URLQueryItem(name: "limit", value: "40"),
                          URLQueryItem(name: "includes[]", value: "cover_art"),
                          URLQueryItem(name: "includes[]", value: "author"),
                          URLQueryItem(name: "contentRating[]", value: "safe"),
                          URLQueryItem(name: "contentRating[]", value: "suggestive")]
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parameters.append(URLQueryItem(name: "order[followedCount]", value: "desc"))
        } else { parameters.append(URLQueryItem(name: "title", value: query)) }
        let object = try await dex("/manga", parameters)
        guard let items = object["data"] as? [[String: Any]] else { throw ServiceError.message("MangaDex returned an unexpected catalog response.") }
        return items.compactMap { item in
            guard let id = item["id"] as? String, let a = item["attributes"] as? [String: Any] else { return nil }
            let relationships = item["relationships"] as? [[String: Any]] ?? []
            let authors = relationships.filter { $0["type"] as? String == "author" }
                .compactMap { ($0["attributes"] as? [String: Any])?["name"] as? String }
            let cover = relationships.first { $0["type"] as? String == "cover_art" }
            let file = (cover?["attributes"] as? [String: Any])?["fileName"] as? String
            let tags = (a["tags"] as? [[String: Any]] ?? []).compactMap { tag -> String? in
                guard let attributes = tag["attributes"] as? [String: Any] else { return nil }
                return self.localized(attributes["name"])
            }
            return CatalogEntry(id: id, title: self.localized(a["title"]) ?? "Untitled", author: authors.joined(separator: ", "),
                                summary: self.localized(a["description"]) ?? "", coverURL: file.map { "https://uploads.mangadex.org/covers/\(id)/\($0).256.jpg" }, tags: tags)
        }
    }

    func add(_ entry: CatalogEntry, store: LibraryStore) async {
        guard !store.books.contains(where: { $0.source == "MangaDex" && $0.remoteID == entry.id }) else {
            message = "This title is already in your library."; return
        }
        let book = Book(title: entry.title, author: entry.author.isEmpty ? "Unknown author" : entry.author,
                        summary: entry.summary, coverURL: entry.coverURL, tags: entry.tags,
                        source: "MangaDex", remoteID: entry.id)
        store.addBook(book)
        await refresh(bookID: book.id, store: store)
        await cacheCover(bookID: book.id, store: store)
    }

    func refreshLibrary(store: LibraryStore) async {
        let ids = store.books.filter { $0.source == "MangaDex" }.map(\.id)
        guard !ids.isEmpty else { message = "Add a MangaDex title from Browse to check for new chapters."; return }
        for id in ids {
            if Task.isCancelled { return }
            await refresh(bookID: id, store: store)
        }
    }

    func refresh(bookID: UUID, store: LibraryStore) async {
        guard let initial = store.book(id: bookID), let remoteID = initial.remoteID, initial.source == "MangaDex" else { return }
        begin(); defer { end() }
        do {
            var records: [[String: Any]] = []
            var offset = 0
            repeat {
                try Task.checkCancellation()
                let object = try await dex("/manga/\(remoteID)/feed", [
                    .init(name: "translatedLanguage[]", value: store.preferences.language),
                    .init(name: "order[chapter]", value: "asc"), .init(name: "order[volume]", value: "asc"),
                    .init(name: "limit", value: "500"), .init(name: "offset", value: String(offset)),
                    .init(name: "includeExternalUrl", value: "0"), .init(name: "includeFutureUpdates", value: "0")])
                guard let batch = object["data"] as? [[String: Any]] else { throw ServiceError.message("MangaDex returned an unexpected chapter feed.") }
                records += batch; offset += batch.count
                let total = object["total"] as? Int ?? offset
                if batch.isEmpty || offset >= total { break }
                if offset >= 10000 { throw ServiceError.message("This title exceeds MangaDex's feed pagination limit. Narrow the chapter language.") }
            } while true
            guard var book = store.book(id: bookID) else { return }
            let existing = Dictionary(book.chapters.compactMap { c in c.remoteID.map { ($0, c) } }, uniquingKeysWith: { first, _ in first })
            var incoming: [Chapter] = []
            var seen = Set<String>()
            for record in records {
                guard let id = record["id"] as? String, let a = record["attributes"] as? [String: Any] else { continue }
                if let external = a["externalUrl"] as? String, !external.isEmpty { continue }
                guard (a["pages"] as? Int ?? 0) > 0 else { continue }
                let chapter = a["chapter"] as? String ?? ""
                let volume = a["volume"] as? String ?? ""
                let key = chapter.isEmpty ? id : "\(volume)-\(chapter)"
                // One scanlation per chapter; preserve an already-added alternative if present.
                if !seen.insert(key).inserted && existing[id] == nil { continue }
                let subtitle = a["title"] as? String ?? ""
                let label = chapter.isEmpty ? (subtitle.isEmpty ? "Special chapter" : subtitle) : "Chapter \(chapter)\(subtitle.isEmpty ? "" : " · " + subtitle)"
                var value = existing[id] ?? Chapter(title: label, number: Double(chapter) ?? 0, remoteID: id)
                value.title = label
                if !value.isDownloaded { value.pageCount = a["pages"] as? Int ?? 0 }
                incoming.append(value)
            }
            let incomingIDs = Set(incoming.compactMap(\.remoteID))
            incoming += book.chapters.filter { chapter in
                guard let id = chapter.remoteID else { return true }
                return !incomingIDs.contains(id) // Preserve offline/read records even when a source removes them.
            }
            book.chapters = incoming.sorted { $0.number == $1.number ? $0.title.localizedStandardCompare($1.title) == .orderedAscending : $0.number < $1.number }
            book.lastUpdatedAt = Date(); store.updateBook(book)
            message = "Updated \(book.title): \(book.chapters.count) chapters in \(store.preferences.language)."
        } catch is CancellationError { message = "Update cancelled." }
        catch { message = error.localizedDescription }
    }

    func downloadUnread(bookID: UUID, store: LibraryStore) async {
        let ids = store.book(id: bookID)?.chapters.filter { !$0.isRead && !$0.isDownloaded }.map(\.id) ?? []
        let generation = cancellationGeneration
        for id in ids {
            if Task.isCancelled || generation != cancellationGeneration { return }
            await download(bookID: bookID, chapterID: id, store: store)
        }
    }

    func download(bookID: UUID, chapterID: UUID, store: LibraryStore) async {
        guard let book = store.book(id: bookID), let chapter = book.chapters.first(where: { $0.id == chapterID }),
              let remoteID = chapter.remoteID, !chapter.isDownloaded else { return }
        guard !jobs.contains(where: { $0.chapterID == chapterID && ["Queued", "Downloading"].contains($0.state) }) else { return }
        let job = DownloadJob(bookID: bookID, chapterID: chapterID, title: "\(book.title) · \(chapter.title)")
        jobs.append(job); let generation = cancellationGeneration
        begin(); defer { end() }
        while activeDownload != nil {
            if Task.isCancelled || generation != cancellationGeneration { setJob(job.id, state: "Cancelled"); return }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        activeDownload = job.id
        defer { activeDownload = nil }
        let relative = "books/\(bookID.uuidString)/chapters/\(chapterID.uuidString)"
        let destination = store.url(for: relative)
        let staging = store.contentURL.appendingPathComponent(".download-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        do {
            try checkDownload(generation)
            setJob(job.id, state: "Downloading")
            let object = try await dex("/at-home/server/\(remoteID)", [])
            guard let base = object["baseUrl"] as? String, let source = object["chapter"] as? [String: Any],
                  let hash = source["hash"] as? String else { throw ServiceError.message("MangaDex did not return page locations.") }
            let saver = store.preferences.dataSaver
            guard let pages = source[saver ? "dataSaver" : "data"] as? [String], !pages.isEmpty else {
                throw ServiceError.message("This chapter has no downloadable pages.")
            }
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            for (index, file) in pages.enumerated() {
                try checkDownload(generation)
                guard let url = URL(string: "\(base)/\(saver ? "data-saver" : "data")/\(hash)/\(file)"), url.scheme == "https" else {
                    throw ServiceError.message("Source returned an invalid page URL.")
                }
                var request = URLRequest(url: url); request.timeoutInterval = 90
                request.setValue("Koma/1.0 (local macOS reader)", forHTTPHeaderField: "User-Agent")
                let (temporary, response) = try await session.download(for: request)
                try checkDownload(generation)
                try validate(response)
                guard let mime = response.mimeType, mime.hasPrefix("image/") else { throw ServiceError.message("A downloaded page was not an image.") }
                let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size > 0 && size < 100_000_000 else { throw ServiceError.message("A page was empty or larger than 100 MB.") }
                let ext = ["jpg", "jpeg", "png", "webp", "gif", "avif"].contains(url.pathExtension.lowercased()) ? url.pathExtension.lowercased() : "jpg"
                try FileManager.default.moveItem(at: temporary, to: staging.appendingPathComponent(String(format: "%05d.%@", index + 1, ext)))
                setJob(job.id, progress: Double(index + 1) / Double(pages.count))
            }
            try checkDownload(generation)
            guard var latest = store.book(id: bookID), let index = latest.chapters.firstIndex(where: { $0.id == chapterID }) else {
                throw ServiceError.message("The title was removed while downloading.")
            }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.moveItem(at: staging, to: destination)
            latest.chapters[index].relativePath = relative; latest.chapters[index].pageCount = pages.count
            store.updateBook(latest); setJob(job.id, state: "Complete", progress: 1)
        } catch is CancellationError { setJob(job.id, state: "Cancelled") }
        catch { setJob(job.id, state: "Failed", error: error.localizedDescription); message = error.localizedDescription }
    }

    func cancelDownloads() { cancellationGeneration += 1 }
    func clearFinishedJobs() { jobs.removeAll { !["Queued", "Downloading"].contains($0.state) } }
    private func checkDownload(_ generation: Int) throws {
        if Task.isCancelled || generation != cancellationGeneration { throw CancellationError() }
    }
    private func setJob(_ id: UUID, state: String? = nil, progress: Double? = nil, error: String? = nil) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        if let state { jobs[index].state = state }; if let progress { jobs[index].progress = progress }; jobs[index].error = error
    }

    private func cacheCover(bookID: UUID, store: LibraryStore) async {
        guard let book = store.book(id: bookID), let raw = book.coverURL, let url = URL(string: raw) else { return }
        do {
            let (data, response) = try await session.data(from: url); try validate(response)
            guard response.mimeType?.hasPrefix("image/") == true && data.count < 15_000_000 else { return }
            let relative = "books/\(bookID.uuidString)/cover.jpg"
            let destination = store.url(for: relative)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
            if var current = store.book(id: bookID) { current.coverPath = relative; store.updateBook(current) }
        } catch { /* A missing thumbnail does not make the title unusable. */ }
    }

    private func localized(_ value: Any?) -> String? {
        guard let dictionary = value as? [String: String] else { return nil }
        return dictionary["en"] ?? dictionary.keys.sorted().compactMap { dictionary[$0] }.first
    }

    private func dex(_ path: String, _ query: [URLQueryItem]) async throws -> [String: Any] {
        var components = URLComponents(string: "https://api.mangadex.org\(path)")!
        components.queryItems = query.isEmpty ? nil : query
        // Reserve this request's slot before suspension so concurrent callers stay spaced.
        let slot = max(Date(), lastRequest.addingTimeInterval(0.3))
        let delay = slot.timeIntervalSinceNow
        lastRequest = slot
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        var request = URLRequest(url: components.url!); request.timeoutInterval = 45
        request.setValue("Koma/1.0 (local macOS reader)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try validate(response)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ServiceError.message("Source returned an unexpected response.") }
        if object["result"] as? String == "error" { throw ServiceError.message("MangaDex could not complete the request.") }
        return object
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 429 { throw ServiceError.message("The source rate limit was reached. Wait a minute, then retry.") }
            if status == 403 { throw ServiceError.message("The source denied access (403). Check your connection or the provider's availability.") }
            throw ServiceError.message("The source returned HTTP \(status). Please retry later.")
        }
    }
}

struct AniListMedia: Identifiable {
    var id: Int
    var title: String
    var chapters: Int?
}

enum AniListService {
    static func search(_ title: String) async throws -> [AniListMedia] {
        let data = try await request(query: "query ($search: String) { Page(perPage: 12) { media(search: $search, type: MANGA) { id title { userPreferred } chapters } } }", variables: ["search": title])
        let page = data["Page"] as? [String: Any]
        return (page?["media"] as? [[String: Any]] ?? []).compactMap { item in
            guard let id = item["id"] as? Int else { return nil }
            let titles = item["title"] as? [String: Any]
            return AniListMedia(id: id, title: titles?["userPreferred"] as? String ?? "Untitled", chapters: item["chapters"] as? Int)
        }
    }

    static func verify(token: String) async throws -> String {
        let data = try await request(query: "query { Viewer { id name } }", token: token)
        guard let viewer = data["Viewer"] as? [String: Any], let name = viewer["name"] as? String else { throw ServiceError.message("Could not verify this AniList token.") }
        return name
    }

    static func push(book: Book, progress: Int, token: String) async throws {
        guard let mediaID = book.aniListID else { throw ServiceError.message("Link an AniList manga first.") }
        let status: String
        switch book.status { case .reading: status = "CURRENT"; case .planned: status = "PLANNING"; case .completed: status = "COMPLETED"; case .onHold: status = "PAUSED"; case .dropped: status = "DROPPED" }
        _ = try await request(query: "mutation ($mediaId: Int, $progress: Int, $status: MediaListStatus) { SaveMediaListEntry(mediaId: $mediaId, progress: $progress, status: $status) { id progress status } }", variables: ["mediaId": mediaID, "progress": max(0, progress), "status": status], token: token)
    }

    static func request(query: String, variables: [String: Any] = [:], token: String? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://graphql.anilist.co")!)
        request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        let (body, response) = try await URLSession.shared.data(for: request)
        let object = try JSONSerialization.jsonObject(with: body) as? [String: Any] ?? [:]
        if let errors = object["errors"] as? [[String: Any]], let message = errors.first?["message"] as? String { throw ServiceError.message("AniList: \(message)") }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data = object["data"] as? [String: Any] else { throw ServiceError.message("AniList could not complete the request.") }
        return data
    }
}

enum AniListCredential {
    private static let service = "app.mihonmac.AniList"
    static func load() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "oauth", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ token: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "oauth"]
        if token.isEmpty {
            let deleted = SecItemDelete(query as CFDictionary)
            guard deleted == errSecSuccess || deleted == errSecItemNotFound else { throw ServiceError.message("Keychain could not remove the access token (\(deleted)).") }
            return
        }
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query; insert[kSecValueData as String] = Data(token.utf8)
            let added = SecItemAdd(insert as CFDictionary, nil)
            guard added == errSecSuccess else { throw ServiceError.message("Keychain could not save the access token (\(added)).") }
        } else if status != errSecSuccess { throw ServiceError.message("Keychain could not update the access token (\(status)).") }
    }
}
