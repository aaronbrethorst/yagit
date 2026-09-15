import AppKit
import Foundation
import GitCore
import SwiftUI
import Testing
@testable import YAGit

/// Builds the demo repository used by the store tests and screenshots.
@MainActor
private func makeFixture() throws -> TestRepository {
    let fixture = try TestRepository()
    try fixture.git("config", "user.name", "Aaron Brethorst")
    try fixture.git("config", "user.email", "aaron@onebusaway.org")
    let lines = ["import UIKit", "", "final class TripViewController: UIViewController {"]
        + (1...29).map { "    // line \($0)" } + ["}", ""]
    try fixture.write("Sources/App/TripViewController.swift", lines.joined(separator: "\n"))
    try fixture.write("Sources/Models/Trip.swift", "struct Trip {\n    let id: String\n}\n")
    try fixture.write("Sources/App/Legacy.swift", "// legacy\n")
    try fixture.write("README.md", "# Demo\n")
    try fixture.commitAll("Initial commit")
    try fixture.addOrigin()
    try fixture.write("Sources/Models/Trip.swift", "struct Trip {\n    let id: String\n    let version = 2\n}\n")
    try fixture.commitAll("Bump model version")
    try fixture.git("checkout", "-q", "-b", "feature/trip-planner")

    let edited = try fixture.read("Sources/App/TripViewController.swift")
        .replacingOccurrences(of: "// line 2\n", with: "// line 2 changed\n    let planner = TripPlanner()\n")
        .replacingOccurrences(of: "// line 27\n", with: "// line 27 changed\n")
    try fixture.write("Sources/App/TripViewController.swift", edited)
    try fixture.write("Sources/App/TripPlanner.swift", "final class TripPlanner {\n    func plan() {}\n}\n")
    try fixture.remove("Sources/App/Legacy.swift")
    try fixture.write("Sources/Models/Stop.swift", "struct Stop {}\n")
    try fixture.git("add", "Sources/Models/Stop.swift")
    return fixture
}

@MainActor
@Suite(.serialized)
struct RepositoryStoreTests {
    @Test func loadSelectsFirstUnstagedFileAndReportsBothLists() async throws {
        let fixture = try makeFixture()
        let store = try RepositoryStore(url: fixture.url)
        await store.load()

        #expect(store.currentBranch == "feature/trip-planner")
        #expect(store.staged.map(\.path) == ["Sources/Models/Stop.swift"])
        #expect(store.unstaged.map(\.path) == [
            "Sources/App/Legacy.swift", "Sources/App/TripPlanner.swift", "Sources/App/TripViewController.swift",
        ])
        #expect(store.changedFileCount == 4)
        #expect(store.selectedChange?.path == "Sources/App/Legacy.swift")
        #expect(store.currentDiff?.status == .deleted)
        #expect(store.history.map(\.summary) == ["Bump model version", "Initial commit"])
        #expect(store.snapshot?.author == Author(name: "Aaron Brethorst", email: "aaron@onebusaway.org"))
    }

    @Test func stageHunkThenCommitLeavesTheOtherHunkUnstaged() async throws {
        let fixture = try makeFixture()
        let store = try RepositoryStore(url: fixture.url)
        await store.load()

        store.select(change: "unstaged:Sources/App/TripViewController.swift")
        try await settle()
        let diff = try #require(store.currentDiff)
        #expect(diff.hunks.count == 2)

        store.stageHunk(diff.hunks[0])
        try await settle()
        #expect(store.isOnBothSides("Sources/App/TripViewController.swift"))
        #expect(store.statusText == "Staged hunk 1 of TripViewController.swift")

        #expect(store.canCommit == false)
        store.commitMessage = "Wire up the planner"
        #expect(store.canCommit)
        store.commit()
        try await settle()

        #expect(store.statusText.hasPrefix("Committed "))
        #expect(store.statusText.hasSuffix(" to feature/trip-planner"))
        #expect(store.commitMessage.isEmpty)
        #expect(store.history.first?.summary == "Wire up the planner")
        #expect(store.staged.isEmpty)
        #expect(store.unstaged.map(\.path) == [
            "Sources/App/Legacy.swift", "Sources/App/TripPlanner.swift", "Sources/App/TripViewController.swift",
        ])
        #expect(store.selectedChange?.path == "Sources/App/Legacy.swift")
        #expect(store.snapshot?.current?.ahead == nil)  // new branch, not on origin
    }

    @Test func createBranchSwitchAndFetch() async throws {
        let fixture = try makeFixture()
        let store = try RepositoryStore(url: fixture.url)
        await store.load()

        #expect(await store.createBranch(named: "main") == "A branch named ‘main’ already exists.")
        #expect(await store.createBranch(named: "feature/other") == nil)
        #expect(store.currentBranch == "feature/other")
        #expect(store.branches.map(\.name) == ["feature/other", "feature/trip-planner", "main"])

        store.switchBranch(named: "main")
        try await settle()
        #expect(store.currentBranch == "main")
        #expect(store.statusText == "Switched to branch ‘main’")
        #expect(store.snapshot?.current?.ahead == 1)
        #expect(store.history.map(\.summary) == ["Bump model version", "Initial commit"])

        store.fetch()
        #expect(store.isFetching)
        #expect(store.statusText == "Fetching origin…")
        try await settle()
        #expect(store.isFetching == false)
        #expect(store.statusText == "Fetched origin — already up to date")
    }

    /// Renders the real window offscreen so the layout can be reviewed without screen recording.
    @Test func screenshots() async throws {
        let fixture = try makeFixture()
        let store = try RepositoryStore(url: fixture.url)
        await store.load()
        store.select(change: "unstaged:Sources/App/TripViewController.swift")
        try await settle()

        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["YAGIT_SCREENSHOT_DIR"]
                            ?? NSTemporaryDirectory()).appendingPathComponent("yagit-screens", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: RepositoryContent(store: store))
        window.orderFront(nil)

        UserDefaults.standard.set(DiffViewStyle.unified.rawValue, forKey: "diffViewStyle")
        try await settle()
        try snapshot(window, to: directory.appendingPathComponent("changes-unified.png"))

        UserDefaults.standard.set(DiffViewStyle.split.rawValue, forKey: "diffViewStyle")
        try await settle()
        try snapshot(window, to: directory.appendingPathComponent("changes-split.png"))

        store.mode = .history
        store.selectCommit(sha: store.history[0].sha)
        try await settle()
        try snapshot(window, to: directory.appendingPathComponent("history.png"))

        store.isPresentingNewBranch = true
        try await settle()
        try snapshot(window, to: directory.appendingPathComponent("new-branch.png"))
        store.isPresentingNewBranch = false
        try await settle()
        window.close()
        print("Screenshots written to \(directory.path)")
    }

    /// A commit touching many files wraps its chips onto many rows; that must not grow the window.
    @Test func manyFileCommitDoesNotOverflowWindow() async throws {
        let fixture = try makeFixture()
        for i in 1...40 {
            try fixture.write("Resources/locale\(i).lproj/Localizable.strings", "\"key\" = \"value \(i)\";\n")
        }
        try fixture.commitAll("Translate into forty locales")
        let store = try RepositoryStore(url: fixture.url)
        await store.load()
        store.mode = .history
        store.selectCommit(sha: store.history[0].sha)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        let hostingView = NSHostingView(rootView: RepositoryContent(store: store))
        window.contentView = hostingView
        window.orderFront(nil)
        try await settle()
        #expect(store.commitDetail?.files.count ?? 0 >= 40)

        #expect(hostingView.fittingSize.height <= 700)
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("yagit-screens", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try snapshot(window, to: directory.appendingPathComponent("history-many-files.png"))
        window.close()
    }

    /// A clean working tree shows only the empty state, not two empty section headers.
    @Test func cleanTreeScreenshot() async throws {
        let fixture = try TestRepository()
        try fixture.git("config", "user.name", "Aaron Brethorst")
        try fixture.git("config", "user.email", "aaron@onebusaway.org")
        try fixture.write("README.md", "# Demo\n")
        try fixture.commitAll("Initial commit")
        let store = try RepositoryStore(url: fixture.url)
        await store.load()

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: RepositoryContent(store: store))
        window.orderFront(nil)
        try await settle()
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("yagit-screens", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try snapshot(window, to: directory.appendingPathComponent("changes-clean.png"))
        window.close()
    }

    private func settle() async throws {
        for _ in 0..<6 {
            try await Task.sleep(for: .milliseconds(120))
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    private func snapshot(_ window: NSWindow, to url: URL) throws {
        let view = window.contentView!.superview!
        view.layoutSubtreeIfNeeded()
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try data.write(to: url)
    }
}


/// Diff rows live in one LazyVStack across every hunk, so their identities must be unique across hunks;
/// duplicates make SwiftUI leave the later hunks' rows blank.
struct DiffRowIdentityTests {
    private let hunks = (0..<3).map { index in
        DiffHunk(index: index, header: "@@ hunk \(index) @@", oldStart: 1, oldLines: 3, newStart: 1, newLines: 3,
                 lines: [
                     DiffLine(kind: .context, oldLineNumber: 1, newLineNumber: 1, text: "a"),
                     DiffLine(kind: .deletion, oldLineNumber: 2, newLineNumber: nil, text: "b"),
                     DiffLine(kind: .addition, oldLineNumber: nil, newLineNumber: 2, text: "c"),
                     DiffLine(kind: .context, oldLineNumber: 3, newLineNumber: 3, text: "d"),
                 ])
    }

    @Test func unifiedRowIDsAreUniqueAcrossHunks() {
        let ids = hunks.flatMap(unifiedRows(for:)).map(\.id)
        #expect(ids.count == 12)
        #expect(Set(ids).count == ids.count)
    }

    @Test func splitRowIDsAreUniqueAcrossHunks() {
        let ids = hunks.flatMap(splitRows(for:)).map(\.id)
        #expect(ids.count == 9)
        #expect(Set(ids).count == ids.count)
    }
}
