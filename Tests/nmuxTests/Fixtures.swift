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

// A cell of 17 × 33 pixels with the font's decorations, as the constraint and sprite tests draw in.
let decorated = Cell(width: 17, height: 33, baseline: 6, underlinePosition: 29, underlineThickness: 2,
                     strikethroughPosition: 20, strikethroughThickness: 2, cursorThickness: 1, faceWidth: 17,
                     faceHeight: 33, faceY: 0, iconHeight: 33, iconHeightSingle: 33)
