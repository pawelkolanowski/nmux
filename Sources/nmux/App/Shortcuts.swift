import AppKit

// The app shortcuts, on the pattern of the macOS keybinds of Ghostty's `src/config/Config.zig` at commit 22f100c6.
// Ghostty: MIT License, Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors; see vendor/LICENSE-ghostty.

/// What an app shortcut does. Its name is the self-test's.
nonisolated enum AppAction: Hashable, Sendable {
    case openConfig, reloadConfig, quit, copy, paste, selectAll, clear
    case newSession, closeSession, closeNmux, previousSession, nextSession, session(Int), lastSession

    var name: String {
        switch self {
        case .openConfig: "open-config"
        case .reloadConfig: "reload-config"
        case .quit: "quit"
        case .copy: "copy"
        case .paste: "paste"
        case .selectAll: "select-all"
        case .clear: "clear"
        case .newSession: "new-session"
        case .closeSession: "close-session"
        case .closeNmux: "close-nmux"
        case .previousSession: "previous-session"
        case .nextSession: "next-session"
        case .session(let n): "session-\(n)"
        case .lastSession: "last-session"
        }
    }
}

/// The main menu's menus, in order; the first is the app's own.
nonisolated enum Menu: String, CaseIterable, Sendable {
    case nmux, edit = "Edit", sessions = "Sessions"
}

/// One app shortcut: the menu it shows in, its title, and its key as the layout types it without modifiers.
nonisolated struct Shortcut: Sendable {
    let menu: Menu
    let title: String
    let key: String
    let flags: NSEvent.ModifierFlags
    let action: AppAction
}

/// The fixed table, on Ghostty's pattern; nothing else is bound, so Cmd+=, Cmd+- and Cmd+0 go to the terminal. Cmd+W
/// keeps the title Close Session although it kills, as the pill asks first.
nonisolated let shortcuts: [Shortcut] = [
    Shortcut(menu: .nmux, title: "Open Config", key: ",", flags: .command, action: .openConfig),
    Shortcut(menu: .nmux, title: "Reload Config", key: ",", flags: [.command, .shift], action: .reloadConfig),
    Shortcut(menu: .nmux, title: "Quit nmux", key: "q", flags: .command, action: .quit),
    Shortcut(menu: .edit, title: "Copy", key: "c", flags: .command, action: .copy),
    Shortcut(menu: .edit, title: "Paste", key: "v", flags: .command, action: .paste),
    Shortcut(menu: .edit, title: "Select All", key: "a", flags: .command, action: .selectAll),
    Shortcut(menu: .edit, title: "Clear", key: "k", flags: .command, action: .clear),
    Shortcut(menu: .sessions, title: "New Session", key: "t", flags: .command, action: .newSession),
    Shortcut(menu: .sessions, title: "Close Session", key: "w", flags: .command, action: .closeSession),
    Shortcut(menu: .sessions, title: "Close nmux", key: "w", flags: [.command, .shift], action: .closeNmux),
    Shortcut(menu: .sessions, title: "Previous Session", key: "[", flags: [.command, .shift], action: .previousSession),
    Shortcut(menu: .sessions, title: "Next Session", key: "]", flags: [.command, .shift], action: .nextSession),
] + (1...8).map { Shortcut(menu: .sessions, title: "Session \($0)", key: "\($0)", flags: .command,
                           action: .session($0)) }
    + [Shortcut(menu: .sessions, title: "Last Session", key: "9", flags: .command, action: .lastSession)]

/// The shortcut a key with these flags makes, matched on its unmodified character and exactly its four modifiers: Caps
/// Lock, Fn and the keypad flag never count.
nonisolated func shortcut(_ key: String?, _ flags: NSEvent.ModifierFlags) -> Shortcut? {
    let mods = flags.intersection([.shift, .control, .option, .command])
    return shortcuts.first { $0.key == key?.lowercased() && $0.flags == mods }
}
