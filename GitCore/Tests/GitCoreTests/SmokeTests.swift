import Testing
@testable import GitCore

@Test func libgit2Links() {
    #expect(GitCoreVersion.libgit2.hasPrefix("1.9"))
}
