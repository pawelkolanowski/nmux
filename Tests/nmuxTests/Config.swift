import Foundation
import Testing
@testable import nmux
@testable import Terminal

// The config: Ghostty's syntax, eleven keys with their defaults, and every skipped line with its number and reason.
private func problems(_ text: String) -> [ConfigProblem] { parseConfig(text).1 }
private func reasons(_ text: String) -> [String] { problems(text).map(\.reason) }
private let mixed = "pill-width = 200\nfont-szie = 16\nstray\n# c\npill-width = 900\nfont-size = 16"
private let one = configCard([
    ConfigProblem(line: 7, text: "pill-width = 900", reason: "expects a number from 60 to 400"),
]) { _ in true }
private let nine = configCard((1...9).map { ConfigProblem(line: $0, text: "x", reason: "no '='") }) { $0.count <= 12 }

struct ConfigTests {
    @Test("an empty text gives every default and no problem") func anEmptyTextGivesEveryDefaultAndNo() {
        #expect(parseConfig("") == (Config(), []))
    }

    @Test("a missing file gives every default") func aMissingFileGivesEveryDefault() {
        #expect(readConfig(nil).0 == Config())
        #expect(readConfig(nil).1.isEmpty)
    }

    @Test("a file that is not UTF-8 is one problem on line 0 and every default") func aFileThatIsNotUtf8Is() {
        #expect(readConfig(Data([0x66, 0xff, 0xfe])).0 == Config())
        #expect(readConfig(Data([0x66, 0xff, 0xfe])).1 == [ConfigProblem(line: 0, text: "", reason: "not UTF-8")])
    }

    @Test("a file that exists but cannot be read is one problem on line 0") func aFileThatExistsButCannotBeRead() {
        #expect(readConfig(nil, exists: true).1 == [ConfigProblem(line: 0, text: "", reason: "cannot read")])
    }

    @Test("a no-break space stays in a value, as Ghostty trims only spaces and tabs")
    func aNoBreakSpaceStaysInAValue() {
        #expect(parsed("theme = x\u{a0}").theme == "x\u{a0}")
    }

    @Test("the defaults in the table's order") func theDefaultsInTheTablesOrder() {
        #expect(configLines(Config()) == [
            "theme=Fuwafuwa Sakura",
            "font-family=SF Mono",
            "font-size=14",
            "font-thicken=false",
            "option-as-alt=false",
            "pill-width=136",
            "background-opacity=1",
            "background-blur=0",
            "copy-on-select=false",
            "clipboard-write=allow",
            "clipboard-read=ask",
        ])
    }

    @Test("the Config and the themes are XDG_CONFIG_HOME's when set") func theConfigAndTheThemesAreXdgConfigHomes() {
        let location = ConfigLocation(xdg: "/x", home: "/h")
        #expect(location.config == "/x/nmux/config")
        #expect(location.themes == "/x/nmux/themes")
        #expect(location.fromXDG)
    }

    @Test("an unset or empty XDG_CONFIG_HOME gives ~/.config", arguments: [nil, ""] as [String?])
    func anUnsetOrEmptyXdgConfigHomeGives(xdg: String?) {
        let location = ConfigLocation(xdg: xdg, home: "/h")
        #expect(location.config == "/h/.config/nmux/config")
        #expect(!location.fromXDG)
    }

    @Test("pill-width is read and tab-width is an unknown key",
          arguments: [("pill-width = 200", nil), ("tab-width = 200", "unknown key")])
    func pillWidthIsReadAndTabWidthIsUnknown(line: String, reason: String?) {
        let (config, problems) = parseConfig(line)
        #expect(problems.first?.reason == reason)
        #expect(config.pillWidth == (reason == nil ? 200 : 136))
    }

    @Test("the last line of a key wins") func theLastLineOfAKeyWins() {
        #expect(parsed("pill-width = 100\npill-width = 200").pillWidth == 200)
    }

    @Test("a bad last line keeps the earlier good one") func aBadLastLineKeepsTheEarlierGood() {
        #expect(parsed("pill-width = 100\npill-width = 900").pillWidth == 100)
    }

    @Test("comments, blank lines and spaces are skipped") func commentsBlankLinesAndSpacesAreSkipped() {
        #expect(parseConfig("# a comment\n\n   \t\n  # indented\n\tfont-size\t=  16  \r\n")
            == (Config(fontSize: 16), []))
    }

    @Test("a value in double quotes loses them") func aValueInDoubleQuotesLosesThem() {
        #expect(parsed("font-family = \"Maple Mono\"").fontFamily == "Maple Mono")
        #expect(parsed("font-family = Maple Mono").fontFamily == "Maple Mono")
    }

    @Test("a lone quote stays") func aLoneQuoteStays() {
        #expect(parsed("font-family = \"").fontFamily == "\"")
    }

    @Test("a value keeps its own =") func aValueKeepsItsOwn() {
        #expect(parsed("theme = a=b").theme == "a=b")
    }

    @Test("an empty value sets the key back to its default") func anEmptyValueSetsTheKeyBackTo() {
        #expect(parsed("pill-width = 200\npill-width =").pillWidth == 136)
        #expect(parsed("theme = x\ntheme = \"\"").theme == "Fuwafuwa Sakura")
    }

    @Test("theme keeps its text") func themeKeepsItsText() {
        #expect(parsed("theme = light:A,dark:B").theme == "light:A,dark:B")
        #expect(parsed("theme = /t/x").theme == "/t/x")
    }

    @Test("font-size takes a number above 0") func fontSizeTakesANumberAbove0() {
        #expect(parsed("font-size = 13.5").fontSize == 13.5)
        #expect(reasons("font-size = 0") == ["expects a number above 0"])
    }

    @Test("booleans as Ghostty reads them") func booleansAsGhosttyReadsThem() {
        #expect(parsed("font-thicken = true").fontThicken)
        #expect(parsed("copy-on-select = 1").copyOnSelect)
        #expect(!parsed("font-thicken = t\nfont-thicken = false").fontThicken)
        #expect(reasons("font-thicken = yes") == ["expects true or false"])
    }

    @Test("option-as-alt takes false, true, left and right", arguments: ["false", "true", "left", "right"])
    func optionAsAltTakes(value: String) {
        #expect(parsed("option-as-alt = \(value)").optionAsAlt.rawValue == value)
    }

    @Test("option-as-alt refuses any other value") func optionAsAltRefusesAnyOtherValue() {
        #expect(reasons("option-as-alt = both") == ["expects one of false, true, left, right"])
    }

    @Test("pill-width takes 60 to 400") func pillWidthTakes60To400() {
        #expect(parsed("pill-width = 60").pillWidth == 60)
        #expect(parsed("pill-width = 400").pillWidth == 400)
        #expect(reasons("pill-width = 59\npill-width = 401")
            == ["expects a number from 60 to 400", "expects a number from 60 to 400"])
    }

    @Test("background-opacity clamps to 0 to 1") func backgroundOpacityClampsTo0To1() {
        #expect(parsed("background-opacity = 0.8").backgroundOpacity == 0.8)
        #expect(parsed("background-opacity = 2").backgroundOpacity == 1)
        #expect(parsed("background-opacity = -1").backgroundOpacity == 0)
        #expect(problems("background-opacity = 2").isEmpty)
        #expect(reasons("background-opacity = half") == ["expects a number"])
    }

    @Test("background-blur true is 20, false 0, or a radius 0 to 100") func backgroundBlurTrueIs20False0Or() {
        #expect(parsed("background-blur = true").backgroundBlur == 20)
        #expect(parsed("background-blur = 20\nbackground-blur = false").backgroundBlur == 0)
        #expect(parsed("background-blur = 100").backgroundBlur == 100)
        #expect(reasons("background-blur = 101\nbackground-blur = -1")
            == Array(repeating: "expects true, false or a number from 0 to 100", count: 2))
    }

    @Test("the clipboard keys take allow, deny and ask") func theClipboardKeysTakeAllowDenyAndAsk() {
        #expect(parsed("clipboard-write = ask").clipboardWrite == .ask)
        #expect(parsed("clipboard-read = allow").clipboardRead == .allow)
        #expect(reasons("clipboard-read = never") == ["expects one of allow, deny, ask"])
    }

    @Test("an unknown key, a line without = and a bad value each give their line and reason")
    func anUnknownKeyALineWithoutAndA() {
        #expect(problems(mixed) == [
            ConfigProblem(line: 2, text: "font-szie = 16", reason: "unknown key"),
            ConfigProblem(line: 3, text: "stray", reason: "no '='"),
            ConfigProblem(line: 5, text: "pill-width = 900", reason: "expects a number from 60 to 400")])
    }

    @Test("while the other keys still apply") func whileTheOtherKeysStillApply() {
        #expect(parsed(mixed).pillWidth == 200)
        #expect(parsed(mixed).fontSize == 16)
    }

    @Test("the config card names one problem and its line") func theConfigCardNamesOneProblemAndIts() {
        #expect(one.title == "Config has 1 problem")
        #expect(one.name == "config-problems 1")
        #expect(one.excerpt == "line 7  pill-width = 900: expects a number from 60 to 400")
    }

    @Test("its buttons are Dismiss and Open Config, the default, and Escape dismisses")
    func itsButtonsAreDismissAndOpenConfigThe() {
        #expect(one.actions == [.dismiss, .openConfig])
        #expect(one.defaultAction == .openConfig)
        #expect(one.escape == .dismiss)
        #expect(one.label(.openConfig) == "Open Config")
    }

    @Test("the config card shows 8 lines, each cut in the middle, then how many more")
    func theConfigCardShows8LinesEachCut() {
        #expect(nine.title == "Config has 9 problems")
        #expect(nine.excerpt?.split(separator: "\n").count == 9)
        #expect(nine.excerpt?.split(separator: "\n").dropLast().allSatisfy { $0.count <= 12 && $0.contains("…") }
            == true)
        #expect(nine.excerpt?.hasSuffix("\nand 1 more") == true)
    }

    @Test("a file that is not UTF-8 reads as line 0 and its reason") func aFileThatIsNotUtf8Reads() {
        #expect(configCard(readConfig(Data([0xff])).1) { _ in true }.excerpt == "line 0: not UTF-8")
    }
}
