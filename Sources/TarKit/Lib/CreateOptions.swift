import Foundation

/// Compression filter applied to the outer archive stream. tar
/// itself doesn't compress; tools like `gzip` / `xz` are layered on
/// top via libarchive's filter API. Only filters our build actually
/// links against are exposed here. Bzip2 / xz / zstd will land once
/// swift-archive supports per-platform trait conditionals (Android
/// NDK doesn't ship the underlying headers).
public enum Compression: Sendable, Equatable {
    case none
    case gzip
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
