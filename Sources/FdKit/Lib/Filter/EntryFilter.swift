import Foundation
import RipgrepKit
// `stat` / `lstat` / `S_IFMT` / `S_IFIFO` come from the platform libc.
// Foundation re-exports them on Darwin/Linux, but not under the Android
// SDK, so import the libc overlay explicitly (mirrors ForgeKit's TTY).
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#endif

/// Decides whether a walker entry passes the filter slice of fd's
/// flag surface (type, size, time, exclude globs, depth bounds).
struct EntryFilter {

    let options: FilterOptions
    private let excludeGlobs: [GitignoreGlob]
    private let referenceDate: Date

    init(options: FilterOptions, referenceDate: Date = Date()) {
        self.options = options
        self.referenceDate = referenceDate
        self.excludeGlobs = options.excludePatterns.compactMap { pat -> GitignoreGlob? in
            try? GitignoreGlob(pattern: pat)
        }
    }

    /// Snapshot of the filesystem metadata the filter actually
    /// inspects. Pulled together once per candidate so the various
    /// checks share resource-key fetches.
    struct Metadata {
        let url: URL
        let isDirectory: Bool
        let isSymlink: Bool
        let isRegularFile: Bool
        let fileSize: UInt64
        let modificationDate: Date?
        let posixPermissions: Int?
        let fileType: FileAttributeType?

        init(url: URL) {
            self.url = url
            let resourceKeys: Set<URLResourceKey> = [
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .isRegularFileKey,
                .fileSizeKey,
                .contentModificationDateKey,
            ]
            let values = try? url.resourceValues(forKeys: resourceKeys)
            self.isDirectory = values?.isDirectory ?? false
            self.isSymlink = values?.isSymbolicLink ?? false
            self.isRegularFile = values?.isRegularFile ?? false
            self.fileSize = UInt64(values?.fileSize ?? 0)
            self.modificationDate = values?.contentModificationDate
            // Posix permissions + file type need FileManager — pull
            // them lazily here to avoid penalizing callers who don't
            // ask for them. fd's `-t x` (executable), `-t s` (socket),
            // `-t p` (pipe), `-t b` (block), `-t c` (char) all need
            // this layer.
            let attrs = try? FileManager.default
                .attributesOfItem(atPath: url.path)
            if let attrs {
                self.posixPermissions = (attrs[.posixPermissions]
                    as? NSNumber)?.intValue
                self.fileType = attrs[.type] as? FileAttributeType
            } else {
                self.posixPermissions = nil
                self.fileType = nil
            }
        }
    }

    /// Decide whether `entry` should be emitted.
    ///
    /// `depth` is the entry's distance from the walker root (root
    /// itself = depth 0). `Walker` doesn't expose depth on its `Entry`
    /// type, so the caller (`Fd.run`) tracks it through the descent.
    func passes(entry: Walker.Entry,
                metadata: Metadata,
                depth: Int) -> Bool {
        // Depth gate -----------------------------------------------
        if let minDepth = options.minDepth, depth < minDepth {
            return false
        }

        // Type filter ----------------------------------------------
        if !options.fileTypes.isEmpty {
            var anyMatched = false
            for kind in options.fileTypes {
                if typeMatches(kind, metadata: metadata) {
                    anyMatched = true
                    break
                }
            }
            if !anyMatched { return false }
        }

        // Size filter ----------------------------------------------
        if !options.sizeConstraints.isEmpty && metadata.isRegularFile {
            for constraint in options.sizeConstraints {
                switch constraint.direction {
                case .atLeast:
                    if metadata.fileSize < constraint.bytes { return false }
                case .atMost:
                    if metadata.fileSize > constraint.bytes { return false }
                case .exactly:
                    if metadata.fileSize != constraint.bytes { return false }
                }
            }
        } else if !options.sizeConstraints.isEmpty && !metadata.isRegularFile {
            // Size filters drop non-regular files entirely — fd does
            // the same: a non-file has no measurable size.
            return false
        }

        // Time filters --------------------------------------------
        if options.changedWithin != nil || options.changedBefore != nil {
            guard let modDate = metadata.modificationDate else { return false }
            let age = referenceDate.timeIntervalSince(modDate)
            if let within = options.changedWithin, age > within { return false }
            if let before = options.changedBefore, age < before { return false }
        }

        // Exclude globs -------------------------------------------
        for glob in excludeGlobs {
            if glob.matches(entry.relativePath, isDirectory: metadata.isDirectory) {
                return false
            }
            // Also try basename — fd's `-E '*.pyc'` is basename-relative.
            if glob.matches(entry.url.lastPathComponent,
                            isDirectory: metadata.isDirectory) {
                return false
            }
        }

        return true
    }

    /// Map fd's `--type` enum onto the metadata snapshot.
    private func typeMatches(_ kind: FilterOptions.FileType,
                             metadata: Metadata) -> Bool {
        switch kind {
        case .file:
            return metadata.isRegularFile
        case .directory:
            return metadata.isDirectory
        case .symlink:
            return metadata.isSymlink
        case .executable:
            // POSIX executable = any-x bit on a regular file.
            guard metadata.isRegularFile,
                  let perms = metadata.posixPermissions else { return false }
            return (perms & 0o111) != 0
        case .empty:
            if metadata.isRegularFile { return metadata.fileSize == 0 }
            if metadata.isDirectory {
                let contents = try? FileManager.default.contentsOfDirectory(
                    atPath: metadata.url.path)
                return (contents?.isEmpty ?? false)
            }
            return false
        case .socket:
            return metadata.fileType == .typeSocket
        case .pipe:
            return metadata.fileType == .typeUnknown  // fd treats FIFO as pipe
                || self.isPipe(metadata: metadata)
        case .blockDevice:
            return metadata.fileType == .typeBlockSpecial
        case .charDevice:
            return metadata.fileType == .typeCharacterSpecial
        }
    }

    /// FileAttributeType doesn't model FIFO explicitly on every SDK
    /// version. On POSIX hosts fall back to a `stat(2)` probe so
    /// `--type pipe` actually finds named pipes. Windows has no
    /// concept of FIFOs in the POSIX sense and the toolchain doesn't
    /// expose `lstat` / `S_IFMT`, so we short-circuit to `false` —
    /// `--type pipe` on Windows produces no hits, which matches what
    /// real fd does there.
    private func isPipe(metadata: Metadata) -> Bool {
        #if os(Windows)
        return false
        #else
        var sb = stat()
        let result = metadata.url.withUnsafeFileSystemRepresentation { rep -> Int32 in
            guard let rep else { return -1 }
            return lstat(rep, &sb)
        }
        guard result == 0 else { return false }
        return (sb.st_mode & S_IFMT) == S_IFIFO
        #endif
    }
}
