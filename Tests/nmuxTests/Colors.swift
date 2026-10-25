import Testing
@testable import Terminal

// The fallback's colours: Terminal.app's Basic defaults and palette, and xterm's colours 16 to 255.
struct ColorsTests {
    @Test("light mode is black on white") func lightModeIsBlackOnWhite() {
        #expect(fallbackDefaults(dark: false) == (RGB(0x000000), RGB(0xffffff)))
    }

    @Test("dark mode is white on black") func darkModeIsWhiteOnBlack() {
        #expect(fallbackDefaults(dark: true) == (RGB(0xffffff), RGB(0x000000)))
    }

    @Test("the palette holds 256 colours") func thePaletteHolds256Colours() {
        #expect(fallbackPalette.count == 256)
    }

    @Test("colours 0 to 15 are Terminal.app's Basic") func colours0To15AreTerminalAppsBasic() {
        #expect(fallbackPalette[1] == RGB(0x990000))
        #expect(fallbackPalette[8] == RGB(0x666666))
        #expect(fallbackPalette[15] == RGB(0xe5e5e5))
    }

    @Test("the cube runs from black through xterm's levels to white") func theCubeRunsFromBlackThroughXtermsLevels() {
        #expect(fallbackPalette[16] == RGB(0x000000))
        #expect(fallbackPalette[17] == RGB(0x00005f))
        #expect(fallbackPalette[196] == RGB(0xff0000))
        #expect(fallbackPalette[231] == RGB(0xffffff))
    }

    @Test("the grey ramp runs from #080808 to #eeeeee") func theGreyRampRunsFrom080808ToEeeeee() {
        #expect(fallbackPalette[232] == RGB(0x080808))
        #expect(fallbackPalette[255] == RGB(0xeeeeee))
    }
}
