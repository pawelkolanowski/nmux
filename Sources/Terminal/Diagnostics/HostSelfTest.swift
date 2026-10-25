#if NMUX_SELFTEST
import GhosttyVt

/// The version of libghostty-vt nmux was built with, `major.minor.patch`.
public var libghosttyVersion: String {
    [GHOSTTY_BUILD_INFO_VERSION_MAJOR, GHOSTTY_BUILD_INFO_VERSION_MINOR, GHOSTTY_BUILD_INFO_VERSION_PATCH].map { info in
        var part = 0
        ghostty_build_info(info, &part)
        return String(part)
    }.joined(separator: ".")
}
#endif
