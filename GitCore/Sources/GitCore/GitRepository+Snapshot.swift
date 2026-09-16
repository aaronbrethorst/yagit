import Foundation
import libgit2

extension GitRepository {
    public func snapshot() throws -> RepositorySnapshot {
        let currentBranch = try currentBranchName()
        let (staged, unstaged) = try changedFiles()
        return RepositorySnapshot(
            currentBranch: currentBranch,
            branches: try localBranches(current: currentBranch),
            remoteBranches: try remoteBranches(current: currentBranch),
            staged: staged,
            unstaged: unstaged,
            author: try? author()
        )
    }

    public func author() throws -> Author {
        var signature: UnsafeMutablePointer<git_signature>?
        try check(git_signature_default(&signature, repo), "signature")
        defer { git_signature_free(signature) }
        return Author(name: String(cString: signature!.pointee.name), email: String(cString: signature!.pointee.email))
    }

    // MARK: - Branches

    func currentBranchName() throws -> String {
        var head: OpaquePointer?
        try check(git_reference_lookup(&head, repo, "HEAD"), "HEAD")
        defer { git_reference_free(head) }
        if git_reference_type(head) == GIT_REFERENCE_SYMBOLIC, let target = git_reference_symbolic_target(head) {
            let name = String(cString: target)
            return name.hasPrefix("refs/heads/") ? String(name.dropFirst("refs/heads/".count)) : name
        }
        // Detached HEAD: show the short SHA.
        if let oid = git_reference_target(head) {
            return String(String(oid: oid.pointee).prefix(7))
        }
        return "HEAD"
    }

    private func localBranches(current: String) throws -> [BranchInfo] {
        var branches: [BranchInfo] = []
        try forEachBranch(type: GIT_BRANCH_LOCAL) { reference, name in
            branches.append(BranchInfo(name: name, isCurrent: name == current, ahead: aheadCount(of: reference, name: name)))
        }
        return branches.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func remoteBranches(current: String) throws -> [String] {
        var names: [String] = []
        try forEachBranch(type: GIT_BRANCH_REMOTE) { _, name in
            if name == "origin/main" || name == "origin/\(current)" { names.append(name) }
        }
        return names.sorted()
    }

    func forEachBranch(type: git_branch_t, _ body: (OpaquePointer, String) throws -> Void) throws {
        var iterator: OpaquePointer?
        try check(git_branch_iterator_new(&iterator, repo, type), "branch list")
        defer { git_branch_iterator_free(iterator) }
        while true {
            var reference: OpaquePointer?
            var branchType = GIT_BRANCH_LOCAL
            let status = git_branch_next(&reference, &branchType, iterator)
            if status == GIT_ITEROVER.rawValue { break }
            try check(status, "branch list")
            defer { git_reference_free(reference) }
            var namePointer: UnsafePointer<CChar>?
            try check(git_branch_name(&namePointer, reference), "branch name")
            try body(reference!, String(cString: namePointer!))
        }
    }

    /// Commits ahead of the upstream (or `origin/<name>` when no upstream is configured).
    private func aheadCount(of reference: OpaquePointer, name: String) -> Int? {
        guard let local = git_reference_target(reference) else { return nil }
        var upstream: OpaquePointer?
        if git_branch_upstream(&upstream, reference) != 0 {
            upstream = nil
            guard git_reference_lookup(&upstream, repo, "refs/remotes/origin/\(name)") == 0 else { return nil }
        }
        defer { git_reference_free(upstream) }
        var resolved: OpaquePointer?
        guard git_reference_resolve(&resolved, upstream) == 0, let remoteOID = git_reference_target(resolved) else { return nil }
        defer { git_reference_free(resolved) }
        var ahead = 0, behind = 0
        guard git_graph_ahead_behind(&ahead, &behind, repo, local, remoteOID) == 0 else { return nil }
        return ahead
    }

    // MARK: - Status

    private func changedFiles() throws -> (staged: [ChangedFile], unstaged: [ChangedFile]) {
        var options = git_status_options()
        try check(git_status_options_init(&options, UInt32(GIT_STATUS_OPTIONS_VERSION)), "status")
        options.show = GIT_STATUS_SHOW_INDEX_AND_WORKDIR
        options.flags = GIT_STATUS_OPT_INCLUDE_UNTRACKED.rawValue
            | GIT_STATUS_OPT_RECURSE_UNTRACKED_DIRS.rawValue
            | GIT_STATUS_OPT_SORT_CASE_SENSITIVELY.rawValue

        var list: OpaquePointer?
        try check(git_status_list_new(&list, repo, &options), "status")
        defer { git_status_list_free(list) }

        var staged: [ChangedFile] = []
        var unstaged: [ChangedFile] = []
        for i in 0..<git_status_list_entrycount(list) {
            guard let entry = git_status_byindex(list, i)?.pointee else { continue }
            let flags = entry.status.rawValue
            if flags & GIT_STATUS_CONFLICTED.rawValue != 0 || flags & GIT_STATUS_IGNORED.rawValue != 0 { continue }

            if let delta = entry.head_to_index?.pointee, let status = FileStatus(indexFlags: flags) {
                staged.append(ChangedFile(path: delta.displayPath, status: status, side: .staged))
            }
            if let delta = entry.index_to_workdir?.pointee, let status = FileStatus(workdirFlags: flags) {
                unstaged.append(ChangedFile(path: delta.displayPath, status: status, side: .unstaged))
            }
        }
        return (staged, unstaged)
    }
}

extension git_diff_delta {
    /// The path to show: the new path, or the old one for deletions.
    var displayPath: String {
        if status == GIT_DELTA_DELETED, let old = old_file.path { return String(cString: old) }
        if let new = new_file.path { return String(cString: new) }
        if let old = old_file.path { return String(cString: old) }
        return ""
    }
}

extension FileStatus {
    init?(indexFlags flags: UInt32) {
        if flags & GIT_STATUS_INDEX_NEW.rawValue != 0 { self = .added }
        else if flags & GIT_STATUS_INDEX_DELETED.rawValue != 0 { self = .deleted }
        else if flags & (GIT_STATUS_INDEX_MODIFIED.rawValue | GIT_STATUS_INDEX_RENAMED.rawValue | GIT_STATUS_INDEX_TYPECHANGE.rawValue) != 0 { self = .modified }
        else { return nil }
    }

    init?(workdirFlags flags: UInt32) {
        if flags & GIT_STATUS_WT_NEW.rawValue != 0 { self = .added }
        else if flags & GIT_STATUS_WT_DELETED.rawValue != 0 { self = .deleted }
        else if flags & (GIT_STATUS_WT_MODIFIED.rawValue | GIT_STATUS_WT_RENAMED.rawValue | GIT_STATUS_WT_TYPECHANGE.rawValue) != 0 { self = .modified }
        else { return nil }
    }

    init(deltaStatus: git_delta_t) {
        switch deltaStatus {
        case GIT_DELTA_ADDED, GIT_DELTA_UNTRACKED: self = .added
        case GIT_DELTA_DELETED: self = .deleted
        default: self = .modified
        }
    }
}
