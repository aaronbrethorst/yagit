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
        #expect(store.history.map(\.commit.summary) == ["Bump model version", "Initial commit"])
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
        #expect(store.history.first?.commit.summary == "Wire up the planner")
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
        #expect(store.history.map(\.commit.summary) == ["Bump model version", "Initial commit"])

        try fixture.commitOnOrigin("Remote work")
        store.fetch()
        #expect(store.isFetching)
        #expect(store.statusText == "Fetching origin…")
        try await settle()
        #expect(store.isFetching == false)
        #expect(store.statusText == "Fetched origin — remote branches updated")
        #expect(store.history.map(\.commit.summary).contains("Remote work"))

        store.fetch()
        try await settle()
        #expect(store.statusText == "Fetched origin — already up to date")
    }

    @Test func selectingABranchOnlyHighlightsIt() async throws {
        let fixture = try makeFixture()
        let store = try RepositoryStore(url: fixture.url)
        await store.load()

        store.selectedBranchName = "main"
        try await settle()
        #expect(store.currentBranch == "feature/trip-planner")
        #expect(try fixture.git("branch", "--show-current").trimmingCharacters(in: .whitespacesAndNewlines)
            == "feature/trip-planner")
    }

    @Test func canMakeBranchActiveNeedsASelectedNonCurrentBranch() async throws {
        let fixture = try makeFixture()
        let store = try RepositoryStore(url: fixture.url)
        await store.load()

        #expect(store.canMakeBranchActive == false)
        store.selectedBranchName = "feature/trip-planner"
        #expect(store.canMakeBranchActive == false)
        store.selectedBranchName = "main"
        #expect(store.canMakeBranchActive)
    }

    @Test func makeSelectedBranchActiveSwitchesAndKeepsTheSelection() async throws {
        let fixture = try makeFixture()
        let store = try RepositoryStore(url: fixture.url)
        await store.load()

        store.selectedBranchName = "main"
        store.makeSelectedBranchActive()
        try await settle()
        #expect(store.currentBranch == "main")
        #expect(store.selectedBranchName == "main")
        #expect(store.canMakeBranchActive == false)
        #expect(store.statusText == "Switched to branch ‘main’")
    }

    @Test func branchSelectionClearsWhenTheBranchDisappears() async throws {
        let fixture = try makeFixture()
        try fixture.git("branch", "spike")
        let store = try RepositoryStore(url: fixture.url)
        await store.load()

        store.selectedBranchName = "spike"
        try fixture.git("branch", "-D", "spike")
        await store.refresh()
        #expect(store.selectedBranchName == nil)
    }

    @Test func commitSelectionSurvivesABranchSwitchAndClearsWhenItsCommitDisappears() async throws {
        let fixture = try makeFixture()
        let spike = try fixture.git("commit-tree", "HEAD^{tree}", "-p", "HEAD", "-m", "Spike")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try fixture.git("branch", "spike", spike)
        let store = try RepositoryStore(url: fixture.url)
        await store.load()
        #expect(store.history.map(\.commit.summary).contains("Spike"))

        store.mode = .history
        store.selectCommit(sha: spike)
        try await settle()
        #expect(store.commitDetail?.commit.sha == spike)

        store.switchBranch(named: "main")
        try await settle()
        #expect(store.currentBranch == "main")
        #expect(store.selectedCommitSHA == spike)
        #expect(store.commitDetail?.commit.sha == spike)

        try fixture.git("branch", "-D", "spike")
        await store.load()
        #expect(!store.history.contains { $0.commit.sha == spike })
        #expect(store.selectedCommitSHA == nil)
        #expect(store.commitDetail == nil)
        #expect(store.selectedCommitFile == nil)
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
        store.selectCommit(sha: store.history[0].commit.sha)
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

    /// A commit touching many files scrolls inside the Files column; that must not grow the window.
    @Test func manyFileCommitDoesNotOverflowWindow() async throws {
        let fixture = try makeFixture()
        for i in 1...40 {
            try fixture.write("Resources/locale\(i).lproj/Localizable.strings", "\"key\" = \"value \(i)\";\n")
        }
        try fixture.commitAll("Translate into forty locales")
        let store = try RepositoryStore(url: fixture.url)
        await store.load()
        store.mode = .history
        store.selectCommit(sha: store.history[0].commit.sha)

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

    /// HSplitView sizes its children to their ideal height, so a binary file's placeholder must not
    /// collapse the Files column and the detail pane to a strip in the middle of the window.
    @Test func binaryFileKeepsHistoryPanesFullHeight() async throws {
        let fixture = try makeFixture()
        try fixture.write("Sources/App/Icon.swift", "let icon = \"icon\"\n")
        let png = fixture.url.appendingPathComponent("Assets/icon.png")
        try FileManager.default.createDirectory(at: png.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D]).write(to: png)
        try fixture.commitAll("Add app icon")
        let store = try RepositoryStore(url: fixture.url)
        await store.load()
        store.mode = .history
        store.selectCommit(sha: store.history[0].commit.sha)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        let hostingView = NSHostingView(rootView: RepositoryContent(store: store))
        window.contentView = hostingView
        window.orderFront(nil)
        try await settle()
        store.selectedCommitFile = "Assets/icon.png"
        try await settle()
        #expect(store.selectedCommitDiff?.isBinary == true)

        let split = try #require(hostingView.descendants(of: NSSplitView.self).first { $0.arrangedSubviews.count == 2 })
        #expect(split.frame.height > 500)
        for pane in split.arrangedSubviews {
            #expect(abs(pane.frame.height - split.frame.height) < 1, "pane \(pane.frame) in split \(split.frame)")
        }
        window.close()
    }

    /// Space toggles the selected file and keeps it selected on its new side, so pressing Space
    /// again moves it straight back.
    @Test func toggleSelectedFileFollowsTheFileAcrossSides() async throws {
        let fixture = try makeFixture()
        let store = try RepositoryStore(url: fixture.url)
        await store.load()
        store.select(change: "unstaged:Sources/App/TripPlanner.swift")
        try await settle()

        store.toggleSelectedFile()
        try await settle()
        #expect(store.selectedChangeID == "staged:Sources/App/TripPlanner.swift")
        #expect(store.staged.map(\.path) == ["Sources/App/TripPlanner.swift", "Sources/Models/Stop.swift"])

        store.toggleSelectedFile()
        try await settle()
        #expect(store.selectedChangeID == "unstaged:Sources/App/TripPlanner.swift")
        #expect(store.staged.map(\.path) == ["Sources/Models/Stop.swift"])
    }

    /// The menu item carries a bare Space key equivalent, so it must be disabled whenever text
    /// is being typed, and come back when a click returns focus to the list.
    @Test func toggleFileStageIsUnavailableWhileTyping() async throws {
        let fixture = try makeFixture()
        let store = try RepositoryStore(url: fixture.url)
        await store.load()

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        let hostingView = NSHostingView(rootView: RepositoryContent(store: store))
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        try await settle()
        #expect(store.selectedChange != nil)
        #expect(store.canToggleSelectedFile, "on open")

        let editor = try #require(hostingView.descendants(of: NSTextView.self).first)
        window.makeFirstResponder(editor)
        try await settle()
        #expect(store.canToggleSelectedFile == false, "typing a commit message")

        // Clicking a row asks for the list back even though the store never left `.list`; that
        // must actually take focus away from the editor.
        store.requestFocus(.list)
        try await settle()
        #expect(store.canToggleSelectedFile, "clicked back into the list")
        #expect(!(window.firstResponder is NSTextView), "editor resigned")

        store.isPresentingNewBranch = true
        #expect(store.canToggleSelectedFile == false, "new-branch sheet")
        store.isPresentingNewBranch = false

        store.mode = .history
        try await settle()
        #expect(store.canToggleSelectedFile == false, "history mode")
        window.close()
    }

    /// A Space key event delivered to the window with the list focused stages the selected file.
    @Test func spaceInTheListStagesTheSelectedFile() async throws {
        let fixture = try makeFixture()
        let store = try RepositoryStore(url: fixture.url)
        await store.load()
        store.select(change: "unstaged:Sources/App/TripPlanner.swift")

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: RepositoryContent(store: store))
        window.makeKeyAndOrderFront(nil)
        try await settle()
        #expect(window.firstResponder is NSTableView)

        let space = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                  windowNumber: window.windowNumber, context: nil,
                                                  characters: " ", charactersIgnoringModifiers: " ",
                                                  isARepeat: false, keyCode: 49))
        window.sendEvent(space)
        try await settle()
        #expect(store.selectedChangeID == "staged:Sources/App/TripPlanner.swift")
        #expect(store.staged.map(\.path).contains("Sources/App/TripPlanner.swift"))
        window.close()
    }

    /// The shortcut is discoverable: a Changes menu item bound to a bare Space.
    @Test func changesMenuOffersToggleFileStageOnSpace() throws {
        let menu = try #require(NSApp.mainMenu?.items.first { $0.title == "Changes" }?.submenu)
        let item = try #require(menu.items.first { ["Stage File", "Unstage File"].contains($0.title) })
        #expect(item.keyEquivalent == " ")
        #expect(item.keyEquivalentModifierMask.isEmpty)
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

private extension NSView {
    func descendants<T: NSView>(of type: T.Type) -> [T] {
        subviews.flatMap { (($0 as? T).map { [$0] } ?? []) + $0.descendants(of: type) }
    }
}
