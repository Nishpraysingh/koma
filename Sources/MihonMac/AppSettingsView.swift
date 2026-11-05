import SwiftUI
import AppKit

struct AppSettingsView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var network: NetworkService
    @Environment(\.dismiss) private var dismiss
    @ViewState private var selectedTab = "Reading"
    @ViewState private var restoreConfirm = false
    @ViewState private var result: String?
    @ViewState private var backingUp = false
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Make yourself at home").font(.system(size: 23, weight: .medium, design: .serif)); Spacer(); Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain) }.padding(24)
            Picker("Settings", selection: $selectedTab) { ForEach(["Reading", "Library", "Backups", "About"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented).padding(.horizontal, 24)
            Form {
                switch selectedTab {
                case "Reading": readingSettings
                case "Library": librarySettings
                case "Backups": backupSettings
                default: aboutSettings
                }
            }.formStyle(.grouped)
            if let result { Text(result).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).padding(16) }
        }.frame(width: 640, height: 570)
            .alert("Replace this library from a backup?", isPresented: $restoreConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Choose backup…", role: .destructive, action: restore)
            } message: { Text("Restoring replaces your current library and managed comic files. Export a backup first if you want to keep them.") }
    }
    @ViewBuilder private var readingSettings: some View {
        Section("Appearance") {
            Picker("App theme", selection: $store.preferences.theme) { ForEach(["System", "Light", "Dark"], id: \.self) { Text($0).tag($0) } }
            Picker("Reader background", selection: $store.preferences.background) { ForEach(["Black", "Gray", "Sepia", "White"], id: \.self) { Text($0).tag($0) } }
        }
        Section("Reader defaults") {
            Picker("Layout", selection: $store.preferences.mode) { ForEach(ReaderMode.allCases) { Text($0.rawValue).tag($0) } }
            Picker("Scale", selection: $store.preferences.fit) { ForEach(ReaderFit.allCases) { Text($0.rawValue).tag($0) } }
            Toggle("Read from right to left", isOn: $store.preferences.rightToLeft)
            Toggle("Show page numbers", isOn: $store.preferences.showPageNumbers)
            Toggle("Mark chapters read when finished", isOn: $store.preferences.autoMarkRead)
        }
    }
    @ViewBuilder private var librarySettings: some View {
        Section("Chapter updates") {
            Toggle("Check online titles when Koma opens", isOn: $store.preferences.updateOnLaunch)
            Picker("Check while the app is running", selection: $store.preferences.updateIntervalHours) {
                Text("Manually").tag(0); Text("Every hour").tag(1); Text("Every 6 hours").tag(6); Text("Every 12 hours").tag(12); Text("Daily").tag(24)
            }
            Text("Scheduled updates run while Koma is open. Online services require an internet connection.").font(.caption).foregroundStyle(.secondary)
        }
        Section("MangaDex") {
            Picker("Chapter language", selection: $store.preferences.language) {
                Text("English").tag("en"); Text("Hindi").tag("hi"); Text("Japanese").tag("ja"); Text("Spanish").tag("es"); Text("French").tag("fr"); Text("Portuguese (Brazil)").tag("pt-br")
            }
            Toggle("Download smaller images (data saver)", isOn: $store.preferences.dataSaver)
        }
        Section("Storage") {
            Text(store.rootURL.path).font(.caption).textSelection(.enabled)
            Button("Show library folder in Finder") { NSWorkspace.shared.open(store.rootURL) }
        }
    }
    @ViewBuilder private var backupSettings: some View {
        Section("Portable library backups") {
            Text("Export a ZIP containing your library, comics, downloaded pages, progress, collections, bookmarks, notes, history, and preferences. AniList credentials stay in your Mac’s Keychain.").font(.callout).foregroundStyle(.secondary)
            Button("Export full backup…", action: export).disabled(backingUp || store.isImporting || network.isWorking)
            Button("Restore backup…") { restoreConfirm = true }.disabled(backingUp || store.isImporting || network.isWorking)
            if backingUp { ProgressView("Working…") }
        }
        Section("Compatibility") {
            Text("Koma backups use their own portable format. Mihon .tachibk backups and Android extension APKs cannot be imported.").font(.callout).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var aboutSettings: some View {
        Section {
            HStack(spacing: 16) {
                Image(systemName: "book.closed.fill").font(.system(size: 32)).foregroundStyle(Color.komaAccent)
                VStack(alignment: .leading, spacing: 5) { Text("Koma 1.0").font(.title2.bold()); Text("A local-first manga reader for your Mac.").foregroundStyle(.secondary) }
            }.padding(.vertical, 8)
            Text("Inspired by Mihon. Independently implemented in SwiftUI and AppKit, with no Android runtime or server required.").font(.callout)
        }
        Section("Supported in this version") {
            Text("PDF, CBZ/ZIP, image folders · Library collections · Reading progress · Single/double page and scrolling readers · Page and chapter bookmarks · Local history · MangaDex search, updates and downloads · Manual AniList tracking · Portable backups").font(.callout).foregroundStyle(.secondary)
        }
        Section("Not yet supported") {
            Text("Android extensions, other source adapters, CBR/RAR/7z archives, Mihon backup migration, trackers other than AniList, and updates while the app is closed.").font(.callout).foregroundStyle(.secondary)
        }
    }
    private func export() {
        let panel = NSSavePanel(); panel.title = "Export Koma library"; panel.nameFieldStringValue = "Koma-backup-\(Date().formatted(.iso8601.year().month().day())).zip"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        backingUp = true
        // Store serializes a consistent snapshot before archiving its managed content.
        Task { @MainActor in
            do { try store.exportBackup(to: url); result = "Backup saved to \(url.lastPathComponent)." }
            catch { result = error.localizedDescription }
            backingUp = false
        }
    }
    private func restore() {
        let panel = NSOpenPanel(); panel.title = "Restore Koma backup"; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        backingUp = true
        Task { @MainActor in
            do { try store.restoreBackup(from: url); result = "Your library has been restored." }
            catch { result = error.localizedDescription }
            backingUp = false
        }
    }
}
