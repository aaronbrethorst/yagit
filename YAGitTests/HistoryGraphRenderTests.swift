import AppKit
import Foundation
import GitCore
import SwiftUI
import Testing
@testable import YAGit

/// The design mockup's history, newest first.
private let mockupSummaries = [
    "Cache trip details between launches",
    "Update Norwegian localization",
    "Sort arrivals by scheduled time",
    "Fix stale arrival predictions",
    "Raise the minimum deployment target to iOS 17",
    "Cut the 2.9 release branch",
    "Merge pull request #418 from feature/trip-planner",
    "Add the TripCache actor",
    "Sketch the trip planner panel",
    "Merge pull request #412 from fix/bookmarks",
    "Add a regression test for empty bookmarks",
    "Guard the bookmarks reload against a nil session",
    "Extract OBAKitCore into its own package",
    "Initial 2.7 release",
]

/// Rebuilds the mockup's repository with one-minute-apart dates, so the walk order is fixed.
@MainActor
private func makeMockupFixture() throws -> TestRepository {
    let fixture = try TestRepository()
    try fixture.git("config", "user.name", "Aaron Brethorst")
    try fixture.git("config", "user.email", "aaron@onebusaway.org")
    var minute = 0
    func nextDate() -> Date {
        defer { minute += 1 }
        return Date(timeIntervalSince1970: 1_788_000_000 + Double(minute) * 60)
    }
    func commit(_ message: String) throws {
        try fixture.git(date: nextDate(), "commit", "-q", "--allow-empty", "-m", message)
    }
    func merge(_ branch: String, _ message: String) throws {
        try fixture.git(date: nextDate(), "merge", "-q", "--no-ff", "-m", message, branch)
        try fixture.git("branch", "-D", branch)
    }

    try commit("Initial 2.7 release")
    try fixture.git("tag", "v2.7.0")
    try commit("Extract OBAKitCore into its own package")
    try fixture.git("checkout", "-q", "-b", "fix/bookmarks")
    try commit("Guard the bookmarks reload against a nil session")
    try commit("Add a regression test for empty bookmarks")
    try fixture.git("checkout", "-q", "main")
    try merge("fix/bookmarks", "Merge pull request #412 from fix/bookmarks")
    try fixture.git("tag", "v2.7.1")
    try fixture.git("checkout", "-q", "-b", "feature/trip-planner-panel")
    try commit("Sketch the trip planner panel")
    try commit("Add the TripCache actor")
    try fixture.git("checkout", "-q", "main")
    try merge("feature/trip-planner-panel", "Merge pull request #418 from feature/trip-planner")
    try fixture.git("checkout", "-q", "-b", "release/2.9")
    try commit("Cut the 2.9 release branch")
    try fixture.git("checkout", "-q", "main")
    try commit("Raise the minimum deployment target to iOS 17")
    try fixture.git("checkout", "-q", "release/2.9")
    try commit("Fix stale arrival predictions")
    try fixture.git("tag", "v2.8.1")
    try fixture.git("checkout", "-q", "-b", "fix/arrival-sort", "main")
    try commit("Sort arrivals by scheduled time")
    try fixture.git("checkout", "-q", "main")
    try commit("Update Norwegian localization")
    try fixture.git("update-ref", "refs/remotes/origin/main", "HEAD")
    try fixture.git("checkout", "-q", "-b", "feature/trip-planner")
    try commit("Cache trip details between launches")
    // Not in the mockup: four refs on the root commit exercise the "+N" overflow badge.
    try fixture.git("branch", "archive/2.7", "v2.7.0")
    try fixture.git("tag", "v2.7.0-rc1", "v2.7.0")
    try fixture.git("tag", "v2.7.0-rc2", "v2.7.0")
    return fixture
}

@MainActor
@Suite(.serialized)
struct HistoryGraphRenderTests {
    private let listWidth = 326

    @Test(arguments: [false, true])
    func mainlineLaneIsContinuousAcrossRows(dark: Bool) async throws {
        let fixture = try makeMockupFixture()
        let store = try RepositoryStore(url: fixture.url)
        await store.load()
        #expect(store.history.map(\.commit.summary) == mockupSummaries)
        #expect(store.history.map(\.graph.column) == [1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1, 1, 0, 0])
        #expect(store.history.last?.refs.count == 4)
        store.mode = .history

        let window = makeWindow(store, dark: dark)
        try await settle(window)
        let (view, rep) = try snapshot(window, named: dark ? "history-graph-dark" : "history-graph-light")

        let table = try #require(view.descendants(of: NSTableView.self).first { Int($0.frame.width) == listWidth })
        let rows = (0..<table.numberOfRows).map { table.rect(ofRow: $0) }.filter { abs($0.height - 34) < 0.5 }
        try #require(rows.count == 14, "commit rows: \(rows)")
        func sample(_ x: CGFloat, _ y: CGFloat) -> NSColor? {
            color(in: rep, of: view, at: table.convert(NSPoint(x: x, y: y), to: view))
        }

        // Row 1 is `main`, a mainline commit: its dot is the first run of ink from the row's leading edge.
        let ink = stride(from: rows[1].minX, to: rows[1].maxX, by: 0.5).filter { isLaneInk(sample($0, rows[1].midY)) }
        let first = try #require(ink.first)
        let laneX = (first + ink.prefix { $0 - first <= 9 }.last!) / 2

        // Lane 0 must have ink on both sides of every boundary from row 1 down to the root.
        for index in 1..<13 {
            for y in [rows[index].maxY - 1, rows[index + 1].minY + 1] {
                let pixel = sample(laneX, y)
                #expect(isLaneInk(pixel), "lane 0 broken below row \(index) at y=\(y): \(String(describing: pixel))")
            }
        }
        window.close()
    }

    @Test func selectedMergeRowRendersFocusedAndUnfocused() async throws {
        let fixture = try makeMockupFixture()
        let store = try RepositoryStore(url: fixture.url)
        await store.load()
        store.mode = .history
        let window = makeWindow(store, dark: false)
        try await settle(window)

        let merge = store.history[6].commit.sha
        store.selectCommit(sha: merge)
        store.requestFocus(.list)
        try await settle(window)
        let (_, focused) = try snapshot(window, named: "history-graph-selected-focused")

        store.focusedPane = .commitFiles
        try await settle(window)
        #expect(store.selectedCommitSHA == merge)
        let (_, unfocused) = try snapshot(window, named: "history-graph-selected-unfocused")
        // Both renders came out gray and identical before the harness mirrored row emphasis.
        #expect(focused.tiffRepresentation != unfocused.tiffRepresentation, "focused and unfocused selection render the same")
        window.close()
    }

    /// The History column as narrow as the split view squeezes it at the window's minimum width.
    @Test func narrowColumnRendersForInspection() async throws {
        let fixture = try makeMockupFixture()
        let store = try RepositoryStore(url: fixture.url)
        await store.load()
        store.mode = .history
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 231, height: 600),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: HistoryListHost(store: store))
        window.makeKeyAndOrderFront(nil)
        try await settle(window)
        _ = try snapshot(window, named: "history-graph-narrow")
        window.close()
    }

    // MARK: - Helpers

    private func makeWindow(_ store: RepositoryStore, dark: Bool) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = NSHostingView(rootView: RepositoryContent(store: store))
        window.makeKeyAndOrderFront(nil)
        return window
    }

    /// Other suites run in parallel and order their own windows front; reclaim key status every pass so
    /// focus still moves, and re-mirror row emphasis so the selection renders with the right prominence.
    private func settle(_ window: NSWindow) async throws {
        for _ in 0..<8 {
            if !window.isKeyWindow { window.makeKeyAndOrderFront(nil) }
            try await Task.sleep(for: .milliseconds(120))
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            emphasizeFirstResponderList(window)
        }
    }

    /// The test host is rarely the active app, so AppKit never gives its window key appearance and every
    /// selection renders gray. Mirror what AppKit does for a key window: only the first-responder list's
    /// rows are emphasized, which is what gives the selected row `.increased` background prominence.
    private func emphasizeFirstResponderList(_ window: NSWindow) {
        let focused = window.firstResponder as? NSTableView
        for table in window.contentView!.superview!.descendants(of: NSTableView.self) {
            table.enumerateAvailableRowViews { rowView, _ in rowView.isEmphasized = table === focused }
        }
    }

    private func snapshot(_ window: NSWindow, named name: String) throws -> (NSView, NSBitmapImageRep) {
        let view = window.contentView!.superview!
        view.layoutSubtreeIfNeeded()
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("yagit-screens", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try #require(rep.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("\(name).png"))
        return (view, rep)
    }

    private func color(in rep: NSBitmapImageRep, of view: NSView, at point: NSPoint) -> NSColor? {
        let scale = CGFloat(rep.pixelsWide) / view.bounds.width
        let y = view.isFlipped ? point.y : view.bounds.height - point.y
        return rep.colorAt(x: Int(point.x * scale), y: Int(y * scale))
    }

    /// Lane colors are saturated; list backgrounds (white, near-black, gray) are not.
    private func isLaneInk(_ color: NSColor?) -> Bool {
        guard let color = color?.usingColorSpace(.sRGB) else { return false }
        return color.saturationComponent > 0.35 && color.brightnessComponent > 0.3
    }
}

/// Hosts the History list on its own, with the focus binding it needs.
private struct HistoryListHost: View {
    let store: RepositoryStore
    @FocusState private var pane: RepositoryStore.Pane?

    var body: some View {
        HistoryList(store: store, focus: $pane)
    }
}

private extension NSView {
    func descendants<T: NSView>(of type: T.Type) -> [T] {
        subviews.flatMap { (($0 as? T).map { [$0] } ?? []) + $0.descendants(of: type) }
    }
}
