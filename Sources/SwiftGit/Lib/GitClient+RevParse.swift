import Foundation
import ForgeKit
import libgit2

extension GitClient {

    /// Resolve `spec` (a ref, sha, abbrev, `<ref>~N`, etc.) to a full
    /// 40-char SHA. Throws when the spec can't be resolved.
    public func resolveOID(_ spec: String) async throws -> String {
        try withRepository { repo in
            var obj: OpaquePointer?
            try check(git_revparse_single(&obj, repo, spec))
            defer { git_object_free(obj) }
            var oid = git_object_id(obj)?.pointee ?? git_oid()
            return formatOID(&oid)
        }
    }

    /// Path to the repo's `.git` directory (or the bare-repo root for
    /// bare repos). Equivalent of `git rev-parse --git-dir`. Returns
    /// nil when called outside any repo.
    public func gitDir() async throws -> String? {
        try withRepository { repo in
            git_repository_path(repo).map { String(cString: $0) }
        }
    }

    /// Working-tree root, the value `git rev-parse --show-toplevel`
    /// prints. Nil for bare repositories.
    public func toplevel() async throws -> String? {
        try withRepository { repo in
            git_repository_workdir(repo).map { String(cString: $0) }
        }
    }

    /// Tracked file paths (everything currently in the index).
    /// Equivalent of `git ls-files`.
    public func indexedPaths() async throws -> [String] {
        try withRepository { repo in
            var index: OpaquePointer?
            try check(git_repository_index(&index, repo))
            defer { git_index_free(index) }
            let count = Int(git_index_entrycount(index))
            var paths: [String] = []
            paths.reserveCapacity(count)
            for i in 0..<count {
                if let entry = git_index_get_byindex(index, i)?.pointee,
                   let p = entry.path {
                    paths.append(String(cString: p))
                }
            }
            return paths
        }
    }

    /// True when `workingDirectory` is inside a non-bare repo.
    public func isInsideWorkTree() async throws -> Bool {
        // We rely on `withRepository` succeeding plus a non-nil
        // workdir to distinguish bare from non-bare.
        do {
            return try withRepository { repo in
                git_repository_workdir(repo) != nil
            }
        } catch {
            return false
        }
    }
}
