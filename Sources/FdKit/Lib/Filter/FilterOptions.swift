import Foundation

/// Post-walk filters that operate on individual `Walker.Entry` values.
///
/// The walker itself is responsible for honoring `.gitignore` and the
/// hidden/symlink/depth gates. `FilterOptions` covers the slice of fd's
/// flag surface that decides *which* of the surviving entries should
/// actually be printed: file-type kind, size, modification time,
/// exclude globs, depth bounds, the `--max-results` cap.
public struct FilterOptions: Sendable {

    /// One of fd's `--type` codes. `file`, `directory`, `symlink`,
    /// `executable`, `empty`, plus the unix special-file kinds. fd uses
    /// the same letters; we keep the long names for readability and
    /// the short letters at the parser layer.
    public enum FileType: Sendable, Hashable {
        case file
        case directory
        case symlink
        case executable
        case empty
        case socket
        case pipe
        case blockDevice
        case charDevice
    }

    /// Logical OR over this set. Empty = no type filter, everything
    /// passes.
    public var fileTypes: Set<FileType> = []

    /// Glob patterns that suppress matching entries. Repeatable
    /// `-E`/`--exclude`. Compiled and applied like an extra gitignore
    /// row, except they always win — no negation.
    public var excludePatterns: [String] = []

    /// `--size +N{b,k,M,G,T,Ki,Mi,Gi,Ti}` / `--size -N…`. `+` means
    /// "at least N", `-` means "at most N". Repeatable; the entry must
    /// satisfy every constraint to pass.
    public var sizeConstraints: [SizeConstraint] = []

    public struct SizeConstraint: Sendable, Equatable {
        public enum Direction: Sendable {
            case atLeast
            case atMost
            /// Unsigned `--size N` means exactly N bytes — fd-style.
            /// Only the signed forms (`+N` / `-N`) loosen this into a
            /// bound.
            case exactly
        }
        public let direction: Direction
        public let bytes: UInt64

        public init(direction: Direction, bytes: UInt64) {
            self.direction = direction
            self.bytes = bytes
        }
    }

    /// `--changed-within` / `--changed-before`. Mutually combinable.
    public var changedWithin: TimeInterval? = nil
    public var changedBefore: TimeInterval? = nil

    /// Minimum recursion depth (`--min-depth`). Root is depth 0. The
    /// walker emits entries shallower than this; we drop them here.
    public var minDepth: Int? = nil

    /// Hard cap on emitted entries (`--max-results`). When reached, the
    /// engine stops walking.
    public var maxResults: Int? = nil

    public init() {}
}
