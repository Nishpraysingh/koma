import Foundation

enum ReadingStatus: String, Codable, CaseIterable, Identifiable {
    case reading = "Reading", planned = "Plan to read", completed = "Completed", onHold = "On hold", dropped = "Dropped"
    var id: String { rawValue }
}

struct Chapter: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var number: Double = 1
    var relativePath: String? = nil
    var pageCount: Int = 0
    var lastPage: Int = 0
    var isRead: Bool = false
    var isBookmarked: Bool = false
    var remoteID: String? = nil
    var addedAt: Date = Date()
    var lastReadAt: Date? = nil
    var isDownloaded: Bool { relativePath != nil }
}

struct Book: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var author: String = "Unknown author"
    var summary: String = ""
    var coverPath: String? = nil
    var coverURL: String? = nil
    var categories: [String] = []
    var tags: [String] = []
    var status: ReadingStatus = .planned
    var favorite: Bool = false
    var notes: String = ""
    var chapters: [Chapter] = []
    var source: String = "Local"
    var remoteID: String? = nil
    var aniListID: Int? = nil
    var addedAt: Date = Date()
    var lastOpenedAt: Date? = nil
    var lastUpdatedAt: Date = Date()
    var unreadCount: Int { chapters.filter { !$0.isRead }.count }
    var downloadedCount: Int { chapters.filter(\.isDownloaded).count }
    var progress: Double { chapters.isEmpty ? 0 : Double(chapters.filter(\.isRead).count) / Double(chapters.count) }
    var nextChapter: Chapter? {
        let unfinished = chapters.filter { !$0.isRead && $0.isDownloaded }
        if let recent = unfinished.filter({ $0.lastReadAt != nil }).max(by: { ($0.lastReadAt ?? .distantPast) < ($1.lastReadAt ?? .distantPast) }) {
            return recent
        }
        return unfinished.first ?? chapters.first { $0.isDownloaded }
    }
}

struct PageBookmark: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var bookID: UUID
    var chapterID: UUID
    var page: Int
    var note: String = ""
    var createdAt: Date = Date()
}

struct ReadingEvent: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var bookID: UUID
    var chapterID: UUID
    var page: Int
    var date: Date = Date()
}

enum ReaderMode: String, Codable, CaseIterable, Identifiable {
    case paged = "Single page", doublePage = "Double page", vertical = "Vertical scroll"
    var id: String { rawValue }
}
enum ReaderFit: String, Codable, CaseIterable, Identifiable {
    case page = "Fit page", width = "Fit width", actual = "Actual size"
    var id: String { rawValue }
}
struct ReaderPreferences: Codable, Equatable {
    var mode: ReaderMode = .paged
    var fit: ReaderFit = .page
    var rightToLeft: Bool = true
    var background: String = "Black"
    var theme: String = "System"
    var showPageNumbers: Bool = true
    var autoMarkRead: Bool = true
    var updateOnLaunch: Bool = false
    var updateIntervalHours: Int = 0
    var language: String = "en"
    var dataSaver: Bool = false
}

struct LibrarySnapshot: Codable {
    var version: Int = 1
    var books: [Book] = []
    var categories: [String] = []
    var bookmarks: [PageBookmark] = []
    var history: [ReadingEvent] = []
    var preferences: ReaderPreferences = ReaderPreferences()
}

struct ReaderSelection: Identifiable, Hashable {
    var bookID: UUID
    var chapterID: UUID
    var id: String { "\(bookID)-\(chapterID)" }
}
