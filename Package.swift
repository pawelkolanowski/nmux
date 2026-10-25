// swift-tools-version:6.2
// nmux's app binary; `make` builds it through SwiftPM and assembles nmux.app around it.
import PackageDescription

let package = Package(
    name: "nmux",
    platforms: [.macOS(.v26)], // Metal 4, which nmux's renderer needs
    targets: [
        // The app runs on the main actor; what runs off it, its tmux and process readers and its pure logic, says
        // `nonisolated`.
        .executableTarget(name: "nmux", dependencies: ["Terminal"], swiftSettings: [.defaultIsolation(MainActor.self)]),
        // The terminal: the pty, the VT host, input, the clipboard and the view that draws it; it knows no menu, window
        // or bundle.
        // `make` compiles the shaders.
        .target(name: "Terminal", dependencies: ["GhosttyVt"], exclude: ["Render/Shaders.metal"]),
        .binaryTarget(name: "GhosttyVt", path: "vendor/ghostty-vt.xcframework.zip"),
        // The lock's rules, for the tests; `make` builds check-lock from the same file with swiftc, before SwiftPM
        // unpacks the zip.
        .target(name: "Lock", path: "Tools/lock", exclude: ["main.swift"]),
        .testTarget(name: "nmuxTests", dependencies: ["nmux", "Terminal", "Lock", "GhosttyVt"]),
    ]
)
