import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct WorkspaceView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var network: NetworkService
    @ViewState private var section: WorkspaceSection = .library
    @ViewState private var category: String?
    @ViewState private var selectedBookID: UUID?
    @ViewState private var reader: ReaderSelection?
    @ViewState private var showCategories = false
    @ViewState private var search = ""
    @ViewState private var sort = "Recently added"
    @ViewState private var filter = "All titles"
    @ViewState private var showSettings = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 205, ideal: 220, max: 260)
        } detail: {
            VStack(spacing: 0) {
                workspaceToolbar
                Divider()
                if let id = selectedBookID, let book = store.book(id: id) {
                    BookDetailView(book: book, openReader: { reader = $0 }, goBack: { selectedBookID = nil })
                } else {
                    sectionContent
                }
                if let message = store.statusMessage ?? network.message {
                    HStack {
                        Image(systemName: "info.circle")
                        Text(message).font(.callout).textSelection(.enabled)
                        Spacer()
                        Button { store.statusMessage = nil; network.message = nil } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain)
                    }.padding(12).background(Color.komaAccent.opacity(0.09))
                }
            }
            .background(Color.komaCanvas)
        }
        .sheet(item: $reader) { selection in
            ReaderView(selection: selection).environmentObject(store).frame(minWidth: 900, minHeight: 660)
        }
        .sheet(isPresented: $showCategories) { CategoryManagerView().environmentObject(store) }
        .sheet(isPresented: $showSettings) { AppSettingsView().environmentObject(store).environmentObject(network) }
        .onReceive(NotificationCenter.default.publisher(for: .komaImport)) { _ in importFiles() }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in await store.importURLs([url]) }
                }
            }
            return !providers.isEmpty
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "book.closed.fill").font(.title2).foregroundStyle(.white)
                    .frame(width: 38, height: 42).background(Color.komaAccent, in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 0) {
                    Text("koma").font(.system(size: 28, weight: .bold, design: .rounded)).tracking(-1)
                    Text("A little space to read.").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 32)
            Text("YOUR SPACE").font(.system(size: 10, weight: .semibold)).tracking(1.8).foregroundStyle(.tertiary)
                .padding(.horizontal, 22).padding(.bottom, 10)
            ForEach(WorkspaceSection.allCases) { item in
                Button {
                    section = item; category = nil; selectedBookID = nil; search = ""
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.icon).font(.system(size: 15)).frame(width: 20)
                        Text(item.rawValue).font(.system(size: 13, weight: section == item && category == nil ? .semibold : .regular))
                        Spacer()
                        if item == .library { Text("\(store.books.count)").font(.system(size: 11)).foregroundStyle(.secondary) }
                        if item == .downloads && network.jobs.contains(where: { $0.state == "Downloading" }) {
                            Circle().fill(Color.komaAccent).frame(width: 6, height: 6)
                        }
                    }
                    .foregroundStyle(section == item && category == nil ? Color.komaAccent : .primary)
                    .padding(.horizontal, 13).padding(.vertical, 10)
                    .background(section == item && category == nil ? Color.komaAccent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 9))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.horizontal, 12).padding(.vertical, 1)
            }
            HStack {
                Text("COLLECTIONS").font(.system(size: 10, weight: .semibold)).tracking(1.8).foregroundStyle(.tertiary)
                Spacer()
                Button { showCategories = true } label: { Image(systemName: "plus").font(.system(size: 12)) }.buttonStyle(.plain).help("Manage collections")
            }.padding(.horizontal, 22).padding(.top, 30).padding(.bottom, 10)
            ScrollView {
                VStack(spacing: 3) {
                    ForEach(store.categories, id: \.self) { name in
                        Button { section = .library; category = name; selectedBookID = nil } label: {
                            HStack(spacing: 12) {
                                Circle().fill(collectionColor(name)).frame(width: 7, height: 7)
                                Text(name).font(.system(size: 12)).lineLimit(1)
                                Spacer()
                                Text("\(store.books.filter { $0.categories.contains(name) }.count)").font(.system(size: 10)).foregroundStyle(.secondary)
                            }.padding(.horizontal, 16).padding(.vertical, 9)
                                .background(category == name ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                    if store.categories.isEmpty {
                        Text("Make a home for your favorites.").font(.caption).foregroundStyle(.tertiary).padding(.horizontal, 12)
                    }
                }.padding(.horizontal, 12)
            }
            Spacer(minLength: 10)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) { Circle().fill(.green).frame(width: 6, height: 6); Text("LOCAL LIBRARY").tracking(1.3).font(.system(size: 9, weight: .semibold)) }
                Text("Your stories. On your Mac.").font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10)).padding(16)
            Button { showSettings = true } label: { Label("Settings & backups", systemImage: "gearshape").font(.system(size: 12)).foregroundStyle(.secondary) }
                .buttonStyle(.plain).padding(.horizontal, 24).padding(.bottom, 22)
        }.background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }

    private var workspaceToolbar: some View {
        HStack(spacing: 14) {
            if selectedBookID != nil {
                Button { selectedBookID = nil } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain)
            }
            Text(selectedBookID == nil ? "\(category ?? section.rawValue)" : "Your library").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            Spacer()
            if section == .library && selectedBookID == nil {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                    TextField("Search your library", text: $search).textFieldStyle(.plain).font(.system(size: 12))
                    if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.tertiary) }
                }.padding(9).frame(width: 230).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
            }
            if store.isImporting || network.isWorking { ProgressView().controlSize(.small) }
            Button { Task { await network.refreshLibrary(store: store) } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).help("Check online titles for new chapters").disabled(network.isWorking)
            Button(action: importFiles) { Label("Import", systemImage: "plus").font(.system(size: 12, weight: .semibold)).padding(.horizontal, 5).padding(.vertical, 3) }
                .buttonStyle(.borderedProminent).disabled(store.isImporting)
        }.padding(.horizontal, 28).frame(height: 64)
    }

    @ViewBuilder private var sectionContent: some View {
        switch section {
        case .library: libraryContent
        case .browse: BrowseView()
        case .history: ActivityListView(kind: .history, openReader: { reader = $0 }, openBook: { selectedBookID = $0 })
        case .updates: ActivityListView(kind: .updates, openReader: { reader = $0 }, openBook: { selectedBookID = $0 })
        case .bookmarks: ActivityListView(kind: .bookmarks, openReader: { reader = $0 }, openBook: { selectedBookID = $0 })
        case .downloads: DownloadsView()
        }
    }

    private var visibleBooks: [Book] {
        let filtered = store.books.filter { book in
            (category == nil || book.categories.contains(category!)) &&
            (search.isEmpty || "\(book.title) \(book.author) \(book.tags.joined(separator: " "))".localizedCaseInsensitiveContains(search)) &&
            (filter == "All titles" || filter == "Favorites" && book.favorite || filter == "Unread" && book.unreadCount > 0 || filter == "Downloaded" && book.downloadedCount > 0 || filter == book.status.rawValue)
        }
        return filtered.sorted {
            switch sort {
            case "Title": return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            case "Last read": return ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast)
            case "Unread chapters": return $0.unreadCount > $1.unreadCount
            default: return $0.addedAt > $1.addedAt
            }
        }
    }

    private var libraryContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("THE NEXT CHAPTER IS YOURS").font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(Color.komaAccent)
                        Text(category ?? "Your library").font(.system(size: 34, weight: .semibold, design: .serif)).tracking(-0.9)
                        Text(store.books.isEmpty ? "A home for the stories you love." : "\(store.books.count) titles · \(store.books.reduce(0) { $0 + $1.downloadedCount }) chapters available offline")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "books.vertical").font(.system(size: 32, weight: .ultraLight)).foregroundStyle(.tertiary)
                }
                if store.books.isEmpty {
                    emptyLibrary
                } else {
                    if search.isEmpty && category == nil, let recent = store.books.filter({ $0.lastOpenedAt != nil && $0.status != .completed }).sorted(by: { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }).first {
                        ContinueReadingBanner(book: recent) {
                            if let chapter = recent.nextChapter { reader = ReaderSelection(bookID: recent.id, chapterID: chapter.id) }
                            else { selectedBookID = recent.id }
                        }
                    }
                    HStack(spacing: 12) {
                        Picker("Filter", selection: $filter) {
                            ForEach(["All titles", "Favorites", "Unread", "Downloaded"] + ReadingStatus.allCases.map(\.rawValue), id: \.self) { Text($0).tag($0) }
                        }.labelsHidden().frame(width: 150)
                        Text("\(visibleBooks.count) titles").font(.caption).foregroundStyle(.tertiary)
                        Spacer()
                        Text("SORT BY").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.tertiary)
                        Picker("Sort", selection: $sort) { ForEach(["Recently added", "Title", "Last read", "Unread chapters"], id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(width: 145)
                    }
                    if visibleBooks.isEmpty {
                        ContentUnavailableView.search(text: search)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 155, maximum: 215), spacing: 23)], alignment: .leading, spacing: 28) {
                            ForEach(visibleBooks) { book in
                                BookCardView(book: book) { selectedBookID = book.id }
                            }
                        }
                    }
                }
                HStack {
                    Rectangle().frame(height: 1).foregroundStyle(.quaternary)
                    Text("ONE MORE PAGE.").font(.system(size: 9, weight: .medium)).tracking(2).foregroundStyle(.tertiary).fixedSize()
                    Rectangle().frame(height: 1).foregroundStyle(.quaternary)
                }.padding(.top, 18)
            }.padding(32)
        }
    }

    private var emptyLibrary: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(Color.komaAccent.opacity(0.08)).frame(width: 116, height: 136).rotationEffect(.degrees(-10)).offset(x: -20)
                RoundedRectangle(cornerRadius: 16).fill(Color.komaAccent.opacity(0.15)).frame(width: 110, height: 136).rotationEffect(.degrees(9)).offset(x: 18)
                Image(systemName: "book.pages").font(.system(size: 54, weight: .ultraLight)).foregroundStyle(Color.komaAccent)
            }.padding(.bottom, 8)
            Text("Every library starts with a story.").font(.system(size: 24, weight: .medium, design: .serif))
            Text("Drop a comic here, import your collection, or discover a new title.\nPDF, CBZ, ZIP, and folders of images are welcome.")
                .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
            HStack(spacing: 12) {
                Button(action: importFiles) { Label("Import your first manga", systemImage: "plus").padding(.horizontal, 9).padding(.vertical, 5) }.buttonStyle(.borderedProminent)
                Button("Browse sources") { section = .browse }.buttonStyle(.bordered).controlSize(.large)
            }
            Button("Try the included sample collection") { Task { await store.addSampleLibrary() } }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary).disabled(store.isImporting)
        }.frame(maxWidth: .infinity).padding(.vertical, 65)
            .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 5])).foregroundStyle(.quaternary))
    }

    private func importFiles() {
        let panel = NSOpenPanel()
        panel.title = "Import manga into Koma"
        panel.message = "Choose PDFs, CBZ/ZIP comics, images, or folders. Files are copied into your local library."
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { let urls = panel.urls; Task { await store.importURLs(urls) } }
    }

    private func collectionColor(_ name: String) -> Color {
        let colors: [Color] = [.komaAccent, .teal, .purple, .orange, .blue]
        return colors[name.utf8.reduce(0) { $0 + Int($1) } % colors.count]
    }
}
