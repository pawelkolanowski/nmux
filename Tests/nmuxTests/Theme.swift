import Foundation
import Testing
@testable import nmux
@testable import Terminal

// Themes: the parser, the spec of `theme`, the lookup and the overlay on the fallback.
private let sixColours = parseTheme("""
    background = #FBDFEF
    foreground = 57466d
    cursor-color = #CF76A4
    cursor-text = #FBDFEF
    selection-background = "#F5C4DD"
    selection-foreground = #49385F
    """)
private func sides(_ text: String) -> String {
    let s = ThemeSpec(text)
    return "\(s.light ?? "-") \(s.dark ?? "-") \(s.pair)"
}
private func found(_ name: String) -> String? { lookUpTheme(name, folders: lookupFolders, read: themeFile)?.path }
private let nowhere = resolveTheme(ThemeSpec("nope"), dark: false, folders: lookupFolders, read: themeFile)
private let pairSpec = ThemeSpec("light:Nord,dark:Dracula")
private let short = Theme(parseTheme("background = #fbdfef\npalette = 0=#57466d\npalette = 200=#123456"), dark: true)
private func accent(_ text: String) -> UInt32 { Theme(parseTheme(text), dark: false).accent.hex }
// Every theme the app bundles: iTerm2-Color-Schemes' and nmux's own.
private let bundled = ["vendor/iTerm2-Color-Schemes/ghostty", "Resources/themes"].flatMap { folder in
    ((try? FileManager.default.contentsOfDirectory(atPath: repositoryPath(folder))) ?? []).map { "\(folder)/\($0)" }
}

struct ThemeTests {
    @Test("a theme reads its six colours, with or without #") func aThemeReadsItsSixColoursWithOr() {
        #expect(sixColours == ThemeColors(
            background: RGB(0xfbdfef), foreground: RGB(0x57466d), cursorColor: RGB(0xcf76a4), cursorText: RGB(0xfbdfef),
            selectionBackground: RGB(0xf5c4dd), selectionForeground: RGB(0x49385f)))
    }

    @Test("cursor-text reaches the terminal's colours") func cursorTextReachesTheTerminalsColours() {
        #expect(Theme(parseTheme("cursor-text = #ffffff"), dark: false).terminal.cursorText == RGB(0xffffff))
    }

    @Test("a theme reads palette 0 and 255 and skips a bad index") func aThemeReadsPalette0And255And() {
        #expect(parseTheme(
            "palette = 0=#010203\npalette = 255=040506\npalette = 256=#070809\npalette = x=#0a0b0c"
        ).palette == [0: RGB(0x010203), 255: RGB(0x040506)])
    }

    @Test("a theme skips a font line, a comment and a bad colour") func aThemeSkipsAFontLineAComment() {
        #expect(parseTheme("font-family = Menlo\n# background = #111111\nbackground = #12345\nforeground = red")
            == ThemeColors())
    }

    @Test("the last line of a key or an index wins") func theLastLineOfAKeyOrAn() {
        #expect(parseTheme("background = #111111\nbackground = #222222\npalette = 3=#333333\npalette = 3=#444444")
            == ThemeColors(background: RGB(0x222222), palette: [3: RGB(0x444444)]))
    }

    @Test("a single theme names both appearances") func aSingleThemeNamesBothAppearances() {
        #expect(sides(" Dracula ") == "Dracula Dracula false")
    }

    @Test("a pair names each side, spaces trimmed") func aPairNamesEachSideSpacesTrimmed() {
        #expect(sides("light: Sakura , dark:Dracula") == "Sakura Dracula true")
        #expect(sides(" light:foo,  dark : bar  ") == "foo bar true")
    }

    @Test("a pair missing a side gives that side the fallback") func aPairMissingASideGivesThatSide() {
        #expect(sides("dark:Dracula") == "- Dracula true")
        #expect(sides("light:Sakura,dark:") == "Sakura - true")
    }

    @Test("the themes folder sits beside the config") func theThemesFolderSitsBesideTheConfig() {
        #expect(lookupFolders == ["/u/nmux/themes", "/b"])
        #expect(themeFolders(ConfigLocation(xdg: nil, home: "/h"), bundle: "/b") == ["/h/.config/nmux/themes", "/b"])
    }

    @Test("a user theme shadows a bundled one, and the bundle comes next, past a file that is not UTF-8")
    func aUserThemeShadowsABundledOneAnd() {
        #expect(found("Dracula") == "/u/nmux/themes/Dracula")
        #expect(found("Nord") == "/b/Nord")
    }

    @Test("an absolute path is read as it is") func anAbsolutePathIsReadAsItIs() {
        #expect(found("/any/where") == "/any/where")
    }

    @Test("a relative path with / or .. finds nothing") func aRelativePathWithOrFindsNothing() {
        #expect(found("x/Nord") == nil)
        #expect(found("../b/Nord") == nil)
        #expect(found("..") == nil)
    }

    @Test("a theme found nowhere is the fallback") func aThemeFoundNowhereIsTheFallback() {
        #expect(nowhere == Theme(dark: false))
        #expect(nowhere.source == nil)
        #expect(nowhere.background == RGB(0xffffff))
        #expect(nowhere.foreground == RGB(0x000000))
    }

    @Test("the dark fallback is white on black") func theDarkFallbackIsWhiteOnBlack() {
        #expect(Theme(dark: true).background == RGB(0x000000))
        #expect(Theme(dark: true).foreground == RGB(0xffffff))
    }

    @Test("a pair resolves the side for the appearance") func aPairResolvesTheSideForTheAppearance() {
        #expect(resolveTheme(pairSpec, dark: false, folders: lookupFolders, read: themeFile).source == "/b/Nord")
        #expect(resolveTheme(pairSpec, dark: true, folders: lookupFolders, read: themeFile).source
            == "/u/nmux/themes/Dracula")
    }

    @Test("a theme keeps the fallback's colours it leaves out, palette 16 to 255 xterm's")
    func aThemeKeepsTheFallbacksColoursItLeaves() {
        #expect(short.foreground == RGB(0xffffff))
        #expect(short.palette[0] == RGB(0x57466d))
        #expect(short.palette[200] == RGB(0x123456))
        #expect(short.palette.count == 256)
        #expect((16..<256).filter { $0 != 200 }.allSatisfy { short.palette[$0] == fallbackPalette[$0] })
    }

    @Test("cursor-color left out takes the foreground and cursor-text the background in force")
    func cursorColorLeftOutTakesTheForegroundAndCursorTextTheBackground() {
        #expect(short.cursorColor == short.foreground)
        #expect(short.terminal.cursorText == nil)
    }

    @Test("selection colours left out stay unset") func selectionColoursLeftOutStayUnset() {
        #expect(short.selectionBackground == nil)
        #expect(short.selectionForeground == nil)
    }

    @Test("the accent is the cursor colour when it differs from the foreground")
    func theAccentIsTheCursorColourWhenIt() {
        #expect(accent("foreground = #111111\ncursor-color = #222222") == 0x222222)
    }

    @Test("the accent is palette 5 when the cursor is the foreground or unset")
    func theAccentIsPalette5WhenTheCursor() {
        #expect(accent("foreground = #111111\ncursor-color = #111111\npalette = 5=#555555") == 0x555555)
        #expect(accent("palette = 5=#555555") == 0x555555)
    }

    @Test("the red is palette 1 when the theme sets it, else the accent") func theRedIsPalette1WhenTheTheme() {
        #expect(Theme(parseTheme("palette = 1=#aa0000\ncursor-color = #222222"), dark: false).red == RGB(0xaa0000))
        #expect(Theme(parseTheme("cursor-color = #222222"), dark: false).red == RGB(0x222222))
    }

    @Test("each bundled theme sets a background and a foreground")
    func eachBundledThemeSetsABackgroundAndAForeground() {
        let unreadable = bundled.filter { path in
            let colors = (try? String(contentsOfFile: repositoryPath(path), encoding: .utf8)).map(parseTheme)
            return colors?.background == nil || colors?.foreground == nil
        }
        #expect(bundled.count > 800)
        #expect(unreadable == [])
    }

    @Test("Fuwafuwa Sakura is #57466D on #FBDFEF, its accent the cursor and its red palette 1")
    func fuwafuwaSakuraIs57466dOnFbdfefItsAccent() {
        #expect(sakura.background == RGB(0xfbdfef))
        #expect(sakura.foreground == RGB(0x57466d))
        #expect(sakura.accent == RGB(0xcf76a4))
        #expect(sakura.red == RGB(0xb96b7b))
    }
}
