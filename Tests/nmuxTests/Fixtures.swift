import AppKit
import CoreText
import Foundation
@testable import nmux
@testable import Terminal

// What more than one suite reads: the repository's files, the fonts, and the fixtures the suites share.

// The repository's root, found from this file, so the tests read its files from any working directory.
let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()

func repositoryPath(_ relative: String) -> String { repository.appendingPathComponent(relative).path }

// Symbols Nerd Font, registered once as the app registers it at launch; a test that needs it reads this first.
let symbolsRegistered: Bool = CTFontManagerRegisterFontsForURL(
    URL(fileURLWithPath: repositoryPath("Resources/Fonts/SymbolsNerdFont-Regular.ttf")) as CFURL, .process, nil)

// SF Mono from its file: by name CoreText gives Helvetica for it.
func sfMono(_ size: CGFloat) -> CTFont {
    let file = CTFontManagerCreateFontDescriptorsFromURL(
        URL(fileURLWithPath: "/System/Library/Fonts/SFNSMono.ttf") as CFURL)
    return CTFontCreateWithFontDescriptor((file as! [CTFontDescriptor])[0], size, nil)
}

// The flags an arrow key carries.
let arrows: NSEvent.ModifierFlags = [.function, .numericPad]

// A cell of 17 × 33 pixels with the font's decorations, as the constraint and sprite tests draw in.
let decorated = Cell(width: 17, height: 33, baseline: 6, underlinePosition: 29, underlineThickness: 2,
                     strikethroughPosition: 20, strikethroughThickness: 2, cursorThickness: 1, faceWidth: 17,
                     faceHeight: 33, faceY: 0, iconHeight: 33, iconHeightSingle: 33)

// The config a text parses to, its problems left out.
func parsed(_ text: String) -> Config { parseConfig(text).0 }

// Theme files in two folders, a user one that shadows the bundle: `themeFile` reads them as the lookup does.
private let themeFiles = ["/u/nmux/themes/Dracula": "background = #000001", "/b/Dracula": "background = #000002",
                          "/b/Nord": "background = #000003", "/any/where": "background = #000004", "/b/../b/Nord": "x",
                          "/b/x/Nord": "x"]
let lookupFolders = themeFolders(ConfigLocation(xdg: "/u", home: "/h"), bundle: "/b")
// A user file that is not UTF-8 is passed over for the bundle's.
private let themeData = themeFiles.mapValues { Data($0.utf8) }.merging(["/u/nmux/themes/Nord": Data([0xff])]) { $1 }
func themeFile(_ path: String) -> Data? { themeData[path] }

// Fuwafuwa Sakura, nmux's own theme, on the light side.
let sakura = Theme(parseTheme((try? String(contentsOfFile: repositoryPath("Resources/themes/Fuwafuwa Sakura"),
                                           encoding: .utf8)) ?? ""),
                   dark: false)

// A 2 × 1 PNG, red `ff0000` left and blue `0000ff` right, RGB with no colour chunk.
let redBlue = Data(base64Encoded:
    "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAIAAAB7QOjdAAAADUlEQVR4nGP4zwAE/wEHAAH/4iOeWQAAAABJRU5ErkJggg==")!
