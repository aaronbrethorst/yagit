import Foundation
import Testing
@testable import GitCore

/// Manual probe: `YAGIT_TIMING_REPO=/path/to/repo swift test --filter HistoryTimingTests`.
@Suite struct HistoryTimingTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["YAGIT_TIMING_REPO"] != nil))
    func historyOnARealRepository() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["YAGIT_TIMING_REPO"])
        let repo = try GitRepository(url: URL(fileURLWithPath: path))
        var entries: [HistoryEntry] = []
        let elapsed = try await ContinuousClock().measure { entries = try await repo.history() }
        let lanes = (entries.map(\.graph.column).max() ?? -1) + 1
        print("history() on \(path): \(entries.count) entries, \(lanes) lanes, \(elapsed)")
    }
}
