import SwiftUI
import AppKit

struct BookCoverView: View {
    @EnvironmentObject private var store: LibraryStore
    let book: Book
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: coverColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                if let path = book.coverPath, let image = NSImage(contentsOf: store.url(for: path)) {
                    Image(nsImage: image).resizable().scaledToFill()
                } else if let address = book.coverURL, let url = URL(string: address) {
                    AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { placeholder }
                } else { placeholder }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
    }
    private var placeholder: some View {
        VStack(spacing: 18) {
            Text(book.source.uppercased()).font(.system(size: 8, weight: .medium)).tracking(3)
            Spacer()
            Image(systemName: "moonphase.waning.crescent").font(.system(size: 45, weight: .ultraLight)).opacity(0.65)
            Text(book.title.uppercased()).font(.system(size: 21, weight: .medium, design: .serif)).tracking(1).multilineTextAlignment(.center)
            Spacer()
            Text(book.author).font(.system(size: 9)).tracking(2)
        }.padding(20).foregroundStyle(.white.opacity(0.9))
    }
    private var coverColors: [Color] {
        let palettes: [[Color]] = [[Color(red: 0.12, green: 0.27, blue: 0.29), .black], [Color(red: 0.69, green: 0.32, blue: 0.20), Color(red: 0.25, green: 0.13, blue: 0.16)], [Color(red: 0.34, green: 0.31, blue: 0.46), Color(red: 0.15, green: 0.14, blue: 0.24)]]
        return palettes[book.title.utf8.reduce(0) { $0 + Int($1) } % palettes.count]
    }
}

struct BookCardView: View {
    @EnvironmentObject private var store: LibraryStore
    let book: Book
    let action: () -> Void
    @ViewState private var hovered = false
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                BookCoverView(book: book)
                    .aspectRatio(0.69, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topTrailing) {
                        if book.unreadCount > 0 {
                            Text("\(book.unreadCount)").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 5).background(Color.komaAccent, in: Capsule()).padding(9)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if book.source == "Local" || book.downloadedCount > 0 {
                            Label("OFFLINE", systemImage: "arrow.down.circle.fill").font(.system(size: 8, weight: .semibold)).tracking(0.8)
                                .foregroundStyle(.white).padding(6).background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 5)).padding(9)
                        }
                    }
                    .shadow(color: .black.opacity(hovered ? 0.2 : 0.1), radius: hovered ? 12 : 6, x: 0, y: 4)
                    .offset(y: hovered ? -3 : 0)
                Text(book.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                HStack {
                    Text(book.author).lineLimit(1)
                    Spacer(minLength: 2)
                    if book.favorite { Image(systemName: "heart.fill").foregroundStyle(Color.komaAccent) }
                }.font(.system(size: 10)).foregroundStyle(.secondary)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.06))
                        Capsule().fill(Color.komaAccent.opacity(0.65)).frame(width: proxy.size.width * book.progress)
                    }
                }.frame(height: 2)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovered = $0 }.animation(.easeOut(duration: 0.16), value: hovered)
        .contextMenu {
            Button(book.favorite ? "Remove from favorites" : "Add to favorites") { var copy = book; copy.favorite.toggle(); store.updateBook(copy) }
            Button("Mark all chapters read") { var copy = book; for index in copy.chapters.indices { copy.chapters[index].isRead = true }; copy.status = .completed; store.updateBook(copy) }
            Button("Mark all chapters unread") { var copy = book; for index in copy.chapters.indices { copy.chapters[index].isRead = false; copy.chapters[index].lastPage = 0 }; copy.status = .planned; store.updateBook(copy) }
        }
    }
}

struct ContinueReadingBanner: View {
    let book: Book
    let action: () -> Void
    var body: some View {
        HStack(spacing: 24) {
            BookCoverView(book: book).frame(width: 75, height: 105).clipShape(RoundedRectangle(cornerRadius: 5)).rotationEffect(.degrees(-5)).shadow(color: .black.opacity(0.2), radius: 8, y: 6)
            VStack(alignment: .leading, spacing: 8) {
                Text("PICK UP WHERE YOU LEFT OFF").font(.system(size: 9, weight: .semibold)).tracking(1.8).foregroundStyle(Color.komaAccent)
                Text(book.title).font(.system(size: 23, weight: .medium, design: .serif)).lineLimit(1)
                if let chapter = book.nextChapter {
                    Text("\(chapter.title) · Page \(chapter.lastPage + 1)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: action) { Label("Continue reading", systemImage: "arrow.right").labelStyle(.titleAndIcon).padding(.horizontal, 6).padding(.vertical, 4) }.buttonStyle(.borderedProminent)
        }.padding(.horizontal, 28).padding(.vertical, 22).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.komaAccent.opacity(0.065), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct CategoryManagerView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @ViewState private var name = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Your collections").font(.title2.bold())
            Text("Organize titles into as many collections as you like.").foregroundStyle(.secondary)
            HStack { TextField("New collection", text: $name).onSubmit(add); Button("Add", action: add).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            List {
                ForEach(store.categories, id: \.self) { category in
                    HStack { Label(category, systemImage: "folder"); Spacer(); Button { store.removeCategory(category) } label: { Image(systemName: "minus.circle").foregroundStyle(.secondary) }.buttonStyle(.plain) }
                }
            }.frame(height: 220)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 460)
    }
    private func add() { store.addCategory(name); name = "" }
}
