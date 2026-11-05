import Foundation

/// Restricts ZIP extraction to ordinary relative files/directories before invoking the system tool.
/// ZIP64 and encrypted archives are deliberately rejected instead of guessed at.
enum ArchiveUtility {
    static let maximumExpandedSize: UInt64 = 20 * 1024 * 1024 * 1024
    static let maximumEntries = 100_000

    static func extractZip(_ archive: URL, to destination: URL) throws {
        let fm = FileManager.default
        let data = try Data(contentsOf: archive, options: .mappedIfSafe)
        try validateZip(data)
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        do {
            try run("/usr/bin/ditto", ["-x", "-k", archive.path, destination.path])
            if let enumerator = fm.enumerator(at: destination, includingPropertiesForKeys: [.isSymbolicLinkKey], options: []) {
                while let item = enumerator.nextObject() as? URL {
                    if try item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                        throw LibraryError.invalid("The archive contains a symbolic link.")
                    }
                    guard item.resolvingSymlinksInPath().path.hasPrefix(destination.resolvingSymlinksInPath().path + "/") else {
                        throw LibraryError.invalid("An archive entry escaped the destination folder.")
                    }
                }
            }
        } catch { try? fm.removeItem(at: destination); throw error }
    }

    static func validateZip(_ data: Data) throws {
        guard data.count >= 22 else { throw LibraryError.invalid("This is not a valid ZIP/CBZ archive.") }
        func u16(_ offset: Int) throws -> UInt16 {
            guard offset >= 0 && offset + 2 <= data.count else { throw LibraryError.invalid("The ZIP directory is truncated.") }
            return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
        }
        func u32(_ offset: Int) throws -> UInt32 {
            guard offset >= 0 && offset + 4 <= data.count else { throw LibraryError.invalid("The ZIP directory is truncated.") }
            return UInt32(data[offset]) | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
        }
        var end: Int?
        for offset in stride(from: data.count - 22, through: max(0, data.count - 65_557), by: -1) {
            if try u32(offset) == 0x06054b50, offset + 22 + Int(try u16(offset + 20)) == data.count { end = offset; break }
        }
        guard let end else { throw LibraryError.invalid("The ZIP end directory could not be found.") }
        let disk = try u16(end + 4), startDisk = try u16(end + 6), count = Int(try u16(end + 10))
        let directorySize = try u32(end + 12), directoryOffset = try u32(end + 16)
        guard disk == 0, startDisk == 0, try u16(end + 8) == UInt16(count), count < 65_535,
              directorySize != UInt32.max, directoryOffset != UInt32.max, count <= maximumEntries else {
            throw LibraryError.invalid("Split and ZIP64 archives are not supported. Split large libraries into smaller backups.")
        }
        var cursor = Int(directoryOffset)
        let directoryEnd = cursor + Int(directorySize)
        guard directoryEnd <= end else { throw LibraryError.invalid("Invalid ZIP directory bounds.") }
        var expanded: UInt64 = 0
        var paths = Set<String>()
        for _ in 0..<count {
            guard try u32(cursor) == 0x02014b50 else { throw LibraryError.invalid("The ZIP directory is invalid.") }
            let flags = try u16(cursor + 8)
            guard flags & 1 == 0 else { throw LibraryError.invalid("Password protected archives are not supported.") }
            let uncompressed = try u32(cursor + 24)
            let filenameLength = Int(try u16(cursor + 28)), extraLength = Int(try u16(cursor + 30)), commentLength = Int(try u16(cursor + 32))
            let entryEnd = cursor + 46 + filenameLength + extraLength + commentLength
            guard filenameLength > 0, entryEnd <= directoryEnd else { throw LibraryError.invalid("The ZIP filename is invalid.") }
            let nameData = data.subdata(in: (cursor + 46)..<(cursor + 46 + filenameLength))
            guard let name = String(data: nameData, encoding: .utf8) ?? String(data: nameData, encoding: .isoLatin1),
                  safePath(name) else { throw LibraryError.invalid("The archive contains an unsafe path.") }
            // Normalization catches duplicate file paths differing only by ./, case or Unicode form.
            let normalized = name.split(separator: "/").filter { $0 != "." }.joined(separator: "/").precomposedStringWithCanonicalMapping.lowercased()
            guard !paths.contains(normalized) else { throw LibraryError.invalid("The archive contains duplicate file paths.") }
            paths.insert(normalized)
            let attributes = try u32(cursor + 38)
            let mode = (attributes >> 16) & 0xf000
            guard mode != 0xa000, mode == 0 || mode == 0x8000 || mode == 0x4000 else { throw LibraryError.invalid("Symbolic links and special files cannot be extracted.") }
            guard uncompressed != UInt32.max else { throw LibraryError.invalid("ZIP64 files are not supported.") }
            expanded += UInt64(uncompressed)
            guard expanded <= maximumExpandedSize else { throw LibraryError.invalid("The archive expands beyond the 20 GB import limit.") }
            // Local headers must agree with the inspected central directory filename.
            let localOffset = Int(try u32(cursor + 42))
            guard try u32(localOffset) == 0x04034b50 else { throw LibraryError.invalid("An archive entry has an invalid local header.") }
            let localLength = Int(try u16(localOffset + 26))
            let localEnd = localOffset + 30 + localLength
            guard localEnd <= data.count, localLength == filenameLength, data.subdata(in: (localOffset + 30)..<localEnd) == nameData else { throw LibraryError.invalid("ZIP filenames do not match their local headers.") }
            cursor = entryEnd
        }
        guard cursor == directoryEnd else { throw LibraryError.invalid("Unexpected data in the ZIP directory.") }
    }

    static func safePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") && !path.contains(":") && !path.contains("\0") && !path.split(separator: "/").contains("..")
    }

    static func createZip(from directory: URL, to destination: URL) throws {
        let fm = FileManager.default
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".mihon-backup-\(UUID().uuidString).zip")
        defer { try? fm.removeItem(at: temporary) }
        try run("/usr/bin/ditto", ["-c", "-k", "--norsrc", directory.path, temporary.path])
        try validateZip(Data(contentsOf: temporary, options: .mappedIfSafe))
        if fm.fileExists(atPath: destination.path) { _ = try fm.replaceItemAt(destination, withItemAt: temporary) }
        else { try fm.moveItem(at: temporary, to: destination) }
    }

    private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: errorData.prefix(3000), encoding: .utf8) ?? "Unknown archive error"
            throw LibraryError.invalid("Archive operation failed: \(detail)")
        }
    }
}
