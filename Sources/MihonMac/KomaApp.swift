import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct KomaApp: App {
    @StateObject private var store = LibraryStore()
    @StateObject private var network = NetworkService()

    var body: some Scene {
        WindowGroup("Koma") {
            WorkspaceView()
                .environmentObject(store)
                .environmentObject(network)
                .tint(.komaAccent)
                .preferredColorScheme(store.preferences.theme == "Dark" ? .dark : store.preferences.theme == "Light" ? .light : nil)
                .frame(minWidth: 980, minHeight: 680)
                .task {
                    if store.preferences.updateOnLaunch { await network.refreshLibrary(store: store) }
                    var lastRefresh = Date()
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 60_000_000_000)
                        guard !Task.isCancelled else { return }
                        let hours = store.preferences.updateIntervalHours
                        if hours > 0 && Date().timeIntervalSince(lastRefresh) >= Double(hours * 3600) {
                            await network.refreshLibrary(store: store)
                            lastRefresh = Date()
                        }
                    }
                }
        }
        .defaultSize(width: 1320, height: 880)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import manga…") { NotificationCenter.default.post(name: .komaImport, object: nil) }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .newItem) {
                Button("Refresh library") { Task { await network.refreshLibrary(store: store) } }
                    .keyboardShortcut("r")
            }
        }
        Settings {
            AppSettingsView().environmentObject(store).environmentObject(network).tint(.komaAccent)
        }
    }
}

extension Notification.Name { static let komaImport = Notification.Name("KomaImport") }
extension Color {
    static let komaAccent = Color(red: 0.84, green: 0.32, blue: 0.16)
    static let komaCanvas = Color(nsColor: .windowBackgroundColor)
}

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case library = "Library", updates = "Updates", history = "History", bookmarks = "Bookmarks", downloads = "Downloads", browse = "Browse sources"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .library: return "square.grid.2x2"
        case .updates: return "clock.arrow.circlepath"
        case .history: return "clock"
        case .bookmarks: return "bookmark"
        case .downloads: return "arrow.down.circle"
        case .browse: return "safari"
        }
    }
}

// Keep the stable property wrapper distinct from the SDK 27 State macro.
typealias ViewState<Value> = SwiftUI.State<Value>
