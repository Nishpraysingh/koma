import SwiftUI

struct TrackingView: View {
    var bookID: UUID
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @ViewState private var token = ""
    @ViewState private var query = ""
    @ViewState private var matches: [AniListMedia] = []
    @ViewState private var busy = false
    @ViewState private var message: String?
    @ViewState private var connectedName: String?
    @ViewState private var progress = 0

    private var book: Book? { store.book(id: bookID) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AniList tracking").font(.title2.bold())
                    Text(book?.title ?? "Title removed").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(24)
            Divider()
            Form {
                Section("1 · Connect your account") {
                    Text("Create an OAuth client in AniList Developer Settings, obtain an access token using AniList's documented authorization flow, then paste it here. The token is stored only in macOS Keychain and excluded from backups.")
                        .font(.caption).foregroundStyle(.secondary)
                    Link("AniList authentication guide ↗", destination: URL(string: "https://docs.anilist.co/guide/auth/")!)
                    SecureField("OAuth access token", text: $token)
                    HStack {
                        Button("Verify & save token") { verify() }.disabled(token.isEmpty || busy)
                        Button("Disconnect") {
                            do { try AniListCredential.save(""); token = ""; connectedName = nil; message = "Token removed from Keychain." }
                            catch { message = error.localizedDescription }
                        }.disabled(busy)
                        if let connectedName { Label(connectedName, systemImage: "checkmark.seal.fill").foregroundStyle(.green) }
                    }
                }
                Section("2 · Link this manga") {
                    HStack {
                        TextField("Search AniList", text: $query).onSubmit { search() }
                        Button("Search") { search() }.disabled(query.isEmpty || busy)
                    }
                    if let id = book?.aniListID {
                        HStack {
                            Label("Linked to AniList #\(id)", systemImage: "link")
                            Spacer()
                            Link("View ↗", destination: URL(string: "https://anilist.co/manga/\(id)")!)
                            Button("Unlink") { if var current = book { current.aniListID = nil; store.updateBook(current) } }
                        }
                    }
                    ForEach(matches) { media in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(media.title).fontWeight(.medium)
                                Text("#\(media.id)\(media.chapters.map { " · \($0) chapters" } ?? "")").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(book?.aniListID == media.id ? "Linked" : "Link") {
                                if var current = book { current.aniListID = media.id; store.updateBook(current) }
                            }.disabled(book?.aniListID == media.id)
                        }
                    }
                }
                Section("3 · Send an update") {
                    Stepper("Chapter progress: \(progress)", value: $progress, in: 0...100_000)
                    Text("Status: \(book?.status.rawValue ?? "Unknown"). Adjust your local status in the title's details. Confirm the chapter number above: local chapter files and special chapters do not always match AniList numbering.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Send progress & status to AniList") { push() }
                        .buttonStyle(.borderedProminent).tint(.orange).disabled(book?.aniListID == nil || token.isEmpty || busy)
                    Text("This button updates your AniList account. Progress is sent only when you press it.").font(.caption).foregroundStyle(.secondary)
                }
                if let message { Text(message).font(.callout).textSelection(.enabled) }
                if busy { ProgressView().controlSize(.small) }
            }.formStyle(.grouped)
        }
        .frame(width: 640, height: 710)
        .onAppear {
            token = AniListCredential.load(); query = book?.title ?? ""
            progress = Int(book?.chapters.filter(\.isRead).map(\.number).max() ?? 0)
        }
    }

    private func verify() {
        busy = true; message = nil
        Task {
            do {
                let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = try await AniListService.verify(token: clean)
                try AniListCredential.save(clean); token = clean; connectedName = name; message = "Connected as \(name)."
            } catch { message = error.localizedDescription }
            busy = false
        }
    }

    private func search() {
        busy = true; message = nil
        Task {
            do { matches = try await AniListService.search(query); if matches.isEmpty { message = "No matching manga found." } }
            catch { message = error.localizedDescription }
            busy = false
        }
    }

    private func push() {
        guard let book else { return }
        busy = true; message = nil
        Task {
            do { try await AniListService.push(book: book, progress: progress, token: token); message = "AniList updated: chapter \(progress), \(book.status.rawValue)." }
            catch { message = error.localizedDescription }
            busy = false
        }
    }
}
