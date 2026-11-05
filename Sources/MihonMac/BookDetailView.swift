import SwiftUI
import AppKit

struct BookDetailView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var network: NetworkService
    let book: Book
    let openReader: (ReaderSelection) -> Void
    let goBack: () -> Void
    @ViewState private var editing = false
    @ViewState private var tracking = false
    @ViewState private var deleteConfirm = false
    @ViewState private var chapterFilter = "All"
    @ViewState private var descending = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top, spacing: 30) {
                    BookCoverView(book: book).frame(width: 170, height: 245).clipShape(RoundedRectangle(cornerRadius: 9)).shadow(color: .black.opacity(0.13), radius: 10, y: 5)
                    VStack(alignment: .leading, spacing: 14) {
                        Text("\(book.source.uppercased())  /  \(book.status.rawValue.uppercased())").font(.system(size: 9, weight: .semibold)).tracking(1.6).foregroundStyle(Color.komaAccent)
                        Text(book.title).font(.system(size: 32, weight: .medium, design: .serif)).textSelection(.enabled)
                        Text(book.author).font(.system(size: 13)).foregroundStyle(.secondary)
                        if !book.summary.isEmpty { Text(book.summary).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(5).textSelection(.enabled) }
                        HStack(spacing: 8) {
                            if let chapter = book.nextChapter {
                                Button { openReader(ReaderSelection(bookID: book.id, chapterID: chapter.id)) } label: { Label(book.lastOpenedAt == nil ? "Start reading" : "Continue", systemImage: "book").padding(4) }.buttonStyle(.borderedProminent)
                            }
                            Button { var copy = book; copy.favorite.toggle(); store.updateBook(copy) } label: { Image(systemName: book.favorite ? "heart.fill" : "heart") }.help("Favorite")
                            Button("Edit") { editing = true }
                            Menu {
                                Button("Link AniList tracking…") { tracking = true }
                                if book.source != "Local" {
                                    Button("Refresh chapters") { Task { await network.refresh(bookID: book.id, store: store) } }
                                    Button("Download unread chapters") { Task { await network.downloadUnread(bookID: book.id, store: store) } }
                                }
                                Button("Mark all read") { var copy = book; for i in copy.chapters.indices { copy.chapters[i].isRead = true }; copy.status = .completed; store.updateBook(copy) }
                                Button("Mark all unread") { var copy = book; for i in copy.chapters.indices { copy.chapters[i].isRead = false; copy.chapters[i].lastPage = 0 }; copy.status = .planned; store.updateBook(copy) }
                                Divider()
                                Button("Remove from library…", role: .destructive) { deleteConfirm = true }
                            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 25)
                        }
                        HStack { ForEach(book.categories, id: \.self) { Text($0).font(.system(size: 10)).padding(.horizontal, 8).padding(.vertical, 4).background(.quaternary, in: Capsule()) } }
                        Text("\(book.chapters.count) chapters · \(book.downloadedCount) offline · \(Int(book.progress * 100))% read").font(.system(size: 11)).foregroundStyle(.tertiary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if !book.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) { Label("Your notes", systemImage: "note.text").font(.caption.bold()); Text(book.notes).font(.callout).textSelection(.enabled) }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Color.komaAccent.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }
                HStack {
                    Text("Chapters").font(.system(size: 22, weight: .medium, design: .serif))
                    Spacer()
                    Picker("Show", selection: $chapterFilter) { ForEach(["All", "Unread", "Downloaded", "Bookmarked"], id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(width: 145)
                    Button { descending.toggle() } label: { Image(systemName: descending ? "arrow.down" : "arrow.up") }.help("Reverse chapter order")
                }
                LazyVStack(spacing: 0) {
                    ForEach(visibleChapters) { chapter in
                        chapterRow(chapter)
                        Divider().padding(.leading, 43)
                    }
                    if visibleChapters.isEmpty { ContentUnavailableView("No chapters here", systemImage: "book.closed", description: Text(book.source == "Local" ? "Import a comic to get started." : "Refresh chapters or change the filter.")) }
                }
            }.padding(32)
        }
        .sheet(isPresented: $editing) { EditBookView(book: book).environmentObject(store) }
        .sheet(isPresented: $tracking) { TrackingView(bookID: book.id).environmentObject(store).environmentObject(network) }
        .alert("Remove “\(book.title)” from Koma?", isPresented: $deleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { store.deleteBook(book.id); goBack() }
        } message: { Text("The managed copy, downloads, progress, and bookmarks for this title will be removed. Your original imported files stay where they are.") }
    }
    private var visibleChapters: [Chapter] {
        let filtered = book.chapters.filter { chapterFilter == "All" || chapterFilter == "Unread" && !$0.isRead || chapterFilter == "Downloaded" && $0.isDownloaded || chapterFilter == "Bookmarked" && $0.isBookmarked }
        return descending ? Array(filtered.reversed()) : filtered
    }
    private func chapterRow(_ chapter: Chapter) -> some View {
        HStack(spacing: 15) {
            Button { store.markChapter(bookID: book.id, chapterID: chapter.id, read: !chapter.isRead) } label: { Image(systemName: chapter.isRead ? "checkmark.circle.fill" : "circle").foregroundStyle(chapter.isRead ? Color.komaAccent : Color.secondary.opacity(0.5)).font(.system(size: 18)) }.buttonStyle(.plain).help(chapter.isRead ? "Mark unread" : "Mark read")
            Button {
                if chapter.isDownloaded { openReader(ReaderSelection(bookID: book.id, chapterID: chapter.id)) }
                else { Task { await network.download(bookID: book.id, chapterID: chapter.id, store: store) } }
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(chapter.title).font(.system(size: 13, weight: .medium)).foregroundStyle(chapter.isRead ? .secondary : .primary)
                    Text(chapter.isDownloaded ? "\(chapter.pageCount) pages · \(chapter.isRead ? "Read" : chapter.lastPage > 0 ? "Page \(chapter.lastPage + 1)" : "Unread")" : "Not downloaded · click to download")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button { var copy = book; if let i = copy.chapters.firstIndex(where: { $0.id == chapter.id }) { copy.chapters[i].isBookmarked.toggle(); store.updateBook(copy) } } label: { Image(systemName: chapter.isBookmarked ? "bookmark.fill" : "bookmark").foregroundStyle(chapter.isBookmarked ? Color.komaAccent : .secondary) }.buttonStyle(.plain).help("Bookmark chapter")
            if chapter.isDownloaded { Image(systemName: "checkmark.circle").foregroundStyle(.secondary).help("Available offline") }
            else { Button { Task { await network.download(bookID: book.id, chapterID: chapter.id, store: store) } } label: { Image(systemName: "arrow.down.circle") }.buttonStyle(.plain).help("Download chapter").disabled(network.isWorking) }
        }.padding(.vertical, 15).padding(.horizontal, 4)
    }
}

struct EditBookView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @ViewState var book: Book
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit title").font(.title2.bold())
            Form {
                TextField("Title", text: $book.title)
                TextField("Author", text: $book.author)
                Picker("Reading status", selection: $book.status) { ForEach(ReadingStatus.allCases) { Text($0.rawValue).tag($0) } }
                Toggle("Favorite", isOn: $book.favorite)
                Section("Collections") {
                    if store.categories.isEmpty { Text("Create collections from the sidebar first.").foregroundStyle(.secondary) }
                    ForEach(store.categories, id: \.self) { category in
                        Toggle(category, isOn: Binding(get: { book.categories.contains(category) }, set: { enabled in if enabled { book.categories.append(category) } else { book.categories.removeAll { $0 == category } } }))
                    }
                }
                Section("Notes") { TextEditor(text: $book.notes).frame(height: 100).font(.body) }
                Section("Description") { TextEditor(text: $book.summary).frame(height: 80).font(.body) }
            }.formStyle(.grouped)
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Save") { store.updateBook(book); dismiss() }.buttonStyle(.borderedProminent).disabled(book.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 540, height: 650)
    }
}
