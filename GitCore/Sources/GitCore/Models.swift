import Foundation

/// Which side of the index a change lives on.
public enum ChangeSide: String, Sendable, Hashable, Codable {
    case staged
    case unstaged
}

/// The coarse status letter shown next to a file.
public enum FileStatus: String, Sendable, Hashable, Codable {
    case modified = "M"
    case added = "A"
    case deleted = "D"
}

/// A file with changes on one side of the index. The same path can appear on both sides.
public struct ChangedFile: Sendable, Hashable, Identifiable {
    public let path: String
    public let status: FileStatus
    public let side: ChangeSide

    public init(path: String, status: FileStatus, side: ChangeSide) {
        self.path = path
        self.status = status
        self.side = side
    }

    public var id: String { "\(side.rawValue):\(path)" }

    public var fileName: String { (path as NSString).lastPathComponent }

    /// Directory portion of the path, empty for files at the repository root.
    public var directory: String {
        let dir = (path as NSString).deletingLastPathComponent
        return dir
    }
}

public struct DiffLine: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case context
        case addition
        case deletion
    }

    public let kind: Kind
    public let oldLineNumber: Int?
    public let newLineNumber: Int?
    /// Line text without its trailing newline.
    public let text: String
    /// True when this is the file's last line and it has no trailing newline.
    public let missingTrailingNewline: Bool

    public init(kind: Kind, oldLineNumber: Int?, newLineNumber: Int?, text: String, missingTrailingNewline: Bool = false) {
        self.kind = kind
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.text = text
        self.missingTrailingNewline = missingTrailingNewline
    }
}

public struct DiffHunk: Sendable, Hashable, Identifiable {
    /// Position of the hunk within its file diff.
    public let index: Int
    /// The `@@ … @@` header line, without trailing newline.
    public let header: String
    public let oldStart: Int
    public let oldLines: Int
    public let newStart: Int
    public let newLines: Int
    public let lines: [DiffLine]

    public init(index: Int, header: String, oldStart: Int, oldLines: Int, newStart: Int, newLines: Int, lines: [DiffLine]) {
        self.index = index
        self.header = header
        self.oldStart = oldStart
        self.oldLines = oldLines
        self.newStart = newStart
        self.newLines = newLines
        self.lines = lines
    }

    public var id: Int { index }
}

public struct FileDiff: Sendable, Hashable, Identifiable {
    public let path: String
    public let status: FileStatus
    public let isBinary: Bool
    public let additions: Int
    public let deletions: Int
    public let hunks: [DiffHunk]

    public init(path: String, status: FileStatus, isBinary: Bool, additions: Int, deletions: Int, hunks: [DiffHunk]) {
        self.path = path
        self.status = status
        self.isBinary = isBinary
        self.additions = additions
        self.deletions = deletions
        self.hunks = hunks
    }

    public var id: String { path }
    public var fileName: String { (path as NSString).lastPathComponent }

    /// Directory portion of the path, empty for files at the repository root.
    public var directory: String { (path as NSString).deletingLastPathComponent }
}

public struct BranchInfo: Sendable, Hashable, Identifiable {
    public let name: String
    public let isCurrent: Bool
    /// Commits ahead of the upstream, or `nil` when the branch has no upstream on origin.
    public let ahead: Int?

    public init(name: String, isCurrent: Bool, ahead: Int?) {
        self.name = name
        self.isCurrent = isCurrent
        self.ahead = ahead
    }

    public var id: String { name }
}

public struct Author: Sendable, Hashable {
    public let name: String
    public let email: String

    public init(name: String, email: String) {
        self.name = name
        self.email = email
    }
}

public struct CommitSummary: Sendable, Hashable, Identifiable {
    public let sha: String
    public let summary: String
    public let message: String
    public let authorName: String
    public let authorEmail: String
    public let date: Date
    /// Parent commits in libgit2 order: the first parent first, empty for a root commit.
    public let parentSHAs: [String]

    public init(sha: String, summary: String, message: String, authorName: String, authorEmail: String, date: Date,
                parentSHAs: [String] = []) {
        self.sha = sha
        self.summary = summary
        self.message = message
        self.authorName = authorName
        self.authorEmail = authorEmail
        self.date = date
        self.parentSHAs = parentSHAs
    }

    public var id: String { sha }
    public var shortSHA: String { String(sha.prefix(7)) }
}

public struct CommitDetail: Sendable, Hashable {
    public let commit: CommitSummary
    public let files: [FileDiff]

    public init(commit: CommitSummary, files: [FileDiff]) {
        self.commit = commit
        self.files = files
    }
}

/// A piece of lane line within half a row: from a column at one edge of the half to a column at the
/// other. Equal columns draw a straight line; different columns draw a curve.
public struct GraphSegment: Sendable, Hashable {
    public let fromColumn: Int
    public let toColumn: Int
    public let colorIndex: Int

    public init(fromColumn: Int, toColumn: Int, colorIndex: Int) {
        self.fromColumn = fromColumn
        self.toColumn = toColumn
        self.colorIndex = colorIndex
    }
}

/// One commit's slice of the lane graph. `upper` runs from the row's top edge to the dot's center,
/// `lower` from the dot's center to the bottom edge.
public struct GraphRow: Sendable, Hashable {
    public let column: Int
    public let colorIndex: Int
    public let isMerge: Bool
    public let upper: [GraphSegment]
    public let lower: [GraphSegment]

    public init(column: Int, colorIndex: Int, isMerge: Bool, upper: [GraphSegment], lower: [GraphSegment]) {
        self.column = column
        self.colorIndex = colorIndex
        self.isMerge = isMerge
        self.upper = upper
        self.lower = lower
    }
}

public struct RepositorySnapshot: Sendable, Hashable {
    public let currentBranch: String
    public let branches: [BranchInfo]
    /// Remote-tracking branches worth showing: `origin/main` and `origin/<current>`.
    public let remoteBranches: [String]
    public let staged: [ChangedFile]
    public let unstaged: [ChangedFile]
    /// `nil` when `user.name` / `user.email` are not configured.
    public let author: Author?

    public init(currentBranch: String, branches: [BranchInfo], remoteBranches: [String], staged: [ChangedFile], unstaged: [ChangedFile], author: Author?) {
        self.currentBranch = currentBranch
        self.branches = branches
        self.remoteBranches = remoteBranches
        self.staged = staged
        self.unstaged = unstaged
        self.author = author
    }

    public var current: BranchInfo? { branches.first { $0.isCurrent } }
}

public enum FetchResult: Sendable, Hashable {
    case upToDate
    case updated
}

/// An error raised by libgit2, carrying its last error message.
public struct GitError: Error, Sendable, Hashable, LocalizedError {
    public let code: Int32
    public let operation: String
    public let message: String

    public init(code: Int32, operation: String, message: String) {
        self.code = code
        self.operation = operation
        self.message = message
    }

    public var errorDescription: String? { message }
}
