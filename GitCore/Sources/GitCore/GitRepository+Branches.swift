import Foundation
import libgit2

extension GitRepository {
    /// Checks out a local branch. Uncommitted changes carry over; conflicts fail the switch.
    public func switchBranch(named name: String) throws {
        var branch: OpaquePointer?
        try check(git_branch_lookup(&branch, repo, name, GIT_BRANCH_LOCAL), "switch")
        defer { git_reference_free(branch) }

        var target: OpaquePointer?
        try check(git_reference_peel(&target, branch, GIT_OBJECT_COMMIT), "switch")
        defer { git_object_free(target) }

        var options = git_checkout_options()
        try check(git_checkout_options_init(&options, UInt32(GIT_CHECKOUT_OPTIONS_VERSION)), "switch")
        options.checkout_strategy = GIT_CHECKOUT_SAFE.rawValue
        try check(git_checkout_tree(repo, target, &options), "switch")
        try check(git_repository_set_head(repo, "refs/heads/\(name)"), "switch")
    }

    /// Creates a branch at HEAD and checks it out. Refuses names that already exist.
    public func createBranch(named name: String) throws {
        var existing: OpaquePointer?
        if git_branch_lookup(&existing, repo, name, GIT_BRANCH_LOCAL) == 0 {
            git_reference_free(existing)
            throw GitError(code: -1, operation: "branch", message: "A branch named ‘\(name)’ already exists.")
        }
        guard git_reference_is_valid_name("refs/heads/\(name)") == 1 else {
            throw GitError(code: -1, operation: "branch", message: "‘\(name)’ is not a valid branch name.")
        }
        guard let head = try headCommit() else {
            throw GitError(code: -1, operation: "branch", message: "Make a first commit before creating a branch.")
        }
        defer { git_commit_free(head) }

        var branch: OpaquePointer?
        try check(git_branch_create(&branch, repo, name, head, 0), "branch")
        git_reference_free(branch)
        try switchBranch(named: name)
    }

    /// Fetches `origin` and reports whether any remote-tracking ref moved.
    public func fetch() async throws -> FetchResult {
        var remote: OpaquePointer?
        try check(git_remote_lookup(&remote, repo, "origin"), "fetch")
        defer { git_remote_free(remote) }

        let before = try remoteRefs()
        var options = git_fetch_options()
        try check(git_fetch_options_init(&options, UInt32(GIT_FETCH_OPTIONS_VERSION)), "fetch")
        try check(git_remote_fetch(remote, nil, &options, nil), "fetch")
        let after = try remoteRefs()
        return before == after ? .upToDate : .updated
    }

    private func remoteRefs() throws -> [String: String] {
        var iterator: OpaquePointer?
        try check(git_branch_iterator_new(&iterator, repo, GIT_BRANCH_REMOTE), "fetch")
        defer { git_branch_iterator_free(iterator) }
        var refs: [String: String] = [:]
        while true {
            var reference: OpaquePointer?
            var type = GIT_BRANCH_REMOTE
            let status = git_branch_next(&reference, &type, iterator)
            if status == GIT_ITEROVER.rawValue { break }
            try check(status, "fetch")
            defer { git_reference_free(reference) }
            if let name = git_reference_name(reference), let oid = git_reference_target(reference) {
                refs[String(cString: name)] = String(oid: oid.pointee)
            }
        }
        return refs
    }
}
