import GhosttyVt

/// libghostty-vt's mouse encoder and one mouse event, reused for every report.
final class MouseEncoder {
    private var encoder: GhosttyMouseEncoder?
    private var event: GhosttyMouseEvent?

    init() {
        ghostty_mouse_encoder_new(nil, &encoder)
        ghostty_mouse_event_new(nil, &event)
        // Motion inside the cell last reported is reported once, as Ghostty's `last_cell`.
        var dedupe = true
        ghostty_mouse_encoder_setopt(encoder, GHOSTTY_MOUSE_ENCODER_OPT_TRACK_LAST_CELL, &dedupe)
    }

    deinit {
        ghostty_mouse_event_free(event)
        ghostty_mouse_encoder_free(encoder)
    }

    /// The bytes for one event at `x`, `y` pixels from the surface's top left, none when the terminal's mode does not
    /// report it. The encoder takes the terminal's tracking mode and format, the surface and cell size, and whether any
    /// button is held, before every event.
    func encode(_ host: VTHost, action: GhosttyMouseAction, button: GhosttyMouseButton?, mods: GhosttyMods,
                x: Double, y: Double, surface: (width: Double, height: Double), cell: Cell,
                anyPressed: Bool) -> [UInt8] {
        guard let encoder, let event else { return [] }
        var size = GhosttyMouseEncoderSize()
        size.size = MemoryLayout<GhosttyMouseEncoderSize>.size
        (size.screen_width, size.screen_height) = (UInt32(max(surface.width, 0)), UInt32(max(surface.height, 0)))
        (size.cell_width, size.cell_height) = (UInt32(cell.width), UInt32(cell.height))
        var pressed = anyPressed
        ghostty_mouse_event_set_action(event, action)
        if let button { ghostty_mouse_event_set_button(event, button) } else { ghostty_mouse_event_clear_button(event) }
        ghostty_mouse_event_set_mods(event, mods)
        ghostty_mouse_event_set_position(event, GhosttyMousePosition(x: Float(x), y: Float(y)))
        return host.locked { t in
            ghostty_mouse_encoder_setopt_from_terminal(encoder, t)
            ghostty_mouse_encoder_setopt(encoder, GHOSTTY_MOUSE_ENCODER_OPT_SIZE, &size)
            ghostty_mouse_encoder_setopt(encoder, GHOSTTY_MOUSE_ENCODER_OPT_ANY_BUTTON_PRESSED, &pressed)
            var out = [CChar](repeating: 0, count: 64), n = 0
            guard ghostty_mouse_encoder_encode(encoder, event, &out, out.count, &n) == GHOSTTY_SUCCESS
            else { return [] }
            return out[..<n].map { UInt8(bitPattern: $0) }
        }
    }
}
