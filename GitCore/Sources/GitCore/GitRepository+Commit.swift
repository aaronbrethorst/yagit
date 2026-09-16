import Foundation
import libgit2

extension GitRepository {
    /// Commits the index to the current branch with the configured author.
    @discardableResult
    public func commit(message: String) throws -> CommitSummary {
        let index = try index()
        var treeOID = git_oid()
        try check(git_index_write_tree(&treeOID, index), "commit")
        var tree: OpaquePointer?
        try check(git_tree_lookup(&tree, repo, &treeOID), "commit")
        defer { git_tree_free(tree) }

        var signature: UnsafeMutablePointer<git_signature>?
        try check(git_signature_default(&signature, repo), "signature")
        defer { git_signature_free(signature) }

        let parent = try headCommit()
        defer { git_commit_free(parent) }

        let parents = UnsafeMutablePointer<OpaquePointer?>.allocate(capacity: 1)
        defer { parents.deallocate() }
        parents.initialize(to: parent)

        var oid = git_oid()
        try check(git_commit_create(&oid, repo, "HEAD", signature, signature, nil, message, tree,
                                    parent == nil ? 0 : 1, parents), "commit")
        return try commitSummary(oid: oid)
    }

    /// Commits reachable from HEAD, newest first.
    public func history(limit: Int = 2000) throws -> [CommitSummary] {
        guard git_repository_head_unborn(repo) == 0 else { return [] }
        var walker: OpaquePointer?
        try check(git_revwalk_new(&walker, repo), "log")
        defer { git_revwalk_free(walker) }
        git_revwalk_sorting(walker, GIT_SORT_TOPOLOGICAL.rawValue | GIT_SORT_TIME.rawValue)
        try check(git_revwalk_push_head(walker), "log")

        var commits: [CommitSummary] = []
        var oid = git_oid()
        while commits.count < limit, git_revwalk_next(&oid, walker) == 0 {
            commits.append(try commitSummary(oid: oid))
        }
        return commits
    }

    /// A commit and the diff against its first parent (or against nothing for a root commit).
    public func commitDetail(sha: String) throws -> CommitDetail {
        var oid = git_oid()
        try check(git_oid_fromstr(&oid, sha), "lookup")
        var commit: OpaquePointer?
        try check(git_commit_lookup(&commit, repo, &oid), "lookup")
        defer { git_commit_free(commit) }

        var tree: OpaquePointer?
        try check(git_commit_tree(&tree, commit), "lookup")
        defer { git_tree_free(tree) }

        var parentTree: OpaquePointer?
        if git_commit_parentcount(commit) > 0 {
            var parent: OpaquePointer?
            try check(git_commit_parent(&parent, commit, 0), "lookup")
            defer { git_commit_free(parent) }
            try check(git_commit_tree(&parentTree, parent), "lookup")
        }
        defer { git_tree_free(parentTree) }

        var diff: OpaquePointer?
        try check(git_diff_tree_to_tree(&diff, repo, parentTree, tree, nil), "diff")
        defer { git_diff_free(diff) }

        var files: [FileDiff] = []
        for deltaIndex in 0..<git_diff_num_deltas(diff) {
            files.append(try fileDiff(from: diff!, deltaIndex: deltaIndex))
        }
        return CommitDetail(commit: CommitSummary(commit: commit!), files: files)
    }

    func commitSummary(oid: git_oid) throws -> CommitSummary {
        var oid = oid
        var commit: OpaquePointer?
        try check(git_commit_lookup(&commit, repo, &oid), "lookup")
        defer { git_commit_free(commit) }
        return CommitSummary(commit: commit!)
    }
}

extension CommitSummary {
    init(commit: OpaquePointer) {
        let author = git_commit_author(commit)!.pointee
        self.init(
            sha: String(oid: git_commit_id(commit)!.pointee),
            summary: String(cString: git_commit_summary(commit)),
            message: String(cString: git_commit_message(commit)),
            authorName: String(cString: author.name),
            authorEmail: String(cString: author.email),
            date: Date(timeIntervalSince1970: TimeInterval(git_commit_time(commit))),
            parentSHAs: (0..<git_commit_parentcount(commit)).map { String(oid: git_commit_parent_id(commit, $0)!.pointee) })
    }
}
