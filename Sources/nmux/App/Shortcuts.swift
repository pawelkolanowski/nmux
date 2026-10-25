import AppKit

// The app shortcuts, on the pattern of the macOS keybinds of Ghostty's `src/config/Config.zig` at commit 22f100c6.
// Ghostty: MIT License, Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors; see vendor/LICENSE-ghostty.

/// What an app shortcut does. Its name is the self-test's.
nonisolated enum AppAction: Hashable, Sendable {
    case quit

    var name: String {
        switch self {
        case .quit: "quit"
        }
    }
}

/// The main menu's menus, in order; the first is the app's own.
nonisolated enum Menu: String, CaseIterable, Sendable {
    case nmux
}

/// One app shortcut: the menu it shows in, its title, and its key as the layout types it without modifiers.
nonisolated struct Shortcut: Sendable {
    let menu: Menu
    let title: String
    let key: String
    let flags: NSEvent.ModifierFlags
    let action: AppAction
}

/// The fixed table, on Ghostty's pattern.
nonisolated let shortcuts: [Shortcut] = [
    Shortcut(menu: .nmux, title: "Quit nmux", key: "q", flags: .command, action: .quit),
]
