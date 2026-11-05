import AppKit
import SwiftUI

struct ReaderView: View {
    let selection: ReaderSelection
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @ViewState private var chapterID: UUID?
    @ViewState private var document: ReaderDocument?
    @ViewState private var page = 0
    @ViewState private var zoom = 1.0
    @ViewState private var error: String?
    @ViewState private var loading = true
    @ViewState private var showContents = false
    @ViewState private var renderConfirmed = false
    @ViewState private var completionVisible = false
    @ViewState private var restoringScroll = false
    @ViewState private var pendingBookmarkPage: Int?
    @ViewState private var pendingVerticalPage: Int?
    @ViewState private var progressTask: Task<Void, Never>?

    private var book: Book? { store.book(id: selection.bookID) }
    private var currentID: UUID { chapterID ?? selection.chapterID }
    private var chapter: Chapter? { book?.chapters.first { $0.id == currentID } }
    private var pageCount: Int { document?.pageCount ?? 0 }
    private var isBookmarked: Bool { store.bookmarks.contains { $0.bookID == selection.bookID && $0.chapterID == currentID && $0.page == page } }
    private var background: Color {
        switch store.preferences.background {
        case "White": return .white
        case "Sepia": return Color(red: 0.89, green: 0.85, blue: 0.76)
        case "Gray": return Color(white: 0.19)
        default: return Color(white: 0.045)
        }
    }
    private var lastVisiblePage: Int {
        min(pageCount - 1, page + (store.preferences.mode == .doublePage ? 1 : 0))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.06))
            HStack(spacing: 0) {
                if showContents { contents.frame(width: 248); Divider() }
                ZStack {
                    background
                    if loading {
                        ProgressView("Opening chapter…").tint(.orange).foregroundStyle(.secondary)
                    } else if let error {
                        ContentUnavailableView {
                            Label("Unable to open chapter", systemImage: "doc.questionmark")
                        } description: {
                            Text(error)
                        } actions: {
                            Button("Try again") { Task { await loadChapter() } }
                            Button("Close reader") { dismiss() }
                        }
                    } else if let document {
                        GeometryReader { geometry in
                            if store.preferences.mode == .vertical {
                                scrollingPages(document, size: geometry.size)
                            } else {
                                pagedPages(document, size: geometry.size)
                            }
                        }
                    }
                }
                .clipped()
            }
            Divider().overlay(Color.white.opacity(0.06))
            footer
        }
        .frame(minWidth: 820, minHeight: 580)
        .background(Color(red: 0.075, green: 0.08, blue: 0.095))
        .preferredColorScheme(.dark)
        .tint(.orange)
        .background(ReaderKeyboardHandler(onKey: handleKey))
        .task(id: currentID) { await loadChapter() }
        .onChange(of: page) { _, _ in
            renderConfirmed = false
            if store.preferences.mode == .vertical { persistProgress() }
        }
        .onChange(of: store.preferences.mode) { _, newMode in
            renderConfirmed = false
            completionVisible = false
            if newMode == .vertical {
                pendingVerticalPage = page
                restoringScroll = true
            } else { restoringScroll = false }
        }
        .onDisappear {
            progressTask?.cancel()
            flushProgress()
            Task { await ContentLoader.shared.clearCache() }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: { Image(systemName: "chevron.down").font(.system(size: 15, weight: .semibold)) }
                .buttonStyle(.plain).help("Close reader (Escape)")
            Button { withAnimation(.easeInOut(duration: 0.18)) { showContents.toggle() } } label: { Image(systemName: "sidebar.left") }
                .buttonStyle(.plain).help("Chapters and bookmarks")
            VStack(alignment: .leading, spacing: 3) {
                Text(book?.title ?? "Reader").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(chapter?.title ?? "Chapter").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 10)
            Picker("Reading mode", selection: Binding(get: { store.preferences.mode }, set: { mode in
                // Guard geometry updates before the vertical view enters the hierarchy.
                pendingVerticalPage = page
                restoringScroll = mode == .vertical
                store.preferences.mode = mode
            })) {
                Image(systemName: "rectangle.portrait").tag(ReaderMode.paged).help("Single page")
                Image(systemName: "book").tag(ReaderMode.doublePage).help("Double page")
                Image(systemName: "scroll").tag(ReaderMode.vertical).help("Vertical scroll")
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 128)
            Menu {
                Picker("Fit", selection: $store.preferences.fit) {
                    ForEach(ReaderFit.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Background", selection: $store.preferences.background) {
                    ForEach(["Black", "Gray", "Sepia", "White"], id: \.self) { Text($0).tag($0) }
                }
                Toggle("Right to left", isOn: $store.preferences.rightToLeft)
                Toggle("Show page numbers", isOn: $store.preferences.showPageNumbers)
                Divider()
                Button("Reset zoom") { zoom = 1 }
                Button("Toggle full screen") { NSApp.keyWindow?.toggleFullScreen(nil) }
            } label: { Image(systemName: "slider.horizontal.3") }
                .menuStyle(.borderlessButton).fixedSize().help("Reader settings")
            Button { NSApp.keyWindow?.toggleFullScreen(nil) } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                .buttonStyle(.plain).help("Toggle full screen")
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 13) {
                Button { move(-1) } label: { Image(systemName: "chevron.left") }.disabled(page == 0)
                    .help("Previous page")
                if pageCount > 1 {
                    Slider(value: Binding(get: { Double(page) }, set: { jumpToPage(Int($0.rounded())) }), in: 0...Double(pageCount - 1), step: 1)
                        .accessibilityLabel("Page")
                        .frame(maxWidth: .infinity)
                } else { Capsule().fill(Color.white.opacity(0.1)).frame(height: 3) }
                Text(pageCount == 0 ? "—" : "\(page + 1) / \(pageCount)")
                    .monospacedDigit().font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).frame(minWidth: 68)
                Button { move(1) } label: { Image(systemName: "chevron.right") }.disabled(pageCount == 0)
                    .help(page >= pageCount - 1 ? "Finish chapter / next chapter" : "Next page")
                Divider().frame(height: 18)
                Button { store.toggleBookmark(bookID: selection.bookID, chapterID: currentID, page: page) } label: {
                    Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                        .foregroundStyle(isBookmarked ? Color.orange : Color.primary)
                }.help("Bookmark page (B)").disabled(pageCount == 0)
                Button { zoom = max(0.5, zoom - 0.25) } label: { Image(systemName: "minus.magnifyingglass") }.help("Zoom out")
                Text("\(Int(zoom * 100))% ").monospacedDigit().font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 42)
                Button { zoom = min(3, zoom + 0.25) } label: { Image(systemName: "plus.magnifyingglass") }.help("Zoom in")
            }
            .buttonStyle(.plain)
            HStack {
                Button { switchChapter(-1) } label: { Label("Previous chapter", systemImage: "backward.end") }
                    .disabled(adjacentChapter(-1) == nil)
                Spacer()
                Text(store.preferences.rightToLeft ? "Right to left · ← next · → previous · Space next · B bookmark" : "Left to right · → next · ← previous · Space next · B bookmark")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                Button {
                    if adjacentChapter(1) == nil { finishChapter() }
                    else { switchChapter(1) }
                } label: {
                    Label(adjacentChapter(1) == nil ? "Mark chapter read" : "Next chapter", systemImage: "forward.end")
                }.disabled(pageCount == 0)
            }
            .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 22).padding(.vertical, 13)
    }

    private var contents: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("CHAPTERS").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary).tracking(1.4).padding(.bottom, 8)
                ForEach(book?.chapters ?? []) { chapter in
                    Button {
                        if chapter.isDownloaded { selectChapter(chapter.id) }
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: chapter.isRead ? "checkmark.circle.fill" : (chapter.isDownloaded ? "doc.richtext" : "icloud.and.arrow.down"))
                                .foregroundStyle(chapter.id == currentID ? Color.orange : .secondary)
                            Text(chapter.title).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(10).background(chapter.id == currentID ? Color.orange.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).disabled(!chapter.isDownloaded)
                }
                let bookmarks = store.bookmarks.filter { $0.bookID == selection.bookID }
                if !bookmarks.isEmpty {
                    Text("BOOKMARKS").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary).tracking(1.4).padding(.top, 24)
                    ForEach(bookmarks) { bookmark in
                        Button {
                            if bookmark.chapterID == currentID { jumpToPage(bookmark.page) }
                            else { pendingBookmarkPage = bookmark.page; selectChapter(bookmark.chapterID) }
                        } label: {
                            Label("Page \(bookmark.page + 1) · \(book?.chapters.first { $0.id == bookmark.chapterID }?.title ?? "Chapter")", systemImage: "bookmark.fill")
                                .lineLimit(2).padding(.vertical, 6)
                        }.buttonStyle(.plain).foregroundStyle(.orange)
                    }
                }
            }.font(.system(size: 12)).padding(16)
        }.background(Color.white.opacity(0.025))
    }

    private func pagedPages(_ document: ReaderDocument, size: CGSize) -> some View {
        let indices = store.preferences.mode == .doublePage && page + 1 < document.pageCount ? [page, page + 1] : [page]
        let ordered = store.preferences.rightToLeft ? Array(indices.reversed()) : indices
        let slotWidth = max(100, (size.width - 32) / CGFloat(ordered.count))
        return ScrollView([.horizontal, .vertical]) {
            HStack(spacing: 4) {
                ForEach(ordered, id: \.self) { index in
                    let dimensions = fittedSize(document: document, index: index, viewport: CGSize(width: slotWidth, height: size.height - 24))
                    ReaderPageImage(document: document, index: index) {
                        if index == lastVisiblePage { renderConfirmed = true; completionVisible = lastVisiblePage == pageCount - 1; persistProgress() }
                    }
                    .frame(width: dimensions.width * zoom, height: dimensions.height * zoom)
                    .overlay(alignment: .bottomTrailing) {
                        if store.preferences.showPageNumbers { pageBadge(index + 1).padding(8) }
                    }
                }
            }
            .padding(12)
            .frame(minWidth: size.width, minHeight: size.height)
        }
        .defaultScrollAnchor(.center)
    }

    private func scrollingPages(_ document: ReaderDocument, size: CGSize) -> some View {
        ScrollViewReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(spacing: 8) {
                    ForEach(0..<document.pageCount, id: \.self) { index in
                        let width = max(100, (size.width - 32) * zoom)
                        ReaderPageImage(document: document, index: index) {
                            if index == page { renderConfirmed = true; persistProgress() }
                        }
                            .frame(width: width, height: width / document.aspectRatio(at: index))
                            .overlay(alignment: .bottomTrailing) {
                                if store.preferences.showPageNumbers { pageBadge(index + 1).padding(10) }
                            }
                            .background(GeometryReader { item in
                                Color.clear.preference(key: ReaderPageVisibilityKey.self, value: [ReaderVisiblePage(index: index, frame: item.frame(in: .named("readerScroll")))])
                            })
                            .id(index)
                    }
                }
                .padding(16)
                .frame(minWidth: size.width)
            }
            .coordinateSpace(name: "readerScroll")
            .onPreferenceChange(ReaderPageVisibilityKey.self) { values in
                guard !restoringScroll else { return }
                let visible = values.filter { $0.frame.maxY > 0 && $0.frame.minY < size.height }
                let atEnd = values.contains { $0.index == document.pageCount - 1 && $0.frame.maxY <= size.height + 24 && $0.frame.maxY > 0 }
                if completionVisible != atEnd { completionVisible = atEnd; persistProgress() }
                if let closest = visible.min(by: { abs($0.frame.midY - size.height / 2) < abs($1.frame.midY - size.height / 2) }), closest.index != page {
                    page = closest.index
                }
            }
            .task(id: document.url) {
                restoringScroll = true
                let target = pendingVerticalPage ?? page
                pendingVerticalPage = nil
                // LazyVStack must lay out before a distant page can be restored.
                await Task.yield()
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                proxy.scrollTo(target, anchor: .top)
                do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
                proxy.scrollTo(target, anchor: .top)
                page = target
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                restoringScroll = false
            }
            .onChange(of: page) { _, newPage in
                // Only jump if this page is outside the visible region. User scrolling drives page updates.
                if restoringScroll { proxy.scrollTo(newPage, anchor: .top) }
            }
            .onChange(of: zoom) { _, _ in proxy.scrollTo(page, anchor: .top) }
        }
    }

    private func pageBadge(_ number: Int) -> some View {
        Text("\(number)").font(.system(size: 10, weight: .medium)).monospacedDigit()
            .foregroundStyle(.white).padding(.horizontal, 7).padding(.vertical, 4)
            .background(.black.opacity(0.55), in: Capsule())
    }

    private func fittedSize(document: ReaderDocument, index: Int, viewport: CGSize) -> CGSize {
        let aspect = document.aspectRatio(at: index)
        switch store.preferences.fit {
        case .width: return CGSize(width: viewport.width, height: viewport.width / aspect)
        case .actual: return document.pageSizes[index]
        case .page:
            let width = min(viewport.width, viewport.height * aspect)
            return CGSize(width: width, height: width / aspect)
        }
    }

    @MainActor private func loadChapter() async {
        progressTask?.cancel()
        loading = true; error = nil; document = nil; renderConfirmed = false; completionVisible = false; zoom = 1
        guard let chapter, let path = chapter.relativePath else {
            error = "Download this chapter before reading it."; loading = false; return
        }
        let requestedID = currentID
        do {
            let loaded = try await ContentLoader.shared.load(store.url(for: path))
            try Task.checkCancellation()
            guard currentID == requestedID else { return }
            page = min(max(0, pendingBookmarkPage ?? chapter.lastPage), loaded.pageCount - 1)
            pendingBookmarkPage = nil
            document = loaded; loading = false
            if var book = book {
                book.lastOpenedAt = Date()
                if book.status == .planned { book.status = .reading }
                if let index = book.chapters.firstIndex(where: { $0.id == requestedID }) { book.chapters[index].pageCount = loaded.pageCount }
                store.updateBook(book)
            }
        } catch is CancellationError { return }
        catch { self.error = error.localizedDescription; loading = false }
    }

    private func persistProgress() {
        guard pageCount > 0 else { return }
        progressTask?.cancel()
        let bookID = selection.bookID, chapterID = currentID, savedPage = page, count = pageCount
        progressTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
            store.recordProgress(bookID: bookID, chapterID: chapterID, page: savedPage, pageCount: count, allowCompletion: false)
            if store.preferences.autoMarkRead && count > 1 && completionVisible && currentID == chapterID {
                finishChapter()
            }
        }
    }

    private func finishChapter() {
        guard var book, let index = book.chapters.firstIndex(where: { $0.id == currentID }), pageCount > 0 else { return }
        book.chapters[index].isRead = true
        book.chapters[index].lastReadAt = Date()
        book.chapters[index].lastPage = pageCount - 1
        book.lastOpenedAt = Date()
        if book.chapters.allSatisfy(\.isRead) { book.status = .completed }
        else if book.status == .planned { book.status = .reading }
        store.updateBook(book)
    }

    private func flushProgress() {
        guard pageCount > 0 else { return }
        store.recordProgress(bookID: selection.bookID, chapterID: currentID, page: page, pageCount: pageCount, allowCompletion: false)
    }

    private func move(_ delta: Int) {
        guard pageCount > 0 else { return }
        let step = store.preferences.mode == .doublePage ? 2 : 1
        if delta > 0 && lastVisiblePage >= pageCount - 1 {
            finishChapter()
            if adjacentChapter(1) != nil { switchChapter(1) }
            return
        }
        if delta < 0 && page == 0 { return }
        jumpToPage(page + delta * step)
    }

    private func jumpToPage(_ target: Int) {
        if store.preferences.mode == .vertical { restoringScroll = true }
        completionVisible = false
        page = min(max(0, target), max(0, pageCount - 1))
        if store.preferences.mode == .vertical {
            Task { try? await Task.sleep(for: .milliseconds(350)); restoringScroll = false }
        }
    }

    private func adjacentChapter(_ delta: Int) -> Chapter? {
        guard let chapters = book?.chapters, let index = chapters.firstIndex(where: { $0.id == currentID }) else { return nil }
        let target = index + delta
        guard chapters.indices.contains(target), chapters[target].isDownloaded else { return nil }
        return chapters[target]
    }
    private func switchChapter(_ delta: Int) {
        if let target = adjacentChapter(delta) { selectChapter(target.id) }
    }
    private func selectChapter(_ id: UUID) {
        guard id != currentID else { return }
        progressTask?.cancel()
        flushProgress()
        chapterID = id
    }
    private func handleKey(_ key: UInt16) -> Bool {
        switch key {
        case 53: dismiss()
        case 123: move(store.preferences.rightToLeft ? 1 : -1)
        case 124: move(store.preferences.rightToLeft ? -1 : 1)
        case 49, 125: move(1)
        case 126: move(-1)
        case 115: jumpToPage(0)
        case 119: jumpToPage(max(0, pageCount - 1))
        case 24, 69: zoom = min(3, zoom + 0.25)
        case 27, 78: zoom = max(0.5, zoom - 0.25)
        case 11:
            if pageCount > 0 { store.toggleBookmark(bookID: selection.bookID, chapterID: currentID, page: page) }
        default: return false
        }
        return true
    }
}

private struct ReaderPageImage: View {
    let document: ReaderDocument
    let index: Int
    let onLoaded: () -> Void
    @ViewState private var image: NSImage?
    @ViewState private var error: String?
    var body: some View {
        ZStack {
            if let image { Image(nsImage: image).resizable().interpolation(.high).scaledToFit() }
            else if let error { VStack(spacing: 12) { Image(systemName: "exclamationmark.triangle"); Text(error).font(.caption).multilineTextAlignment(.center) }.foregroundStyle(.secondary).padding() }
            else { ProgressView().tint(.orange) }
        }
        .task(id: "\(document.url.path)#\(index)") {
            image = nil; error = nil
            do {
                let loaded = try await ContentLoader.shared.image(in: document, page: index)
                try Task.checkCancellation()
                image = loaded; error = nil; onLoaded()
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
}

private struct ReaderVisiblePage: Equatable {
    let index: Int
    let frame: CGRect
}
private struct ReaderPageVisibilityKey: PreferenceKey {
    static var defaultValue: [ReaderVisiblePage] = []
    static func reduce(value: inout [ReaderVisiblePage], nextValue: () -> [ReaderVisiblePage]) { value.append(contentsOf: nextValue()) }
}

private struct ReaderKeyboardHandler: NSViewRepresentable {
    let onKey: (UInt16) -> Bool
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.onKey = onKey
        context.coordinator.view = view
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak coordinator = context.coordinator] event in
            guard let coordinator, let window = coordinator.view?.window, event.window === window,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  !(window.firstResponder is NSTextView) else { return event }
            return coordinator.onKey?(event.keyCode) == true ? nil : event
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) { context.coordinator.onKey = onKey }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
    }
    class Coordinator {
        weak var view: NSView?
        var monitor: Any?
        var onKey: ((UInt16) -> Bool)?
    }
}
