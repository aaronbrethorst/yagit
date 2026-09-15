import libgit2

public enum GitCoreVersion {
    public static var libgit2: String {
        var major: Int32 = 0, minor: Int32 = 0, patch: Int32 = 0
        git_libgit2_version(&major, &minor, &patch)
        return "\(major).\(minor).\(patch)"
    }
}
