import Foundation
// Selective imports — the libarchive wrapper module is named `Archive`
// and exposes its own `enum Archive` which would collide with our
// public type below.
import struct Archive.ArchiveEntry
import class Archive.ArchiveReader
import class Archive.ArchiveWriter
import enum Archive.ArchiveFormat
import enum Archive.ArchiveFilter
import enum Archive.FileType

/// High-level facade over libarchive (via marcprux/swift-archive) for
/// tar create / extract / list. Reads any libarchive-supported format
/// (compression auto-detected on read), but only writes pax-restricted
/// tar with optional gzip filter. Cross-platform (macOS, iOS, Linux,
/// Windows, Android).
public enum Archive {

    // MARK: List

    public static func list(at url: URL) throws -> [Entry] {
        let reader = try newReader(at: url)
        return try collect(reader: reader)
    }

    public static func list(data: Data) throws -> [Entry] {
        let reader = try newReader(data: data)
        return try collect(reader: reader)
    }

    private static func collect(reader: ArchiveReader) throws -> [Entry] {
        var out: [Entry] = []
        try reader.forEachEntry { native, _ in
            out.append(map(native))
        }
        return out
    }

    // MARK: Extract

    @discardableResult
    public static func extract(
        from url: URL, options: ExtractOptions
    ) throws -> [Entry] {
        let reader = try newReader(at: url)
        return try extract(reader: reader, options: options)
    }

    @discardableResult
    public static func extract(
        from data: Data, options: ExtractOptions
    ) throws -> [Entry] {
        let reader = try newReader(data: data)
        return try extract(reader: reader, options: options)
    }

    private static func extract(
        reader: ArchiveReader, options: ExtractOptions
    ) throws -> [Entry] {
        let fm = FileManager.default
        try fm.createDirectory(
            at: options.destination, withIntermediateDirectories: true)

        var written: [Entry] = []
        try reader.forEachEntry { native, reader in
            let stripped = stripComponents(
                path: native.pathname, count: options.stripComponents)
            // sanitize returns:
            //   nil  → hostile path (refuse archive)
            //   ""   → legit no-op (e.g. `./` or fully stripped) — skip
            //   else → safe normalized relative path
            guard let safe = sanitizeRelativePath(stripped) else {
                throw TarKitError.unsafeEntryPath(native.pathname)
            }
            if safe.isEmpty { return }

            let target = options.destination.appendingPathComponent(safe)
            let exists = fm.fileExists(atPath: target.path)
            if exists && !options.overwrite { return }

            do {
                switch native.fileType {
                case .directory:
                    try fm.createDirectory(
                        at: target, withIntermediateDirectories: true)
                case .symbolicLink:
                    try fm.createDirectory(
                        at: target.deletingLastPathComponent(),
                        withIntermediateDirectories: true)
                    if exists { try? fm.removeItem(at: target) }
                    if let link = native.symlinkTarget {
                        // Preserve the raw symlink target string —
                        // `URL(fileURLWithPath:)` would resolve it
                        // against cwd and turn relative links absolute.
                        try fm.createSymbolicLink(
                            atPath: target.path,
                            withDestinationPath: link)
                    }
                default:
                    try fm.createDirectory(
                        at: target.deletingLastPathComponent(),
                        withIntermediateDirectories: true)
                    if exists { try? fm.removeItem(at: target) }
                    let bytes = try reader.readData()
                    try bytes.write(to: target)
                }
            } catch let e as TarKitError {
                throw e
            } catch {
                throw TarKitError.writeFailed(
                    target, underlying: error.localizedDescription)
            }
            written.append(map(native))
        }
        return written
    }

    private static func stripComponents(path: String, count: Int) -> String {
        guard count > 0 else { return path }
        var components = path.split(
            separator: "/", omittingEmptySubsequences: true)
        if components.count <= count { return "" }
        components.removeFirst(count)
        return components.joined(separator: "/")
    }

    /// Returns a normalized relative path under the destination root.
    /// `nil` means the entry is hostile (absolute, drive-letter, or
    /// `..`-traversing) and the caller should refuse the archive.
    /// An empty string means the entry resolved to a no-op (e.g. `.`
    /// or `./`) and the caller should skip it silently — matching
    /// GNU tar's behavior on its own `./` leading entry.
    private static func sanitizeRelativePath(_ raw: String) -> String? {
        if raw.isEmpty { return "" }
        if raw.hasPrefix("/") { return nil }
        if raw.hasPrefix("\\") { return nil }
        if raw.count >= 2 {
            let chars = Array(raw)
            if chars[1] == ":" && chars[0].isLetter { return nil }
        }
        let normalized = raw.replacingOccurrences(of: "\\", with: "/")
        var out: [String] = []
        for piece in normalized.split(
            separator: "/", omittingEmptySubsequences: true)
        {
            let s = String(piece)
            if s == "." { continue }
            if s == ".." { return nil }
            out.append(s)
        }
        return out.joined(separator: "/")
    }

    // MARK: Create

    @discardableResult
    public static func create(
        at url: URL,
        paths: [URL],
        options: CreateOptions = .init()
    ) throws -> [Entry] {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        try fm.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)

        let writer: ArchiveWriter
        do {
            writer = try ArchiveWriter(
                path: url.path,
                format: .tar,
                filters: options.compression.libarchiveFilters)
        } catch {
            throw TarKitError.archiveOpenFailed(url.path)
        }

        var written: [Entry] = []
        for input in paths {
            try walk(source: input, prefix: nil,
                     writer: writer, options: options,
                     into: &written)
        }
        try writer.close()
        return written
    }

    private static func walk(
        source: URL, prefix: String?,
        writer: ArchiveWriter, options: CreateOptions,
        into written: inout [Entry]
    ) throws {
        let fm = FileManager.default
        let attrs = try fm.attributesOfItem(atPath: source.path)
        let type = attrs[.type] as? FileAttributeType
        let topName = source.lastPathComponent
        let entryPath: String
        if let prefix, !prefix.isEmpty {
            entryPath = "\(prefix)/\(topName)"
        } else {
            entryPath = topName
        }
        let modDate = (attrs[.modificationDate] as? Date) ?? Date()
        let perms = (attrs[.posixPermissions] as? NSNumber)?.uint16Value

        if type == .typeDirectory {
            // Always emit a directory entry — matches GNU tar's default.
            let dirPath = entryPath + "/"
            let dirEntry = ArchiveEntry(
                pathname: dirPath,
                size: 0,
                fileType: .directory,
                permissions: perms ?? 0o755,
                modificationDate: modDate)
            try writer.writeEntry(dirEntry)
            written.append(Entry(
                path: dirPath, kind: .directory, size: 0,
                modificationDate: modDate, mode: perms ?? 0o755))
            if options.recursive {
                let children = try fm.contentsOfDirectory(
                    at: source, includingPropertiesForKeys: nil,
                    options: [])
                for child in children.sorted(by: { $0.path < $1.path }) {
                    try walk(source: child, prefix: entryPath,
                             writer: writer, options: options,
                             into: &written)
                }
            }
        } else if type == .typeSymbolicLink && !options.followSymlinks {
            let linkTarget = (try? fm.destinationOfSymbolicLink(
                atPath: source.path)) ?? ""
            let entry = ArchiveEntry(
                pathname: entryPath,
                size: 0,
                fileType: .symbolicLink,
                permissions: perms ?? 0o755,
                modificationDate: modDate,
                symlinkTarget: linkTarget)
            try writer.writeEntry(entry)
            written.append(Entry(
                path: entryPath, kind: .symlink, size: 0,
                modificationDate: modDate, mode: perms ?? 0o755))
        } else {
            let bytes = try Data(contentsOf: source)
            let entry = ArchiveEntry(
                pathname: entryPath,
                size: Int64(bytes.count),
                fileType: .regular,
                permissions: perms ?? 0o644,
                modificationDate: modDate)
            try writer.writeEntry(entry, data: bytes)
            written.append(Entry(
                path: entryPath, kind: .file, size: Int64(bytes.count),
                modificationDate: modDate, mode: perms ?? 0o644))
        }
    }

    // MARK: Mappings

    private static func map(_ native: ArchiveEntry) -> Entry {
        let kind: Entry.Kind
        switch native.fileType {
        case .directory: kind = .directory
        case .symbolicLink: kind = .symlink
        default: kind = .file
        }
        let path: String
        if kind == .directory && !native.pathname.hasSuffix("/") {
            path = native.pathname + "/"
        } else {
            path = native.pathname
        }
        return Entry(
            path: path, kind: kind,
            size: native.size,
            modificationDate: native.modificationDate,
            mode: native.permissions)
    }

    private static func newReader(at url: URL) throws -> ArchiveReader {
        do {
            return try ArchiveReader(path: url.path)
        } catch {
            throw TarKitError.archiveOpenFailed(url.path)
        }
    }

    private static func newReader(data: Data) throws -> ArchiveReader {
        do {
            return try ArchiveReader(data: data)
        } catch {
            throw TarKitError.archiveOpenFailed(error.localizedDescription)
        }
    }
}

extension Compression {
    var libarchiveFilters: [ArchiveFilter] {
        switch self {
        case .none:  return [.none]
        case .gzip:  return [.gzip]
        case .bzip2: return [.bzip2]
        case .xz:    return [.xz]
        case .zstd:  return [.zstd]
        }
    }
}
