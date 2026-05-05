import Foundation

/// Compression filter applied to the outer archive stream. tar
/// itself doesn't compress; tools like `gzip` / `xz` are layered on
/// top via libarchive's filter API. The bz2 / xz / zstd cases are
/// only effective on macOS / Linux / Windows — libarchive's CArchive
/// is built without those filters on iOS / tvOS / watchOS / visionOS
/// / Android, so a `.bzip2` / `.xz` / `.zstd` write will fail with
/// libarchive's own "filter unavailable" error there.
public enum Compression: Sendable, Equatable {
    case none
    case gzip
    case bzip2
    case xz
    case zstd
}

public struct CreateOptions: Sendable {
    /// Compression filter applied to the outer stream.
    public var compression: Compression
    /// Walk into directory inputs (default: true — POSIX tar default).
    public var recursive: Bool
    /// `-h` / `--dereference`: follow symlinks and store target
    /// contents instead of the link itself. Default false (POSIX
    /// default — symlinks are preserved as symlinks).
    public var followSymlinks: Bool

    public init(
        compression: Compression = .none,
        recursive: Bool = true,
        followSymlinks: Bool = false
    ) {
        self.compression = compression
        self.recursive = recursive
        self.followSymlinks = followSymlinks
    }
}
