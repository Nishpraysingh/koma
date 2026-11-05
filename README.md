# Koma for macOS

A native, local-first manga and comic reader inspired by Mihon. SwiftUI + AppKit + PDFKit; no web server, Android emulator, subscription, or third-party package dependencies.

This is an independently implemented first version, **not a complete macOS port of Mihon**. The reading and library features below work locally; source and tracker compatibility is narrower than Mihon's. No changes have been pushed to your GitHub fork.

## Open the app

The packaged application is in **`dist/Koma.app`**. Double-click it in Finder. You can copy it to Applications yourself; it also runs from this folder. `dist/Koma.zip` contains the same app. This build targets this Mac's Apple Silicon architecture and macOS 14 or newer. It is locally ad-hoc signed, not notarized for public distribution.

1. Choose **Import** (⌘O), or drag files/folders onto the window.
2. Import PDF, CBZ/ZIP comics, a folder of page images, or a title folder containing chapter folders/archives/PDFs. Pages use natural filename order, so `2.jpg` comes before `10.jpg`.
3. Click a title, then **Start reading**. Files are copied into Koma's managed library; originals are untouched.
4. Alternatively, choose **Try the included sample collection** to create three original, locally generated demonstration titles. These are samples, not downloaded manga.

## Features

| Area | Implemented |
| --- | --- |
| Library | Cover grid, title/author/tag search, favorites, reading status, sorting, unread/downloaded filters |
| Organization | Multiple collections per title, editable title/author/description, personal notes |
| Local imports | PDF, CBZ/ZIP, image folders, multiple chapters per title |
| Reader | Single page, double page, vertical scrolling, right-to-left/left-to-right, fit page/width, zoom, backgrounds, fullscreen |
| Progress | Last-page resume, chapter read state, recent history, optional completion marking |
| Bookmarks | Saved pages and chapters; open a bookmarked page from Bookmarks |
| Online catalog | MangaDex title search and popular titles, title metadata and covers |
| Updates | Refresh chapter feeds manually, on launch, or at a chosen interval while the app is running |
| Offline downloads | Per-chapter or unread-batch download, progress queue, cancellation, manual retry |
| Tracking | Link an AniList manga and explicitly send reading status/progress using an OAuth token stored in Keychain |
| Backups | Portable ZIP of metadata **and comic files**, including history, notes, bookmarks, collections, and preferences |
| Appearance | System/light/dark app themes; independent reader background |

### Reader shortcuts

| Key | Action |
| --- | --- |
| ← / → | Previous/next page according to reading direction |
| Space | Next page |
| Home / End | First/last page |
| B | Bookmark current page |
| + / − | Zoom |
| Escape | Close reader |

Use the reader sidebar for chapters and page bookmarks. Chapter completion is delayed until the final page renders; a one-page chapter requires explicit completion. Progress is saved locally even when automatic completion is disabled.

## MangaDex and AniList

**MangaDex:** open **Browse sources**, search, and add a title. Open it in Library to download chapters. Chapter language and smaller-image downloads are configurable in Settings. Downloaded chapters and cached covers work without an internet connection. Catalog browsing, chapter refresh, new downloads, and tracking require internet and service availability. Source errors are shown in the interface.

**AniList:** open a title's `…` menu → **Link AniList tracking**. Supply your own AniList OAuth access token, verify it, search for the matching title, link it, and use the explicit sync control. Koma does not include an AniList OAuth client registration or request account access automatically. Tokens never enter library JSON or backups. See the [official authentication guide](https://docs.anilist.co/guide/auth/) and [authenticated requests documentation](https://docs.anilist.co/guide/auth/authenticated-requests).

MangaDex integration follows its public [API](https://api.mangadex.org/docs/). Catalog browsing includes safe/suggestive titles. External-host chapters are excluded. One scanlation is selected per numbered volume/chapter where possible. Existing chapter records are retained if a provider removes them, so saved progress and downloads survive refresh.

## Data and backups

Default local storage:

```text
~/Library/Application Support/Koma/
  library.json       # metadata, preferences, reading progress
  content/           # copied comics, covers, downloaded pages
```

Settings → Library → **Show library folder in Finder** opens the actual location.

Settings → Backups → **Export full backup** exports a self-contained ZIP. **Restore backup** replaces the current library after validating its contents; export first if you want to keep the existing collection. ZIP paths, symlinks, duplicate paths, file references, and expanded-size limits are checked. Corrupted metadata is preserved rather than silently overwritten.

Backups/imports currently reject ZIP64, split archives, encrypted archives, and archives over 20 GB expanded. For larger collections, back up the complete Application Support/Koma folder while Koma is closed. Backup exports may take time for large libraries.

## Differences from full Mihon

- Android extension APKs cannot run in this native macOS app. Only MangaDex has a native online adapter in this version; arbitrary websites and external extension repositories are not supported.
- AniList is the only implemented tracker. Sync is manual, from Koma to AniList; there is no two-way or automatic tracker sync. MyAnimeList, Kitsu, MangaUpdates, Shikimori, Bangumi, MangaBaka, and Hikka adapters are not implemented.
- Mihon `.tachibk` backup migration, source migration, CBR/RAR/7z/EPUB import, advanced image filters, custom source plugins, and per-title reader overrides are not implemented.
- Download jobs are session-only; completed chapter files persist. Failed/cancelled chapter downloads restart cleanly when retried. The queue does not resume after quitting.
- Scheduled chapter refresh runs while Koma is open, not while it is quit. There is no launch agent or system-wide background service.
- Koma has no hosted account, telemetry, cloud sync, or automatic app updater. Portable backups can be copied to a destination you choose.

## Build and test

Install Apple's Command Line Tools or Xcode. From this directory:

```sh
swift build
./scripts/test-local.sh
./scripts/build-app.sh
```

The standalone test runner works with Command Line Tools alone. The additional XCTest suite in `Tests/MihonMacTests` can be run with `swift test` when full Xcode (including XCTest) is installed.

The packaging script creates `dist/Koma.app` and `dist/Koma.zip`. For a faster development build, use `./scripts/build-app.sh debug`. Open `Package.swift` in Xcode to develop visually, or edit the Swift files in any editor.

The `ViewState` alias resolves the stable `SwiftUI.State` property wrapper explicitly. This avoids the SDK 27 `State` macro requiring a plugin missing from some Command Line Tools installations, while keeping support for macOS 14.

## Code map

| File | Responsibility |
| --- | --- |
| `KomaApp.swift` | Entry point, dependency objects, menu commands, refresh scheduling |
| `Models.swift` | Book/chapter/bookmark/history/settings data structures |
| `WorkspaceView.swift` | Sidebar, library filters/grid, file import entry point |
| `LibraryComponents.swift` | Covers, cards, continue-reading banner, collection editor |
| `BookDetailView.swift` | Title details, chapter actions, metadata/notes editor |
| `LibraryStore.swift` | Persistent library, imports, progress, full backup/restore |
| `ArchiveUtility.swift` | ZIP inspection and system archive operations |
| `ContentLoader.swift` | Page inspection/rendering with a bounded image cache |
| `ReaderView.swift` | Reader layouts, navigation, bookmarks, completion detection |
| `NetworkService.swift` | MangaDex API, downloads, AniList GraphQL, Keychain |
| `BrowseView.swift`, `TrackingView.swift` | Online discovery and explicit tracker setup/sync |
| `ActivityViews.swift` | History, updates, bookmarks, downloads |
| `AppSettingsView.swift` | Reading settings, refresh preferences, backups, feature limits |
| `SampleLibrary.swift` | Original, locally generated demo pages |

## Verification

See `VERIFICATION.md` for the build/test results and checks performed on this Mac. Network fixture tests exercise response parsing and state preservation without credentials. AniList account writes cannot be live-tested without your own account authorization.
