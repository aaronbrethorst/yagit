import Foundation
import libgit2

extension GitRepository {
    /// The diff for one file on one side of the index, or `nil` if that side has no change.
    public func diff(path: String, side: ChangeSide) throws -> FileDiff? {
        let diff = try makeDiff(path: path, side: side)
        defer { git_diff_free(diff) }
        guard git_diff_num_deltas(diff) > 0 else { return nil }
        return try fileDiff(from: diff, deltaIndex: 0)
    }

    /// Builds a libgit2 diff limited to `path`. Caller frees.
    func makeDiff(path: String, side: ChangeSide) throws -> OpaquePointer {
        var options = git_diff_options()
        try check(git_diff_options_init(&options, UInt32(GIT_DIFF_OPTIONS_VERSION)), "diff")
        options.flags |= GIT_DIFF_DISABLE_PATHSPEC_MATCH.rawValue
        let index = try index()
        let tree = side == .staged ? try headTree() : nil
        defer { git_tree_free(tree) }
        if side == .unstaged {
            options.flags |= GIT_DIFF_INCLUDE_UNTRACKED.rawValue
                | GIT_DIFF_SHOW_UNTRACKED_CONTENT.rawValue
                | GIT_DIFF_RECURSE_UNTRACKED_DIRS.rawValue
        }
        let (diff, status) = withStrArray([path]) { pathspec -> (OpaquePointer?, Int32) in
            options.pathspec = pathspec
            var diff: OpaquePointer?
            let status = side == .unstaged
                ? git_diff_index_to_workdir(&diff, repo, index, &options)
                : git_diff_tree_to_index(&diff, repo, tree, index, &options)
            return (diff, status)
        }
        try check(status, "diff")
        return diff!
    }

    /// Converts one delta of a libgit2 diff into a `FileDiff`.
    func fileDiff(from diff: OpaquePointer, deltaIndex: Int) throws -> FileDiff {
        var patch: OpaquePointer?
        try check(git_patch_from_diff(&patch, diff, deltaIndex), "patch")
        defer { git_patch_free(patch) }
        let delta = git_patch_get_delta(patch)!.pointee

        var additions = 0, deletions = 0
        try check(git_patch_line_stats(nil, &additions, &deletions, patch), "patch stats")

        var hunks: [DiffHunk] = []
        for hunkIndex in 0..<git_patch_num_hunks(patch) {
            var hunkPointer: UnsafePointer<git_diff_hunk>?
            var lineCount = 0
            try check(git_patch_get_hunk(&hunkPointer, &lineCount, patch, hunkIndex), "hunk")
            let hunk = hunkPointer!.pointee

            var lines: [DiffLine] = []
            for lineIndex in 0..<lineCount {
                var linePointer: UnsafePointer<git_diff_line>?
                try check(git_patch_get_line_in_hunk(&linePointer, patch, hunkIndex, lineIndex), "line")
                let line = linePointer!.pointee
                switch git_diff_line_t(UInt32(UInt8(bitPattern: line.origin))) {
                case GIT_DIFF_LINE_CONTEXT_EOFNL, GIT_DIFF_LINE_ADD_EOFNL, GIT_DIFF_LINE_DEL_EOFNL:
                    if let last = lines.popLast() {
                        lines.append(DiffLine(kind: last.kind, oldLineNumber: last.oldLineNumber,
                                              newLineNumber: last.newLineNumber, text: last.text,
                                              missingTrailingNewline: true))
                    }
                default:
                    lines.append(DiffLine(raw: line))
                }
            }

            hunks.append(DiffHunk(
                index: hunkIndex,
                header: hunk.headerText,
                oldStart: Int(hunk.old_start), oldLines: Int(hunk.old_lines),
                newStart: Int(hunk.new_start), newLines: Int(hunk.new_lines),
                lines: lines))
        }

        return FileDiff(
            path: delta.displayPath,
            status: FileStatus(deltaStatus: delta.status),
            isBinary: delta.flags & GIT_DIFF_FLAG_BINARY.rawValue != 0,
            additions: additions,
            deletions: deletions,
            hunks: hunks)
    }
}

extension DiffLine {
    init(raw line: git_diff_line) {
        let kind: Kind
        switch git_diff_line_t(UInt32(UInt8(bitPattern: line.origin))) {
        case GIT_DIFF_LINE_ADDITION: kind = .addition
        case GIT_DIFF_LINE_DELETION: kind = .deletion
        default: kind = .context
        }
        var text = String(decoding: UnsafeRawBufferPointer(start: line.content, count: line.content_len), as: UTF8.self)
        if text.hasSuffix("\n") { text.removeLast() }
        if text.hasSuffix("\r") { text.removeLast() }
        self.init(
            kind: kind,
            oldLineNumber: line.old_lineno >= 0 ? Int(line.old_lineno) : nil,
            newLineNumber: line.new_lineno >= 0 ? Int(line.new_lineno) : nil,
            text: text)
    }
}

extension git_diff_hunk {
    var headerText: String {
        var header = self.header
        var text = withUnsafePointer(to: &header) { pointer in
            pointer.withMemoryRebound(to: UInt8.self, capacity: header_len) { bytes in
                String(decoding: UnsafeBufferPointer(start: bytes, count: header_len), as: UTF8.self)
            }
        }
        while text.hasSuffix("\n") || text.hasSuffix("\r") { text.removeLast() }
        return text
    }
}
