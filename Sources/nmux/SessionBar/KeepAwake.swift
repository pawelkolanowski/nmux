import IOKit.pwr_mgt

/// The Keep-awake cup's hold: while it stands the Mac does not sleep on its own, as `caffeinate -i` holds it; the
/// display still may. It ends with nmux.
final class KeepAwake {
    private(set) var hold: IOPMAssertionID?

    /// False when the system refuses the hold.
    func start() -> Bool {
        var id = IOPMAssertionID(0)
        guard IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                          IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                          "nmux keeps the Mac awake" as CFString,
                                          &id) == kIOReturnSuccess else { return false }
        hold = id
        return true
    }

    func release() {
        if let hold { IOPMAssertionRelease(hold) }
        hold = nil
    }
}
