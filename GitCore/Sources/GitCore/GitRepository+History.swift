import Foundation
import libgit2

extension GitRepository {
    public static let historyLimit = 2000

    /// Commits reachable from HEAD, every local branch, the sidebar's remote branches, and every tag,
    /// newest first, each with its ref badges and its slice of the lane graph.
    ///
    /// Any sorted walk visits every reachable commit before returning the first one; `limit` only
    /// bounds how many summaries are built.
    public func history(limit: Int = GitRepository.historyLimit) throws -> [HistoryEntry] {
        let refs = try historyRefs()

        var walker: OpaquePointer?
        try check(git_revwalk_new(&walker, repo), "log")
        defer { git_revwalk_free(walker) }
        git_revwalk_sorting(walker, GIT_SORT_TOPOLOGICAL.rawValue | GIT_SORT_TIME.rawValue)
        if git_repository_head_unborn(repo) == 0 {
            try check(git_revwalk_push_head(walker), "log")
        }
        for sha in refs.tips {
            var oid = git_oid()
            try check(git_oid_fromstr(&oid, sha), "log")
            try check(git_revwalk_push(walker, &oid), "log")
        }
        // Peels annotated tags and skips tags of trees or blobs.
        try check(git_revwalk_push_glob(walker, "refs/tags"), "log")

        var commits: [CommitSummary] = []
        var oid = git_oid()
        while commits.count < limit {
            let status = git_revwalk_next(&oid, walker)
            if status == GIT_ITEROVER.rawValue { break }
            try check(status, "log")
            commits.append(try commitSummary(oid: oid))
        }
        let rows = GraphLayout.rows(for: commits, mainlineTip: mainlineTip())
        return zip(commits, rows).map { commit, row in
            HistoryEntry(commit: commit, refs: refs.labels[commit.sha] ?? [], graph: row)
        }
    }

    /// Branch tips to start the walk from, and every ref's badge keyed by the commit it points to.
    private func historyRefs() throws -> (tips: Set<String>, labels: [String: [RefLabel]]) {
        let current = try currentBranchName()
        let detached = git_repository_head_detached(repo) == 1
        var tips = Set<String>()
        var labels: [String: [RefLabel]] = [:]

        if detached, let head = try headCommit() {
            defer { git_commit_free(head) }
            labels[String(oid: git_commit_id(head)!.pointee), default: []].append(RefLabel(name: "HEAD", kind: .head))
        }

        try forEachBranch(type: GIT_BRANCH_LOCAL) { reference, name in
            guard let sha = try peeledCommitSHA(reference) else { return }
            tips.insert(sha)
            labels[sha, default: []].append(RefLabel(name: name, kind: .localBranch(isCurrent: !detached && name == current)))
        }

        for name in try remoteBranches(current: current) {
            var reference: OpaquePointer?
            guard git_reference_lookup(&reference, repo, "refs/remotes/\(name)") == 0 else { continue }
            defer { git_reference_free(reference) }
            guard let sha = try peeledCommitSHA(reference!) else { continue }
            tips.insert(sha)
            labels[sha, default: []].append(RefLabel(name: name, kind: .remoteBranch))
        }

        var iterator: UnsafeMutablePointer<git_reference_iterator>?
        try check(git_reference_iterator_glob_new(&iterator, repo, "refs/tags/*"), "log")
        defer { git_reference_iterator_free(iterator) }
        while true {
            var reference: OpaquePointer?
            let status = git_reference_next(&reference, iterator)
            if status == GIT_ITEROVER.rawValue { break }
            try check(status, "log")
            defer { git_reference_free(reference) }
            guard let sha = try peeledCommitSHA(reference!) else { continue }
            labels[sha, default: []].append(RefLabel(name: String(cString: git_reference_shorthand(reference)), kind: .tag))
        }

        return (tips, labels.mapValues { $0.sorted(by: RefLabel.displayOrder) })
    }

    /// The trunk drawn in column 0: `main`, else `master`, else `origin/main`, else HEAD.
    private func mainlineTip() -> String? {
        for name in ["refs/heads/main", "refs/heads/master", "refs/remotes/origin/main", "HEAD"] {
            var reference: OpaquePointer?
            guard git_reference_lookup(&reference, repo, name) == 0 else { continue }
            defer { git_reference_free(reference) }
            if let sha = try? peeledCommitSHA(reference!) { return sha }
        }
        return nil
    }

    /// The commit a reference ultimately points to, or `nil` when it doesn't lead to a commit
    /// (a tag of a tree or blob, or an unborn HEAD). Other failures throw.
    private func peeledCommitSHA(_ reference: OpaquePointer) throws -> String? {
        var object: OpaquePointer?
        let status = git_reference_peel(&object, reference, GIT_OBJECT_COMMIT)
        if [GIT_EPEEL.rawValue, GIT_EINVALIDSPEC.rawValue, GIT_ENOTFOUND.rawValue].contains(status) { return nil }
        try check(status, "log")
        defer { git_object_free(object) }
        return String(oid: git_object_id(object)!.pointee)
    }
}
