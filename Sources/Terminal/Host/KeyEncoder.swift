import GhosttyVt

/// libghostty-vt's key encoder and one key event, reused for every key.
final class KeyEncoder {
    private var encoder: GhosttyKeyEncoder?
    private var event: GhosttyKeyEvent?

    init() {
        ghostty_key_encoder_new(nil, &encoder)
        ghostty_key_event_new(nil, &event)
    }

    deinit {
        ghostty_key_event_free(event)
        ghostty_key_encoder_free(encoder)
    }

    func encode(_ host: VTHost, optionAsAlt: OptionAsAlt, action: GhosttyKeyAction, key: GhosttyKey, mods: GhosttyMods,
                consumed: GhosttyMods, unshifted: UInt32, text: String?, composing: Bool = false) -> [UInt8] {
        guard let encoder, let event else { return [] }
        host.locked { ghostty_key_encoder_setopt_from_terminal(encoder, $0) }
        var option = optionAsAlt.ghostty
        ghostty_key_encoder_setopt(encoder, GHOSTTY_KEY_ENCODER_OPT_MACOS_OPTION_AS_ALT, &option)
        ghostty_key_event_set_action(event, action)
        ghostty_key_event_set_key(event, key)
        ghostty_key_event_set_mods(event, mods)
        ghostty_key_event_set_consumed_mods(event, consumed)
        ghostty_key_event_set_unshifted_codepoint(event, unshifted)
        // A key that composes makes no bytes of its own.
        ghostty_key_event_set_composing(event, composing)
        // The event does not own its text, so the encode runs while the string is alive.
        let utf8 = Array((text ?? "").utf8CString)
        return utf8.withUnsafeBufferPointer { p in
            ghostty_key_event_set_utf8(event, text == nil ? nil : p.baseAddress, utf8.count - 1)
            var out = [CChar](repeating: 0, count: 128), n = 0
            var result = ghostty_key_encoder_encode(encoder, event, &out, out.count, &n)
            if result == GHOSTTY_OUT_OF_SPACE {
                out = [CChar](repeating: 0, count: n)
                result = ghostty_key_encoder_encode(encoder, event, &out, out.count, &n)
            }
            guard result == GHOSTTY_SUCCESS else { return [] }
            return out[..<n].map { UInt8(bitPattern: $0) }
        }
    }
}
