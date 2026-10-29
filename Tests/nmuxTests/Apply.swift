import Foundation
import Testing
@testable import nmux
@testable import Terminal

// The change set: what an apply redoes, from the old settings and colours to the new.
private let before = Applied(config: Config(), theme: sakura)
private func redone(_ text: String) -> [Change] {
    changes(from: before, to: Applied(config: parsed(text), theme: sakura))
}
private func paired(_ text: String) -> Applied {
    let config = parsed("theme = \(text)")
    return Applied(config: config,
                   theme: resolveTheme(ThemeSpec(config.theme), dark: false, folders: lookupFolders, read: themeFile))
}
private let relocated = { var theme = sakura; theme.source = "/elsewhere/Fuwafuwa Sakura"; return theme }()

struct ApplyTests {
    @Test("the first apply redoes everything") func theFirstApplyRedoesEverything() {
        #expect(changes(from: nil, to: before) == Change.allCases)
    }

    @Test("nothing changed redoes nothing") func nothingChangedRedoesNothing() {
        #expect(changes(from: before, to: before).isEmpty)
    }

    @Test("each font key on its own redoes the face") func eachFontKeyOnItsOwnRedoesThe() {
        #expect(redone("font-family = Menlo") == [.face])
        #expect(redone("font-size = 18") == [.face])
        #expect(redone("font-thicken = true") == [.face])
    }

    @Test("opacity and blur redo the opacity") func opacityAndBlurRedoTheOpacity() {
        #expect(redone("background-opacity = 0.5") == [.opacity])
        #expect(redone("background-blur = true") == [.opacity])
    }

    @Test("pill-width redoes the pills") func pillWidthRedoesThePills() {
        #expect(redone("pill-width = 200") == [.pills])
    }

    @Test("each input key on its own redoes the input",
          arguments: ["option-as-alt = left", "copy-on-select = true", "clipboard-write = deny",
                      "clipboard-read = allow"])
    func eachInputKeyRedoesTheInput(line: String) {
        #expect(redone(line) == [.input])
    }

    @Test("image-storage-limit redoes the images") func imageStorageLimitRedoesTheImages() {
        #expect(redone("image-storage-limit = 0") == [.images])
    }

    @Test("the theme key alone redoes nothing until its colours differ") func theThemeKeyAloneRedoesNothingUntilIts() {
        #expect(redone("theme = Nord").isEmpty)
    }

    @Test("a theme with other colours redoes the colours, before the face")
    func aThemeWithOtherColoursRedoesTheColours() {
        #expect(changes(from: before, to: Applied(config: parsed("font-size = 18"), theme: Theme(dark: false)))
            == [.colours, .face])
    }

    @Test("a pair whose current side did not change redoes nothing") func aPairWhoseCurrentSideDidNotChange() {
        #expect(changes(from: paired("light:Nord,dark:Dracula"), to: paired("light:Nord,dark:/any/where")).isEmpty)
    }

    @Test("the same colours from another file redo nothing") func theSameColoursFromAnotherFileRedoNothing() {
        #expect(changes(from: before, to: Applied(config: Config(), theme: relocated)).isEmpty)
    }

    @Test("the other appearance with the same colours redoes the colours, for the scheme report")
    func theOtherAppearanceWithTheSameColoursRedoes() {
        #expect(changes(from: Applied(config: Config(), theme: Theme(dark: false)),
                        to: Applied(config: Config(), theme: { var t = Theme(dark: false); t.dark = true; return t }()))
            == [.colours])
    }
}
