import AppKit
import Foundation
import GitCore
import SwiftUI
import Testing
@testable import YAGit

/// `store.focusedPane` must drive the window's real first responder, otherwise the arrow keys
/// keep acting on whichever list the Tab key last visited.
@MainActor
@Suite(.serialized)
struct PaneFocusTests {
    // Column widths are the only stable way to tell the three SwiftUIOutlineListViews apart.
    private let sidebarWidth = 212
    private let changesListWidth = 326
    private let commitFilesWidth = 240

    @Test func focusedPaneDrivesTheFirstResponder() async throws {
        let store = try await makeStore()
        let window = makeWindow(store)
        try await settle(window)

        // The list column starts focused, so the arrow keys work the moment the window opens.
        #expect(store.focusedPane == .list)
        #expect(focusedTableWidth(window) == changesListWidth)

        store.focusedPane = .sidebar
        try await settle(window)
        #expect(focusedTableWidth(window) == sidebarWidth)

        store.focusedPane = .list
        try await settle(window)
        #expect(focusedTableWidth(window) == changesListWidth)

        // History adds the commit-files column; focus must be able to reach it.
        store.mode = .history
        try await settle(window)
        store.selectCommit(sha: store.history[0].commit.sha)
        try await settle(window)
        store.focusedPane = .commitFiles
        try await settle(window)
        #expect(focusedTableWidth(window) == commitFilesWidth)

        window.close()
    }

    /// Switching modes rebuilds the content column, so focus must survive the rebuild rather than
    /// being stranded on a view that is gone.
    @Test func focusSurvivesAModeSwitch() async throws {
        let store = try await makeStore()
        let window = makeWindow(store)
        try await settle(window)

        store.mode = .history
        try await settle(window)
        store.selectCommit(sha: store.history[0].commit.sha)
        try await settle(window)
        store.focusedPane = .commitFiles
        try await settle(window)

        // Leaving History retires the commit-files column, so focus falls back to the list.
        store.mode = .changes
        try await settle(window)
        #expect(store.focusedPane == .list)
        #expect(focusedTableWidth(window) == changesListWidth)

        // A pane that survives the switch keeps focus, so clicking a sidebar row to change
        // modes leaves the arrow keys in the sidebar.
        store.focusedPane = .sidebar
        store.mode = .history
        try await settle(window)
        #expect(store.focusedPane == .sidebar)
        #expect(focusedTableWidth(window) == sidebarWidth)

        window.close()
    }

    /// At launch the window opens before the first snapshot loads, so the list isn't in the tree
    /// yet. Focus must still land on it once it arrives, not on the commit message editor.
    @Test func launchFocusesTheListNotTheCommitMessage() async throws {
        let store = try await makeStore(loaded: false)
        let window = makeWindow(store)
        try await settle(window)
        #expect(!(window.firstResponder is NSTextView))

        await store.load()
        try await settle(window)
        #expect(!(window.firstResponder is NSTextView))
        #expect(!store.isEditingCommitMessage)
        #expect(focusedTableWidth(window) == changesListWidth)

        window.close()
    }

    // MARK: - Helpers

    private func makeStore(loaded: Bool = true) async throws -> RepositoryStore {
        let fixture = try TestRepository()
        try fixture.git("config", "user.name", "Aaron Brethorst")
        try fixture.git("config", "user.email", "aaron@onebusaway.org")
        try fixture.write("README.md", "# Demo\n")
        try fixture.commitAll("Initial commit")
        try fixture.write("Second.swift", "let y = 2\n")
        try fixture.commitAll("Second commit")
        try fixture.write("README.md", "# Demo changed\n")
        try fixture.write("Other.swift", "let x = 1\n")
        let store = try RepositoryStore(url: fixture.url)
        if loaded { await store.load() }
        return store
    }

    private func makeWindow(_ store: RepositoryStore) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: RepositoryContent(store: store))
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func focusedTableWidth(_ window: NSWindow) -> Int? {
        guard let table = window.firstResponder as? NSTableView else { return nil }
        return Int(table.frame.width)
    }

    /// Other suites run in parallel and order their own windows front; SwiftUI refuses to move
    /// focus in a window that is not key, so reclaim it on every pass.
    private func settle(_ window: NSWindow) async throws {
        for _ in 0..<8 {
            if !window.isKeyWindow { window.makeKeyAndOrderFront(nil) }
            try await Task.sleep(for: .milliseconds(120))
        }
    }
}
