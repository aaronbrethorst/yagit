import Foundation
import libgit2

extension GitRepository {
    /// Stages every unstaged change in `path`.
    public func stage(path: String) throws {
        let index = try index()
        let exists = FileManager.default.fileExists(atPath: url.appendingPathComponent(path).path)
        if exists {
            try check(git_index_add_bypath(index, path), "stage")
        } else {
            try check(git_index_remove_bypath(index, path), "stage")
        }
        try check(git_index_write(index), "stage")
    }

    /// Moves every staged change in `path` back to the working tree (`git reset -- path`).
    public func unstage(path: String) throws {
        let head = try headCommit()
        defer { git_commit_free(head) }
        try withStrArray([path]) { pathspec in
            try check(git_reset_default(repo, head, &pathspec), "unstage")
        }
    }

    /// Stages a single hunk of an unstaged change.
    public func stageHunk(path: String, hunk: DiffHunk, fileStatus: FileStatus) throws {
        guard fileStatus == .modified else { return try stage(path: path) }
        try apply(patch: patchText(path: path, hunk: hunk, reversed: false))
    }

    /// Returns a single staged hunk to the working tree.
    public func unstageHunk(path: String, hunk: DiffHunk, fileStatus: FileStatus) throws {
        guard fileStatus == .modified else { return try unstage(path: path) }
        try apply(patch: patchText(path: path, hunk: hunk, reversed: true))
    }

    private func apply(patch text: String) throws {
        let (diff, status) = text.withCString { buffer -> (OpaquePointer?, Int32) in
            var diff: OpaquePointer?
            let status = git_diff_from_buffer(&diff, buffer, strlen(buffer))
            return (diff, status)
        }
        try check(status, "parse patch")
        defer { git_diff_free(diff) }
        var options = git_apply_options()
        try check(git_apply_options_init(&options, UInt32(GIT_APPLY_OPTIONS_VERSION)), "apply")
        try check(git_apply(repo, diff, GIT_APPLY_LOCATION_INDEX, &options), "apply")
    }

    /// A minimal unified patch containing only `hunk`. Reversed patches unstage.
    func patchText(path: String, hunk: DiffHunk, reversed: Bool) -> String {
        let (oldStart, oldLines, newStart, newLines) = reversed
            ? (hunk.newStart, hunk.newLines, hunk.oldStart, hunk.oldLines)
            : (hunk.oldStart, hunk.oldLines, hunk.newStart, hunk.newLines)
        var text = "diff --git a/\(path) b/\(path)\n--- a/\(path)\n+++ b/\(path)\n"
        text += "@@ -\(oldStart),\(oldLines) +\(newStart),\(newLines) @@\n"
        for line in hunk.lines {
            let prefix: String
            switch line.kind {
            case .context: prefix = " "
            case .addition: prefix = reversed ? "-" : "+"
            case .deletion: prefix = reversed ? "+" : "-"
            }
            text += prefix + line.text + "\n"
            if line.missingTrailingNewline { text += "\\ No newline at end of file\n" }
        }
        return text
    }
}
