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

// SF Mono from its file: by name CoreText gives Helvetica for it.
func sfMono(_ size: CGFloat) -> CTFont {
    let file = CTFontManagerCreateFontDescriptorsFromURL(
        URL(fileURLWithPath: "/System/Library/Fonts/SFNSMono.ttf") as CFURL)
    return CTFontCreateWithFontDescriptor((file as! [CTFontDescriptor])[0], size, nil)
}
