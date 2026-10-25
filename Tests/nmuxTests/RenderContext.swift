import Foundation
import Testing
@testable import nmux
@testable import Terminal

// Two Sessions' terminals, each on a pty of its own, in an app that finds its shaders in build/nmux.metallib, which
// `make` compiles before `swift test` runs.
@MainActor
private func twoTerminals() throws -> AppDelegate {
    let app = AppDelegate()
    let metallib = URL(fileURLWithPath: repositoryPath("build/nmux.metallib"))
    try #require(FileManager.default.fileExists(atPath: metallib.path),
                 "build/nmux.metallib is missing: run make first")
    app.metallib = metallib
    let font = Font(sfMono(14), points: 14, scale: 2, thicken: false)
    (app.font, app.fonts) = (font, [2: font])
    for n in 0..<2 {
        let view = try TerminalView(argv: ["/bin/cat"], grid: Grid(cols: 80, rows: 24),
                                    context: app.sharedContext(), font: font)
        app.mirror.sessions.append(Session(SessionInfo(id: SessionID(number: n), name: "\(n)"), view))
    }
    return app
}

@MainActor
struct RenderContextTests {
    @Test("the app makes the render context once, for every terminal") func theAppMakesTheRenderContextOnce() throws {
        let app = try twoTerminals()
        let context = try app.sharedContext()
        #expect(try app.sharedContext() === context)
        #expect(app.sessions.allSatisfy { $0.view.context === context })
    }

    @Test("a scale change hands every terminal the font of the new scale")
    func aScaleChangeHandsEveryTerminalTheFont() throws {
        let app = try twoTerminals()
        app.rescale(1)
        #expect(app.font?.scale == 1)
        #expect(app.sessions.allSatisfy { $0.view.font === app.font })
    }

    @Test("a scale it had before gives the same font again") func aScaleItHadBeforeGivesTheSameFontAgain() throws {
        let app = try twoTerminals()
        let first = app.font
        app.rescale(1)
        app.rescale(2)
        #expect(app.font === first)
        #expect(app.sessions.allSatisfy { $0.view.font === first })
    }
}
