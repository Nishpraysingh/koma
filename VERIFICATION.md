# Verification — 4 November 2026

## Packaged app

- Built the release executable with the installed Apple Swift 6.4 toolchain in Swift 5 language mode.
- Packaged `dist/Koma.app`, including its icon and Info.plist, and `dist/Koma.zip`.
- Verified the local code signature with `codesign --verify --deep --strict`.
- Verified the executable is an arm64 Mach-O binary for this Apple Silicon Mac.
- Launched the packaged release through macOS and inspected its native accessibility tree and rendered interface.

## Automated checks

`./scripts/test-local.sh` completed successfully. It compiles the application’s actual core implementations with a standalone test harness, without XCTest or external dependencies. Tests use isolated temporary directories and fixture HTTP responses; they do not access personal comics or tracker accounts.

Checks cover:

- Managed image-folder, CBZ, and single-image imports; original files remain intact.
- Natural page ordering, image decoding, out-of-range page errors, three-page PDF inspection/rendering, and missing-content errors.
- Progress persistence across store recreation, chapter completion status, categories, history, and bookmarks.
- Portable backup and restore of metadata **and page files**.
- Unsafe metadata paths and ZIP traversal path rejection.
- Failed restores into a read-only destination preserving the existing snapshot and original content.
- Corrupted library metadata remaining preserved with an error instead of being overwritten.
- Deleting a managed title clearing dependent history/bookmarks without deleting original imported files.
- MangaDex catalog relationship parsing and URL-encoded queries.
- Chapter refresh preserving existing local files and reading state.
- Rate-limit errors and failed refreshes preserving the library.
- Successful staged chapter download, saved local path, file persistence after store recreation, and failed-download cleanup.

The separate XCTest suite could not run with this Command Line Tools installation because the XCTest module is absent. The standalone checks above passed instead. Full Xcode is needed to use `swift test` here. A CoreGraphics diagnostic was emitted while processing the generated PDF fixture; page count and rasterization assertions passed.

## Native interface checks

- Created the three original sample titles from the app’s empty state.
- Confirmed covers, offline chapter counts, collection membership, and title details render.
- Opened and navigated the reader; tested single page, double page, and vertical modes.
- Saved a page bookmark and confirmed it appears in Bookmarks.
- Corrected and rechecked vertical-mode restoration: switching from single-page page 2 retains page 2.
- Verified keyboard zoom changes 100% to 125%.
- Closed the reader and confirmed page 2 remains saved in title details and the continue-reading banner.
- Opened MangaDex browsing against the live service: 40 popular titles and their cover images rendered successfully.
- Left the final release open on the local library with clearly labeled sample titles.

## Not live-verified

- AniList login/token storage/account writes require the user’s own OAuth token and authorization. No tracker account was modified.
- Live MangaDex chapter downloads were not used for verification; downloads were tested with deterministic HTTP/image fixtures. Actual availability depends on the source.
- Large collections approaching the 20 GB ZIP limit, Intel builds, and older macOS releases have not been tested on this Mac.

See README.md for the explicit feature compatibility gaps relative to Mihon.
