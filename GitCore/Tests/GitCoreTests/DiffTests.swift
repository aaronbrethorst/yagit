import Foundation
import Testing
@testable import GitCore

/// Twenty numbered lines, far enough apart that edits at both ends form separate hunks.
let twentyLines = (1...20).map { "line \($0)" }.joined(separator: "\n") + "\n"

func editedTwentyLines() -> String {
    var lines = (1...20).map { "line \($0)" }
    lines[1] = "line 2 changed"
    lines[17] = "line 18 changed"
    lines.insert("inserted after 18", at: 18)
    return lines.joined(separator: "\n") + "\n"
}

@Suite struct DiffTests {
    @Test func modifiedFileHasTwoHunksWithBothGutters() async throws {
        let fixture = try TestRepository()
        try fixture.write("a.txt", twentyLines)
        try fixture.commitAll("Initial")
        try fixture.write("a.txt", editedTwentyLines())

        let repo = try GitRepository(url: fixture.url)
        let diff = try #require(try await repo.diff(path: "a.txt", side: .unstaged))

        #expect(diff.path == "a.txt")
        #expect(diff.status == .modified)
        #expect(diff.isBinary == false)
        #expect(diff.additions == 3)
        #expect(diff.deletions == 2)
        #expect(diff.hunks.count == 2)

        let first = diff.hunks[0]
        #expect(first.header == "@@ -1,5 +1,5 @@")
        #expect(first.oldStart == 1 && first.newStart == 1)
        #expect(first.lines.map(\.kind) == [.context, .deletion, .addition, .context, .context, .context])
        #expect(first.lines[1] == DiffLine(kind: .deletion, oldLineNumber: 2, newLineNumber: nil, text: "line 2"))
        #expect(first.lines[2] == DiffLine(kind: .addition, oldLineNumber: nil, newLineNumber: 2, text: "line 2 changed"))
        #expect(first.lines[3] == DiffLine(kind: .context, oldLineNumber: 3, newLineNumber: 3, text: "line 3"))

        let second = diff.hunks[1]
        #expect(second.index == 1)
        #expect(second.header == "@@ -15,6 +15,7 @@ line 14")
        #expect(second.lines.filter { $0.kind == .addition }.map(\.text) == ["line 18 changed", "inserted after 18"])
    }

    @Test func untrackedFileIsOneHunkOfAdditions() async throws {
        let fixture = try TestRepository()
        try fixture.write("a.txt", "a\n")
        try fixture.commitAll("Initial")
        try fixture.write("Sources/new.swift", "let x = 1\nlet y = 2\n")

        let repo = try GitRepository(url: fixture.url)
        let diff = try #require(try await repo.diff(path: "Sources/new.swift", side: .unstaged))

        #expect(diff.status == .added)
        #expect(diff.additions == 2)
        #expect(diff.hunks.count == 1)
        #expect(diff.hunks[0].lines.allSatisfy { $0.kind == .addition })
        #expect(diff.hunks[0].lines.map(\.newLineNumber) == [1, 2])
    }

    @Test func stagedSideShowsIndexAgainstHead() async throws {
        let fixture = try TestRepository()
        try fixture.write("a.txt", "one\n")
        try fixture.commitAll("Initial")
        try fixture.write("a.txt", "two\n")
        try fixture.git("add", "a.txt")
        try fixture.write("a.txt", "three\n")

        let repo = try GitRepository(url: fixture.url)
        let staged = try #require(try await repo.diff(path: "a.txt", side: .staged))
        let unstaged = try #require(try await repo.diff(path: "a.txt", side: .unstaged))

        #expect(staged.hunks[0].lines.map(\.text) == ["one", "two"])
        #expect(unstaged.hunks[0].lines.map(\.text) == ["two", "three"])
    }

    @Test func missingSideReturnsNil() async throws {
        let fixture = try TestRepository()
        try fixture.write("a.txt", "one\n")
        try fixture.commitAll("Initial")
        try fixture.write("a.txt", "two\n")

        let repo = try GitRepository(url: fixture.url)
        #expect(try await repo.diff(path: "a.txt", side: .staged) == nil)
        #expect(try await repo.diff(path: "missing.txt", side: .unstaged) == nil)
    }

    @Test func missingTrailingNewlineIsFlagged() async throws {
        let fixture = try TestRepository()
        try fixture.write("a.txt", "one\ntwo\n")
        try fixture.commitAll("Initial")
        try fixture.write("a.txt", "one\ntwo")

        let repo = try GitRepository(url: fixture.url)
        let diff = try #require(try await repo.diff(path: "a.txt", side: .unstaged))
        let lines = diff.hunks[0].lines
        #expect(lines.map(\.kind) == [.context, .deletion, .addition])
        #expect(lines[1].missingTrailingNewline == false)
        #expect(lines[2].missingTrailingNewline == true)
        #expect(lines[2].text == "two")
    }
}
