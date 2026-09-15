import Foundation
import libgit2

/// One libgit2 repository handle. All operations are serialized through the actor.
public actor GitRepository {
    nonisolated(unsafe) let repo: OpaquePointer
    public nonisolated let url: URL

    /// Opens the repository containing `url` (searching parent directories). Never creates one.
    public init(url: URL) throws {
        git_libgit2_init()
        var pointer: OpaquePointer?
        let status = git_repository_open_ext(&pointer, url.path, 0, nil)
        guard status == 0, let pointer else {
            let error = GitError.last(code: status, operation: "open")
            git_libgit2_shutdown()
            throw error
        }
        repo = pointer
        if let workdir = git_repository_workdir(pointer) {
            self.url = URL(fileURLWithPath: String(cString: workdir), isDirectory: true)
        } else {
            self.url = url
        }
    }

    deinit {
        git_repository_free(repo)
        git_libgit2_shutdown()
    }

    // MARK: - Shared helpers

    func check(_ status: Int32, _ operation: String) throws {
        guard status >= 0 else { throw GitError.last(code: status, operation: operation) }
    }

    /// The repository index, re-read from disk if another process changed it.
    func index() throws -> OpaquePointer {
        var index: OpaquePointer?
        try check(git_repository_index(&index, repo), "index")
        try check(git_index_read(index, 0), "index read")
        return index!
    }

    /// The commit HEAD points to, or `nil` for an unborn branch.
    func headCommit() throws -> OpaquePointer? {
        if git_repository_head_unborn(repo) == 1 { return nil }
        var commit: OpaquePointer?
        try check(git_reference_name_to_id_commit(&commit), "HEAD")
        return commit
    }

    private func git_reference_name_to_id_commit(_ out: inout OpaquePointer?) -> Int32 {
        var oid = git_oid()
        let status = git_reference_name_to_id(&oid, repo, "HEAD")
        guard status == 0 else { return status }
        return git_commit_lookup(&out, repo, &oid)
    }

    /// The tree of HEAD, or `nil` for an unborn branch. Caller frees.
    func headTree() throws -> OpaquePointer? {
        guard let commit = try headCommit() else { return nil }
        defer { git_commit_free(commit) }
        var tree: OpaquePointer?
        try check(git_commit_tree(&tree, commit), "HEAD tree")
        return tree
    }

    func withStrArray<T>(_ strings: [String], _ body: (inout git_strarray) throws -> T) rethrows -> T {
        var cStrings: [UnsafeMutablePointer<CChar>?] = strings.map { strdup($0) }
        defer { cStrings.forEach { free($0) } }
        return try cStrings.withUnsafeMutableBufferPointer { buffer in
            var array = git_strarray(strings: buffer.baseAddress, count: strings.count)
            return try body(&array)
        }
    }
}

extension GitError {
    /// Builds an error from libgit2's thread-local last error.
    static func last(code: Int32, operation: String) -> GitError {
        let message: String
        if let error = git_error_last(), let text = error.pointee.message {
            message = String(cString: text)
        } else {
            message = "libgit2 error \(code)"
        }
        return GitError(code: code, operation: operation, message: message)
    }
}

extension String {
    init(oid: git_oid) {
        var oid = oid
        var buffer = [CChar](repeating: 0, count: Int(GIT_OID_MAX_HEXSIZE) + 1)
        git_oid_tostr(&buffer, buffer.count, &oid)
        self = String(cString: buffer)
    }
}
