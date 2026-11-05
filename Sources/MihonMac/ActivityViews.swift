import SwiftUI

struct ActivityListView: View {
    enum Kind { case history, updates, bookmarks }
    @EnvironmentObject private var store: LibraryStore
    let kind: Kind
    let openReader: (ReaderSelection) -> Void
    let openBook: (UUID) -> Void
    private var title: String { kind == .history ? "Your reading journey" : kind == .updates ? "The latest chapters" : "Saved for another moment" }
    private var subtitle: String { kind == .history ? "Every page brings you a little further." : kind == .updates ? "Unread chapters, with the newest additions first." : "Page bookmarks and chapters you want to return to." }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) { Text(title).font(.system(size: 31, weight: .medium, design: .serif)); Text(subtitle).font(.callout).foregroundStyle(.secondary) }
                switch kind {
                case .history:
                    if store.history.isEmpty { empty("No history yet", "Start reading and your recent chapters will appear here.") }
                    ForEach(store.history.sorted { $0.date > $1.date }) { event in
                        if let book = store.book(id: event.bookID), let chapter = book.chapters.first(where: { $0.id == event.chapterID }) {
                            activityRow(book: book, chapter: chapter, detail: "Page \(event.page + 1) · \(event.date.formatted(date: .abbreviated, time: .shortened))")
                        }
                    }
                case .updates:
                    if unread.isEmpty { empty("You're all caught up", "Refresh online titles to check for more chapters.") }
                    ForEach(unread, id: \.chapter.id) { item in
                        activityRow(book: item.book, chapter: item.chapter, detail: "Added \(item.chapter.addedAt.formatted(date: .abbreviated, time: .omitted)) · \(item.chapter.isDownloaded ? "Offline" : "Online")")
                    }
                case .bookmarks:
                    if store.bookmarks.isEmpty && chapterBookmarks.isEmpty { empty("Keep your favorite moments", "Use the bookmark button in the reader to save a page.") }
                    ForEach(store.bookmarks.sorted { $0.createdAt > $1.createdAt }) { mark in
                        if let book = store.book(id: mark.bookID), let chapter = book.chapters.first(where: { $0.id == mark.chapterID }) {
                            HStack {
                                activityRow(book: book, chapter: chapter, detail: "Page \(mark.page + 1)\(mark.note.isEmpty ? "" : " · \(mark.note)")", page: mark.page)
                                Button { store.toggleBookmark(bookID: mark.bookID, chapterID: mark.chapterID, page: mark.page) } label: { Image(systemName: "bookmark.slash") }.buttonStyle(.plain).help("Remove page bookmark")
                            }
                        }
                    }
                    ForEach(chapterBookmarks, id: \.chapter.id) { item in activityRow(book: item.book, chapter: item.chapter, detail: "Bookmarked chapter") }
                }
            }.padding(32)
        }
    }
    private struct Item { var book: Book; var chapter: Chapter }
    private var unread: [Item] { store.books.flatMap { book in book.chapters.filter { !$0.isRead }.map { Item(book: book, chapter: $0) } }.sorted { $0.chapter.addedAt > $1.chapter.addedAt } }
    private var chapterBookmarks: [Item] { store.books.flatMap { book in book.chapters.filter(\.isBookmarked).map { Item(book: book, chapter: $0) } } }
    private func empty(_ title: String, _ detail: String) -> some View { ContentUnavailableView(title, systemImage: kind == .history ? "clock" : kind == .updates ? "checkmark.seal" : "bookmark", description: Text(detail)).frame(maxWidth: .infinity).padding(.top, 70) }
    private func activityRow(book: Book, chapter: Chapter, detail: String, page: Int? = nil) -> some View {
        HStack(spacing: 18) {
            BookCoverView(book: book).frame(width: 48, height: 68).clipShape(RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 6) {
                Button(book.title) { openBook(book.id) }.font(.system(size: 14, weight: .semibold)).buttonStyle(.plain)
                Text(chapter.title).font(.system(size: 12)).foregroundStyle(.secondary)
                Text(detail).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Spacer()
            Button(chapter.isDownloaded ? "Read" : "View title") {
                if chapter.isDownloaded {
                    if let page { var copy = book; if let index = copy.chapters.firstIndex(where: { $0.id == chapter.id }) { copy.chapters[index].lastPage = page; store.updateBook(copy) } }
                    openReader(ReaderSelection(bookID: book.id, chapterID: chapter.id))
                } else { openBook(book.id) }
            }.buttonStyle(.bordered)
        }.padding(16).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct DownloadsView: View {
    @EnvironmentObject private var network: NetworkService
    @EnvironmentObject private var store: LibraryStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) { Text("Ready for offline").font(.system(size: 31, weight: .medium, design: .serif)); Text("\(store.books.reduce(0) { $0 + $1.downloadedCount }) chapters stored on this Mac.").font(.callout).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Cancel downloads") { network.cancelDownloads() }.disabled(!network.isWorking)
                    Button("Clear finished") { network.clearFinishedJobs() }
                }
                if network.jobs.isEmpty {
                    ContentUnavailableView("Take your stories with you", systemImage: "arrow.down.circle", description: Text("Add a title from Browse sources, then download chapters from its details.\nImported comics are already available offline.")).padding(.top, 80).frame(maxWidth: .infinity)
                }
                ForEach(network.jobs) { job in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text(job.title).font(.headline); Spacer(); Text(job.state).foregroundStyle(.secondary).font(.caption) }
                        ProgressView(value: job.progress)
                        if let error = job.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                    }.padding(18).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                }
            }.padding(32)
        }
    }
}
