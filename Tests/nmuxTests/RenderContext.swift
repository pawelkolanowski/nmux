import Foundation
import Testing
@testable import nmux
@testable import Terminal

// The Session's terminal on a pty of its own, in an app that finds its shaders in build/nmux.metallib, which `make`
// compiles before `swift test` runs.
@MainActor
private func oneTerminal() throws -> AppDelegate {
    let app = AppDelegate()
    let metallib = URL(fileURLWithPath: repositoryPath("build/nmux.metallib"))
    try #require(FileManager.default.fileExists(atPath: metallib.path),
                 "build/nmux.metallib is missing: run make first")
    app.metallib = metallib
    let font = Font(sfMono(14), points: 14, scale: 2)
    (app.font, app.fonts) = (font, [2: font])
    app.terminal = try TerminalView(argv: ["/bin/cat"], grid: Grid(cols: 80, rows: 24),
                                    context: app.sharedContext(), font: font)
    return app
}

@MainActor
struct RenderContextTests {
    @Test("the app makes the render context once") func theAppMakesTheRenderContextOnce() throws {
        let app = try oneTerminal()
        let context = try app.sharedContext()
        #expect(try app.sharedContext() === context)
        #expect(app.terminal?.context === context)
    }

    @Test("a scale change hands the terminal the font of the new scale")
    func aScaleChangeHandsTheTerminalTheFont() throws {
        let app = try oneTerminal()
        app.rescale(1)
        #expect(app.font?.scale == 1)
        #expect(app.terminal?.font === app.font)
    }

    @Test("a scale it had before gives the same font again") func aScaleItHadBeforeGivesTheSameFontAgain() throws {
        let app = try oneTerminal()
        let first = app.font
        app.rescale(1)
        app.rescale(2)
        #expect(app.font === first)
        #expect(app.terminal?.font === first)
    }
}
