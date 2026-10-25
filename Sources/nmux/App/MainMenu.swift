import AppKit

/// The app shortcuts as the main menu's key equivalents, so they show in the menu bar; the first menu is the app's own.
func makeMainMenu(target: AppDelegate) -> NSMenu {
    let main = NSMenu()
    for name in Menu.allCases {
        let menu = NSMenu(title: name.rawValue)
        for s in shortcuts where s.menu == name {
            let item = menu.addItem(withTitle: s.title, action: #selector(AppDelegate.menuPicked(_:)),
                                    keyEquivalent: s.key)
            item.keyEquivalentModifierMask = s.flags
            item.target = target
            item.representedObject = s.action
        }
        let holder = NSMenuItem(title: name.rawValue, action: nil, keyEquivalent: "")
        holder.submenu = menu
        main.addItem(holder)
    }
    return main
}
