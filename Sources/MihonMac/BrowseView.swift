import SwiftUI

struct BrowseView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var network: NetworkService
    @ViewState private var query = ""
    @ViewState private var results: [CatalogEntry] = []
    @ViewState private var loading = false
    @ViewState private var error: String?
    @ViewState private var adding = Set<String>()
    @ViewState private var searchTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DISCOVER SOMETHING NEW").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(.orange)
                        Text("Browse").font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("Find your next read. Download chapters to keep them offline.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label("MangaDex", systemImage: "network").font(.callout.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 8).background(.quaternary, in: Capsule())
                }
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search titles on MangaDex", text: $query).textFieldStyle(.plain).onSubmit { runSearch() }
                    if !query.isEmpty { Button { query = ""; runSearch() } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary) }
                    Button("Search", action: runSearch).buttonStyle(.borderedProminent).tint(.orange).disabled(loading)
                }.padding(12).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))

                HStack {
                    Text(query.isEmpty ? "Popular on MangaDex" : "Search results").font(.title3.weight(.semibold))
                    Spacer()
                    Text("\(results.count) titles · safe & suggestive catalog").font(.caption).foregroundStyle(.secondary)
                }
                if loading {
                    ProgressView("Finding stories…").frame(maxWidth: .infinity).padding(70)
                } else if let error {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark").font(.largeTitle).foregroundStyle(.orange)
                        Text("The source is unavailable").font(.headline)
                        Text(error).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 500)
                        Button("Try again", action: runSearch)
                        Text("Your local library and downloaded chapters still work offline.").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(55)
                } else if results.isEmpty {
                    ContentUnavailableView("No titles found", systemImage: "books.vertical", description: Text("Try another title or fewer search terms."))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 165, maximum: 230), spacing: 22)], alignment: .leading, spacing: 26) {
                        ForEach(results) { entry in catalogCard(entry) }
                    }
                }
                Text("MangaDex is the currently supported online source. Android APK extensions cannot run on macOS. Only chapters hosted by MangaDex are imported; external-provider links are excluded.")
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 10)
            }.padding(32)
        }
        .task { if results.isEmpty { runSearch() } }
        .onDisappear { searchTask?.cancel(); loading = false }
    }

    private func catalogCard(_ entry: CatalogEntry) -> some View {
        let exists = store.books.contains { $0.remoteID == entry.id && $0.source == "MangaDex" }
        return VStack(alignment: .leading, spacing: 9) {
            AsyncImage(url: entry.coverURL.flatMap(URL.init(string:))) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else { ZStack { LinearGradient(colors: [.orange.opacity(0.25), .purple.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing); Image(systemName: "book.closed").font(.system(size: 38)).foregroundStyle(.secondary) } }
            }.frame(height: 235).frame(maxWidth: .infinity).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topLeading) { if exists { Label("In library", systemImage: "checkmark").font(.caption2.weight(.semibold)).padding(7).background(.ultraThinMaterial, in: Capsule()).padding(8) } }
            Text(entry.title).font(.headline).lineLimit(2).frame(height: 38, alignment: .topLeading)
            Text(entry.author.isEmpty ? "MangaDex" : entry.author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Button {
                adding.insert(entry.id)
                Task { await network.add(entry, store: store); adding.remove(entry.id) }
            } label: {
                HStack {
                    if adding.contains(entry.id) { ProgressView().controlSize(.mini) }
                    else { Image(systemName: exists ? "checkmark" : "plus") }
                    Text(adding.contains(entry.id) ? "Adding…" : exists ? "Added to library" : "Add to library")
                }.frame(maxWidth: .infinity)
            }.buttonStyle(.bordered).tint(.orange).disabled(exists || adding.contains(entry.id))
        }
    }

    private func runSearch() {
        searchTask?.cancel()
        let text = query
        searchTask = Task {
            loading = true; error = nil
            do {
                let values = try await network.search(text)
                try Task.checkCancellation()
                results = values; loading = false
            } catch is CancellationError { }
            catch { if !Task.isCancelled { self.error = error.localizedDescription; loading = false } }
        }
    }
}
