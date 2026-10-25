import AppKit
import GhosttyVt

// What a key becomes before the encoder sees it: the Option that is Alt, the mods with their sides, the text and the
// edit keys. Adapted from Ghostty's `src/input/key_mods.zig`, `macos/Sources/Ghostty/Ghostty.Input.swift`,
// `NSEvent+Extension.swift` and the macOS keybinds of `src/config/Config.zig` at commit 22f100c6.
// Ghostty: MIT License, Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors; see vendor/LICENSE-ghostty.

/// The `option-as-alt` setting: which Option is Alt. False, the default, leaves both to type.
public enum OptionAsAlt: String, Sendable {
    case `false`, `true`, left, right

    var ghostty: GhosttyOptionAsAlt {
        switch self {
        case .false: GHOSTTY_OPTION_AS_ALT_FALSE
        case .true: GHOSTTY_OPTION_AS_ALT_TRUE
        case .left: GHOSTTY_OPTION_AS_ALT_LEFT
        case .right: GHOSTTY_OPTION_AS_ALT_RIGHT
        }
    }
}

/// The flags the layout translates the key with: an Option that is Alt goes, so the text is the key's own. The right
/// Option's device mask names the side; the other flags, hidden bits included, stay as they came.
func translationFlags(_ flags: NSEvent.ModifierFlags, _ optionAsAlt: OptionAsAlt) -> NSEvent.ModifierFlags {
    guard flags.contains(.option) else { return flags }
    let right = flags.rawValue & UInt(NX_DEVICERALTKEYMASK) != 0
    switch optionAsAlt {
    case .false: return flags
    case .left where right, .right where !right: return flags
    default: return flags.subtracting(.option)
    }
}

/// Each modifier: its flag, libghostty-vt's mod, and for the four with sides, the right one's device mask and side bit.
private let modifierBits: [(flag: NSEvent.ModifierFlags, mod: Int32, right: (mask: Int32, side: Int32)?)] = [
    (.shift, GHOSTTY_MODS_SHIFT, (NX_DEVICERSHIFTKEYMASK, GHOSTTY_MODS_SHIFT_SIDE)),
    (.control, GHOSTTY_MODS_CTRL, (NX_DEVICERCTLKEYMASK, GHOSTTY_MODS_CTRL_SIDE)),
    (.option, GHOSTTY_MODS_ALT, (NX_DEVICERALTKEYMASK, GHOSTTY_MODS_ALT_SIDE)),
    (.command, GHOSTTY_MODS_SUPER, (NX_DEVICERCMDKEYMASK, GHOSTTY_MODS_SUPER_SIDE)),
    (.capsLock, GHOSTTY_MODS_CAPS_LOCK, nil),
]

private func rightHeld(_ flags: NSEvent.ModifierFlags, _ mask: Int32) -> Bool { flags.rawValue & UInt(mask) != 0 }

/// libghostty-vt's mods for the flags, a right-hand modifier marked by its side bit.
func ghosttyMods(_ flags: NSEvent.ModifierFlags) -> GhosttyMods {
    modifierBits.reduce(0) { mods, m in
        var mods = flags.contains(m.flag) ? mods | GhosttyMods(m.mod) : mods
        if let right = m.right, rightHeld(flags, right.mask) { mods |= GhosttyMods(right.side) }
        return mods
    }
}

/// The mods the layout spent on the text: never Control or Command. Caps Lock stays among them, as in Ghostty.
func consumedMods(_ translation: NSEvent.ModifierFlags) -> GhosttyMods {
    ghosttyMods(translation.subtracting([.control, .command]))
}

/// The modifier keys, each with its flag and whether it is the right one.
private let modifierKeys: [GhosttyKey: (flag: NSEvent.ModifierFlags, right: Bool)] = [
    GHOSTTY_KEY_CAPS_LOCK: (.capsLock, false),
    GHOSTTY_KEY_SHIFT_LEFT: (.shift, false), GHOSTTY_KEY_SHIFT_RIGHT: (.shift, true),
    GHOSTTY_KEY_CONTROL_LEFT: (.control, false), GHOSTTY_KEY_CONTROL_RIGHT: (.control, true),
    GHOSTTY_KEY_ALT_LEFT: (.option, false), GHOSTTY_KEY_ALT_RIGHT: (.option, true),
    GHOSTTY_KEY_META_LEFT: (.command, false), GHOSTTY_KEY_META_RIGHT: (.command, true),
]

/// Whether a modifier key's change pressed it, or nil for a key that is no modifier. A right key counts as pressed only
/// while its own device mask is set; otherwise the change released it with the other side still held, as in Ghostty.
func modifierPressed(_ key: GhosttyKey, _ flags: NSEvent.ModifierFlags) -> Bool? {
    guard let (flag, right) = modifierKeys[key] else { return nil }
    guard flags.contains(flag) else { return false }
    guard right, let mask = modifierBits.first(where: { $0.flag == flag })?.right?.mask else { return true }
    return rightHeld(flags, mask)
}

/// The text the encoder gets: a control character comes back as its key without Control, which `withoutControl` gives;
/// a codepoint in Apple's function-key range, or text that starts with a control character, is none.
func keyText(_ characters: String?, withoutControl: () -> String?) -> String? {
    guard var text = characters else { return nil }
    if text.unicodeScalars.count == 1, let scalar = text.unicodeScalars.first {
        if scalar.value < 0x20 { text = withoutControl() ?? "" }
        if (0xF700...0xF8FF).contains(scalar.value) { return nil }
    }
    guard let first = text.unicodeScalars.first, first.value >= 0x20, first.value != 0x7F else { return nil }
    return text
}

/// The four modifiers a table matches on, exactly; Caps Lock, Fn and the keypad flag never count.
func matchedModifiers(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
    flags.intersection([.shift, .control, .option, .command])
}

/// Ghostty's macOS edit keys: Cmd+Left to the line's start, Cmd+Right to its end, Cmd+Backspace kills the line, and
/// Option+Left and Option+Right move by word. Only with exactly those mods.
func editKey(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags) -> [UInt8]? {
    switch (macKeys[keyCode], matchedModifiers(flags)) {
    case (GHOSTTY_KEY_ARROW_LEFT?, .command): [0x01]
    case (GHOSTTY_KEY_ARROW_RIGHT?, .command): [0x05]
    case (GHOSTTY_KEY_BACKSPACE?, .command): [0x15]
    case (GHOSTTY_KEY_ARROW_LEFT?, .option): [0x1B, 0x62]
    case (GHOSTTY_KEY_ARROW_RIGHT?, .option): [0x1B, 0x66]
    default: nil
    }
}
