import Foundation
import ZIPFoundation

/// High-level facade over `ZIPFoundation` for the operations zip(1)
/// and unzip(1) need. Cross-platform (Apple + Linux + sandboxed iOS),
/// no `Process` calls.
public enum Archive {

    // MARK: List

    public static func list(at url: URL) throws -> [Entry] {
        let archive = try openArchive(at: url)
        return entries(in: archive)
    }

    public static func list(data: Data) throws -> [Entry] {
        let archive = try openArchive(data: data)
        return entries(in: archive)
    }

    private static func entries(in archive: ZIPFoundation.Archive) -> [Entry] {
        archive.map { native in
            Entry(
                path: native.path,
                kind: kind(of: native),
                uncompressedSize: Int64(native.uncompressedSize),
                compressedSize: Int64(native.compressedSize),
                compressionMethod: method(of: native),
                crc32: native.checksum,
                modificationDate: native.fileAttributes[.modificationDate] as? Date
            )
        }
    }

    private static func kind(of entry: ZIPFoundation.Entry) -> Entry.Kind {
        switch entry.type {
        case .file: return .file
        case .directory: return .directory
        case .symlink: return .symlink
        }
    }

    private static func method(of entry: ZIPFoundation.Entry) -> CompressionMethod {
        // ZIPFoundation exposes `compressedSize` / `uncompressedSize`
        // — equal sizes → store; different → deflate.
        entry.compressedSize == entry.uncompressedSize ? .store : .deflate
    }

    // MARK: Test integrity

    /// Walks every entry and recomputes its CRC; throws on mismatch.
    /// Returns the entries (with their CRCs) on success.
    @discardableResult
    public static func test(at url: URL) throws -> [Entry] {
        let archive = try openArchive(at: url)
        for entry in archive {
            // ZIPFoundation's extract closure-form recomputes CRC and
            // throws if it doesn't match the central directory.
            _ = try archive.extract(entry, skipCRC32: false) { _ in }
        }
        return entries(in: archive)
    }

    // MARK: Read a single entry

    /// Returns the decompressed bytes of `entryPath`. Used by `unzip -p`.
    public static func read(entry entryPath: String, from url: URL) throws -> Data {
        let archive = try openArchive(at: url)
        guard let entry = archive[entryPath] else {
            throw ZipKitError.entryNotFound(entryPath)
        }
        var out = Data()
        _ = try archive.extract(entry) { chunk in
            out.append(chunk)
        }
        return out
    }

    public static func read(entry entryPath: String, data: Data) throws -> Data {
        let archive = try openArchive(data: data)
        guard let entry = archive[entryPath] else {
            throw ZipKitError.entryNotFound(entryPath)
        }
        var out = Data()
        _ = try archive.extract(entry) { chunk in
            out.append(chunk)
        }
        return out
    }

    // MARK: Stream entries to a FileHandle

    /// Writes each matching entry's bytes to `handle`, prefixed with a
    /// `=== <path> ===` header. Used by `unzip -p` (no header) and by
    /// SwiftGH's `gh run view --log` (header per file). Set
    /// `printHeaders: false` to omit the prefix.
    public static func streamEntries(
        from data: Data,
        to handle: FileHandle,
        matching options: ExtractOptions = .init(destination: URL(fileURLWithPath: "")),
        printHeaders: Bool = true
    ) throws {
        let archive = try openArchive(data: data)
        let selected = archive
            .filter { $0.type == .file }
            .filter { entry in
                shouldInclude(entryPath: entry.path,
                              includes: options.includes,
                              excludes: options.excludes,
                              caseInsensitive: options.caseInsensitive)
            }
            .sorted { $0.path < $1.path }
        for entry in selected {
            if printHeaders {
                handle.write(Data("\n=== \(entry.path) ===\n".utf8))
            }
            _ = try archive.extract(entry) { chunk in
                handle.write(chunk)
            }
        }
    }

    // MARK: Extract

    @discardableResult
    public static func extract(
        from url: URL, options: ExtractOptions
    ) throws -> [Entry] {
        let archive = try openArchive(at: url)
        return try extract(archive: archive, options: options)
    }

    @discardableResult
    public static func extract(
        from data: Data, options: ExtractOptions
    ) throws -> [Entry] {
        let archive = try openArchive(data: data)
        return try extract(archive: archive, options: options)
    }

    private static func extract(
        archive: ZIPFoundation.Archive, options: ExtractOptions
    ) throws -> [Entry] {
        try FileManager.default.createDirectory(
            at: options.destination, withIntermediateDirectories: true)

        var written: [Entry] = []
        let entries = archive.sorted { $0.path < $1.path }

        for native in entries {
            // `-j` (junk paths) means flat extraction — skip directory
            // entries entirely; for files take only the basename.
            if options.junkPaths && native.type == .directory {
                continue
            }
            let path = options.junkPaths
                ? (native.path as NSString).lastPathComponent
                : native.path
            guard !path.isEmpty else { continue }
            guard shouldInclude(entryPath: native.path,
                                includes: options.includes,
                                excludes: options.excludes,
                                caseInsensitive: options.caseInsensitive)
            else { continue }

            let target = options.destination.appendingPathComponent(path)
            let exists = FileManager.default.fileExists(atPath: target.path)
            if exists {
                switch options.overwrite {
                case .yes: try? FileManager.default.removeItem(at: target)
                case .no: continue
                case .error: throw ZipKitError.destinationExists(target)
                }
            }

            do {
                switch native.type {
                case .directory:
                    try FileManager.default.createDirectory(
                        at: target, withIntermediateDirectories: true)
                case .file:
                    try FileManager.default.createDirectory(
                        at: target.deletingLastPathComponent(),
                        withIntermediateDirectories: true)
                    _ = try archive.extract(native, to: target)
                case .symlink:
                    try FileManager.default.createDirectory(
                        at: target.deletingLastPathComponent(),
                        withIntermediateDirectories: true)
                    _ = try archive.extract(native, to: target)
                }
            } catch let error as ZipKitError { throw error }
            catch {
                throw ZipKitError.writeFailed(target,
                    underlying: error.localizedDescription)
            }
            written.append(Entry(
                path: native.path,
                kind: kind(of: native),
                uncompressedSize: Int64(native.uncompressedSize),
                compressedSize: Int64(native.compressedSize),
                compressionMethod: method(of: native),
                crc32: native.checksum,
                modificationDate: native.fileAttributes[.modificationDate] as? Date))
        }
        return written
    }

    // MARK: Create

    /// Build a new archive at `zipURL` containing every matching file
    /// in `paths`. Directories are walked when `recursive` is set.
    @discardableResult
    public static func create(
        at zipURL: URL,
        paths: [URL],
        options: CreateOptions = .init()
    ) throws -> [Entry] {
        // Remove an existing archive — Info-ZIP appends to existing
        // archives by default but our minimal port replaces them.
        if FileManager.default.fileExists(atPath: zipURL.path) {
            try FileManager.default.removeItem(at: zipURL)
        }
        let archive: ZIPFoundation.Archive
        do {
            archive = try ZIPFoundation.Archive(url: zipURL, accessMode: .create)
        } catch {
            throw ZipKitError.archiveOpenFailed(zipURL.path)
        }

        var written: [Entry] = []
        let toAdd = try resolveInputs(paths: paths, options: options)
        for resolved in toAdd {
            let baseAttrs = (try? FileManager.default.attributesOfItem(
                atPath: resolved.source.path)) ?? [:]
            let isDir = (baseAttrs[.type] as? FileAttributeType) == .typeDirectory
            let isSymlink = (baseAttrs[.type] as? FileAttributeType) == .typeSymbolicLink

            if isDir {
                if options.includeDirectories {
                    try archive.addEntry(
                        with: resolved.entryPath + "/",
                        type: .directory,
                        uncompressedSize: Int64(0),
                        provider: { _, _ in Data() })
                    written.append(syntheticDirEntry(path: resolved.entryPath + "/"))
                }
            } else if isSymlink && !options.followSymlinks {
                let dest = (try? FileManager.default.destinationOfSymbolicLink(
                    atPath: resolved.source.path)) ?? ""
                let bytes = Data(dest.utf8)
                try archive.addEntry(
                    with: resolved.entryPath,
                    type: .symlink,
                    uncompressedSize: Int64(bytes.count),
                    compressionMethod: nativeCompressionMethod(options.compressionMethod),
                    provider: { _, _ in bytes })
                written.append(Entry(
                    path: resolved.entryPath, kind: .symlink,
                    uncompressedSize: Int64(bytes.count),
                    compressedSize: Int64(bytes.count),
                    compressionMethod: .store,
                    crc32: 0, modificationDate: nil))
            } else {
                try archive.addEntry(
                    with: resolved.entryPath,
                    fileURL: resolved.source,
                    compressionMethod: nativeCompressionMethod(options.compressionMethod))
                let size = Int64(
                    (baseAttrs[.size] as? NSNumber)?.int64Value ?? 0)
                written.append(Entry(
                    path: resolved.entryPath, kind: .file,
                    uncompressedSize: size,
                    compressedSize: size,
                    compressionMethod: options.compressionMethod,
                    crc32: 0, modificationDate: baseAttrs[.modificationDate] as? Date))
            }
        }
        return written
    }

    private static func nativeCompressionMethod(
        _ method: CompressionMethod
    ) -> ZIPFoundation.CompressionMethod {
        switch method {
        case .store: return .none
        case .deflate: return .deflate
        }
    }

    private static func syntheticDirEntry(path: String) -> Entry {
        Entry(path: path, kind: .directory,
              uncompressedSize: 0, compressedSize: 0,
              compressionMethod: .store, crc32: 0, modificationDate: nil)
    }

    // MARK: Input resolution (for create)

    private struct ResolvedInput {
        let source: URL
        let entryPath: String
    }

    private static func resolveInputs(
        paths: [URL], options: CreateOptions
    ) throws -> [ResolvedInput] {
        var resolved: [ResolvedInput] = []
        for input in paths {
            try walk(source: input, prefix: nil,
                     into: &resolved, options: options)
        }
        return resolved
    }

    private static func walk(
        source: URL, prefix: String?, into resolved: inout [ResolvedInput],
        options: CreateOptions
    ) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: source.path)
        let type = attrs[.type] as? FileAttributeType
        let topName = source.lastPathComponent

        let entryName: String
        if options.junkPaths {
            entryName = topName
        } else if let prefix {
            entryName = prefix.isEmpty ? topName : "\(prefix)/\(topName)"
        } else {
            entryName = topName
        }

        // Filter
        let nameForFilter = (entryName as NSString).lastPathComponent
        if !options.includes.isEmpty,
           !GlobMatcher.matchesAny(patterns: options.includes,
                                   name: nameForFilter) {
            return
        }
        if GlobMatcher.matchesAny(patterns: options.excludes,
                                  name: nameForFilter) {
            return
        }

        if type == .typeDirectory {
            if options.recursive {
                if options.includeDirectories {
                    resolved.append(.init(source: source, entryPath: entryName))
                }
                let children = try FileManager.default.contentsOfDirectory(
                    at: source, includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles])
                for child in children.sorted(by: { $0.path < $1.path }) {
                    try walk(source: child, prefix: entryName,
                             into: &resolved, options: options)
                }
            }
        } else {
            resolved.append(.init(source: source, entryPath: entryName))
        }
    }

    // MARK: Helpers

    private static func openArchive(at url: URL) throws -> ZIPFoundation.Archive {
        do {
            return try ZIPFoundation.Archive(url: url, accessMode: .read)
        } catch {
            throw ZipKitError.archiveOpenFailed(url.path)
        }
    }

    private static func openArchive(data: Data) throws -> ZIPFoundation.Archive {
        do {
            return try ZIPFoundation.Archive(data: data, accessMode: .read)
        } catch {
            throw ZipKitError.archiveOpenFailed(error.localizedDescription)
        }
    }

    private static func shouldInclude(
        entryPath: String,
        includes: [String], excludes: [String],
        caseInsensitive: Bool
    ) -> Bool {
        if !includes.isEmpty,
           !GlobMatcher.matchesAny(patterns: includes,
                                   name: entryPath,
                                   caseInsensitive: caseInsensitive)
        {
            return false
        }
        if GlobMatcher.matchesAny(patterns: excludes,
                                  name: entryPath,
                                  caseInsensitive: caseInsensitive)
        {
            return false
        }
        return true
    }
}
