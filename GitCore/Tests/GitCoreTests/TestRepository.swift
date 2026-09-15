import Foundation

/// A throwaway repository built with the system `git`, used as an independent oracle.
final class TestRepository {
    let url: URL
    private(set) var remoteURL: URL?

    init() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitCoreTests-\(UUID().uuidString)", isDirectory: true)
        url = base.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try git("init", "-q", "-b", "main")
        try git("config", "user.name", "Test Author")
        try git("config", "user.email", "test@example.com")
        try git("config", "commit.gpgsign", "false")
    }

    deinit {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    // MARK: Fixtures

    func write(_ path: String, _ contents: String) throws {
        let file = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: file, atomically: true, encoding: .utf8)
    }

    func read(_ path: String) throws -> String {
        try String(contentsOf: url.appendingPathComponent(path), encoding: .utf8)
    }

    func remove(_ path: String) throws {
        try FileManager.default.removeItem(at: url.appendingPathComponent(path))
    }

    func commitAll(_ message: String) throws {
        try git("add", "-A")
        try git("commit", "-q", "-m", message)
    }

    /// Adds a bare `origin` remote, pushes `main` and sets it as upstream.
    func addOrigin() throws {
        let remote = url.deletingLastPathComponent().appendingPathComponent("origin.git")
        try run("/usr/bin/git", ["init", "-q", "--bare", "-b", "main", remote.path], in: url.deletingLastPathComponent())
        try git("remote", "add", "origin", remote.path)
        try git("push", "-q", "-u", "origin", "main")
        remoteURL = remote
    }

    /// Advances `origin/main` from a separate clone so a fetch has something to pull.
    func commitOnOrigin(_ message: String) throws {
        guard let remoteURL else { preconditionFailure("call addOrigin() first") }
        let clone = url.deletingLastPathComponent().appendingPathComponent("clone-\(UUID().uuidString)")
        try run("/usr/bin/git", ["clone", "-q", remoteURL.path, clone.path], in: url.deletingLastPathComponent())
        try run("/usr/bin/git", ["-c", "user.name=Other", "-c", "user.email=other@example.com",
                                 "commit", "-q", "--allow-empty", "-m", message], in: clone)
        try run("/usr/bin/git", ["push", "-q", "origin", "main"], in: clone)
    }

    // MARK: Oracle

    @discardableResult
    func git(_ arguments: String...) throws -> String {
        try run("/usr/bin/git", arguments, in: url)
    }

    @discardableResult
    private func run(_ executable: String, _ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_CONFIG_NOSYSTEM"] = "1"
        environment["HOME"] = directory.deletingLastPathComponent().path
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw TestRepositoryError.commandFailed("\(executable) \(arguments.joined(separator: " ")): \(text)")
        }
        return text
    }
}

enum TestRepositoryError: Error {
    case commandFailed(String)
}
