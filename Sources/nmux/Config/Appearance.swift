import AppKit
import Terminal

/// What an apply must redo, in the order it redoes them and the self-test logs them.
nonisolated enum Change: String, CaseIterable {
    case colours, face, opacity, pills, input
}

/// The Config and the colours in force; nil before the first apply, which redoes everything.
nonisolated struct Applied: Equatable {
    var config: Config
    var theme: Theme
}

/// What differs between the old Config and colours and the new. The theme's path is left out: the same colours from
/// another file redraw nothing. Its appearance counts, since the colour scheme report follows it.
nonisolated func changes(from old: Applied?, to new: Applied) -> [Change] {
    guard let old else { return Change.allCases }
    func differs<T: Equatable>(_ key: KeyPath<Config, T>) -> Bool {
        old.config[keyPath: key] != new.config[keyPath: key]
    }
    var (oldTheme, newTheme) = (old.theme, new.theme)
    (oldTheme.source, newTheme.source) = (nil, nil)
    var changed: Set<Change> = []
    if oldTheme != newTheme { changed.insert(.colours) }
    if differs(\.fontFamily) || differs(\.fontSize) || differs(\.fontThicken) { changed.insert(.face) }
    if differs(\.backgroundOpacity) || differs(\.backgroundBlur) { changed.insert(.opacity) }
    if differs(\.pillWidth) { changed.insert(.pills) }
    if differs(\.optionAsAlt) || differs(\.copyOnSelect) || differs(\.clipboardWrite) || differs(\.clipboardRead) {
        changed.insert(.input)
    }
    return Change.allCases.filter(changed.contains)
}

/// What an apply reaches: the window, every Session's terminal, the fit of a new face and the Session bar.
protocol AppearanceHost: AnyObject {
    var window: NSWindow? { get }
    var terminals: [TerminalView] { get }
    /// A new face at the window's backing scale: every terminal takes it and the window snaps to its cells.
    func faceChanged(_ font: Font)
    /// Every pill at the new `pill-width`.
    func pillWidthChanged(_ width: Double)
    /// The New Session field's text and caret in the new colours.
    func colourField()
}

/// The Config and the Theme in force, and the one apply that puts them on screen: at launch before the first Session,
/// on Reload Config and on a switch of the appearance. Only what changed since the last apply is redone, so nothing
/// changed draws nothing. Content, selection, scroll, marked text, the shown Session and an open prompt stay; tmux
/// hears only of a new grid.
final class Appearance {
    let location: ConfigLocation
    weak var host: AppearanceHost?
    private(set) var config = Config()
    /// The lines the last load skipped, until the author dismisses their card.
    var problems: [ConfigProblem]?
    /// The colours in force, for the appearance they were resolved for, and what the last apply put on screen.
    private(set) var theme = Theme(dark: false)
    private var applied: Applied?
    private var watch: NSKeyValueObservation?

    init(_ location: ConfigLocation) { self.location = location }

    /// Reads the Config whole, logs every value in force and applies them with the Theme.
    func load(_ cause: String) {
        let problems: [ConfigProblem]
        (config, problems) = readConfig(FileManager.default.contents(atPath: location.config),
                                        exists: FileManager.default.fileExists(atPath: location.config))
        for line in configLines(config) { selfTestLog("config \(line)") }
        for problem in problems { selfTestLog("config-problem \(problem.line) \(problem.reason)") }
        loadTheme()
        apply(cause)
        self.problems = problems.isEmpty ? nil : problems
    }

    /// Reads the theme file again for the window's appearance, or the one given; a Theme found nowhere is the Fallback
    /// look and no problem.
    func loadTheme(dark: Bool? = nil) {
        guard let window = host?.window else { return }
        let folders = themeFolders(location, bundle: Bundle.main.resourceURL?.appendingPathComponent("themes").path)
        theme = resolveTheme(ThemeSpec(config.theme), dark: dark ?? isDark(window.effectiveAppearance),
                             folders: folders) {
            FileManager.default.contents(atPath: $0)
        }
        selfTestLog("theme \(theme.dark ? "dark" : "light") \(theme.source ?? "fallback")")
        selfTestLog("colour background=\(hex(theme.background)) foreground=\(hex(theme.foreground)) "
                    + "accent=\(hex(theme.accent))")
    }

    /// A pair, or the Fallback look, follows the system appearance live; a single Theme found keeps its colours, and
    /// only the colour scheme report follows the switch.
    func follow(_ window: NSWindow) {
        watch = window.observe(\.effectiveAppearance) { window, _ in
            MainActor.assumeIsolated {
                let dark = isDark(window.effectiveAppearance)
                guard dark != self.theme.dark else { return }
                if ThemeSpec(self.config.theme).pair || self.theme.source == nil {
                    self.loadTheme()
                } else {
                    self.theme.dark = dark
                }
                self.apply("appearance")
            }
        }
    }

    func apply(_ cause: String) {
        guard let host, let window = host.window else { return }
        let next = Applied(config: config, theme: theme), redo = changes(from: applied, to: next)
        applied = next
        selfTestLog("apply \(cause) " + (redo.isEmpty ? "none" : redo.map(\.rawValue).joined(separator: " ")))
        for change in redo {
            switch change {
            case .colours: for view in host.terminals { view.setColors(theme.terminal) }
            case .face: host.faceChanged(makeFont(scale: window.backingScaleFactor))
            case .opacity: for view in host.terminals { view.opacity = config.backgroundOpacity }
            case .pills: host.pillWidthChanged(config.pillWidth)
            case .input: for view in host.terminals { input(view) }
            }
        }
        if redo.contains(.colours) || redo.contains(.opacity) {
            ChromeTheme.current = ChromeTheme(theme, opacity: config.backgroundOpacity)
            syncWindowBackground()
            // Every drawn view draws again: the bar's, the tips over the terminal and the card among them.
            func redraw(_ view: NSView) {
                view.needsDisplay = true
                view.subviews.forEach(redraw)
            }
            window.contentView.map(redraw)
            host.colourField()
        }
    }

    /// A new Session's terminal starts with what the last apply put on the others.
    func dress(_ view: TerminalView) {
        view.setColors(theme.terminal)
        view.opacity = config.backgroundOpacity
        input(view)
    }

    /// As Ghostty's window: below 1 it is not opaque, its background all but clear and blurred by `background-blur`;
    /// else it takes the Theme's background and no blur.
    func syncWindowBackground() {
        guard let window = host?.window else { return }
        let clear = config.backgroundOpacity < 1
        window.isOpaque = !clear
        window.backgroundColor = clear ? .white.withAlphaComponent(0.001) : nsColor(theme.background)
        blur(window, radius: clear ? config.backgroundBlur : 0)
    }

    /// The input keys, read at the view's next key, selection or OSC 52 request.
    private func input(_ view: TerminalView) {
        (view.optionAsAlt, view.copyOnSelect) = (config.optionAsAlt, config.copyOnSelect)
        (view.clipboardWrite, view.clipboardRead) = (config.clipboardWrite, config.clipboardRead)
    }

    /// `font-family` at `font-size` points at the backing scale, with `font-thicken`. SF Mono is the system's
    /// monospaced face, which CoreText does not find by name; a family CoreText cannot find falls back to it, logged
    /// and never a problem. Under the self-test, NMUX_SELFTEST_FONT names a face file in the app's Resources/Fonts to
    /// draw in instead.
    func makeFont(scale: Double) -> Font {
        let size = config.fontSize
        var face: CTFont = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
#if NMUX_SELFTEST
        let forced = SelfTest.font.flatMap { Bundle.main.resourceURL?.appendingPathComponent("Fonts/\($0)") }
            .flatMap { (CTFontManagerCreateFontDescriptorsFromURL($0 as CFURL) as? [CTFontDescriptor])?.first }
#else
        let forced: CTFontDescriptor? = nil
#endif
        if let forced {
            face = CTFontCreateWithFontDescriptor(forced, size, nil)
        } else if config.fontFamily != Config().fontFamily {
            let wanted = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: config.fontFamily]
                                                              as CFDictionary)
            if let found = CTFontDescriptorCreateMatchingFontDescriptor(wanted, nil)
                .map({ CTFontCreateWithFontDescriptor($0, size, nil) }),
               family(found).caseInsensitiveCompare(config.fontFamily) == .orderedSame {
                face = found
            } else {
                selfTestLog("font-family \(config.fontFamily) not found")
            }
        }
        selfTestLog("font \(family(face)) \(logNumber(size))")
        return Font(face, points: size, scale: scale, thicken: config.fontThicken)
    }
}

func isDark(_ appearance: NSAppearance) -> Bool { appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
