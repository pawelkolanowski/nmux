# nmux's only build entry. `make` builds build/nmux.app from a fresh clone, offline.
APP  := build/nmux.app
# The app the seam drives: the release app with the self-test compiled in.
SELFTEST := build/selftest/nmux.app
SOURCES  := $(shell find Sources -name '*.swift')
ZIP  := vendor/ghostty-vt.xcframework.zip
LOCK := vendor/libghostty-vt.lock
# The zip unpacked, once it passed its lock.
VT   := build/ghostty-vt.xcframework/macos-arm64_x86_64

.PHONY: all run install test seam references bench clean

all: $(APP)

run: $(APP)
	open $(APP)

install: $(APP)
	rm -rf /Applications/nmux.app
	cp -R $(APP) /Applications/

# The logic tests first, so they fail before the slow seam; the smoke launch then starts the app that ships.
test: $(APP) $(SELFTEST)
	swift test
	Tests/seam/run.sh
	Tests/seam/smoke.sh

# `make seam RUN="2 3"` runs only those runs; `make seam` runs them all.
seam: $(SELFTEST)
	Tests/seam/run.sh $(RUN)

# Draws the twelve reference sheets into build/references for the author to look at; it checks nothing.
references: $(VT)/libghostty-vt.a
	NMUX_REFERENCES=1 swift test --filter drawTheTwelveReferenceSheets

# Prints the allocations and the time of one full-screen rebuild of the rows, in a release build; it checks nothing.
bench: $(VT)/libghostty-vt.a
	NMUX_BENCH=1 swift test -c release -Xswiftc -enable-testing --build-path .build/bench --filter rebuildAFullScreenOfRows

clean:
	rm -rf build .build

build/check-lock: Tools/lock/Lock.swift Tools/lock/main.swift
	mkdir -p build && swiftc -o $@ $^

$(VT)/libghostty-vt.a: $(ZIP) $(LOCK) build/check-lock
	build/check-lock $(LOCK) $(ZIP)
	rm -rf build/ghostty-vt.xcframework && unzip -q $(ZIP) -d build && touch $@

# The zip passes its lock before SwiftPM unpacks it. macOS kills a binary that cp overwrote in place
# while an earlier copy ran, so the old one goes first.
build/nmux: $(SOURCES) Package.swift $(VT)/libghostty-vt.a
	swift build -c release
	rm -f $@ && cp .build/release/nmux $@

# A build path of its own, so the two builds never share products.
build/selftest/nmux: $(SOURCES) Package.swift $(VT)/libghostty-vt.a
	swift build -c release -Xswiftc -DNMUX_SELFTEST --build-path .build/selftest
	mkdir -p build/selftest && rm -f $@ && cp .build/selftest/release/nmux $@

$(SELFTEST): $(APP) build/selftest/nmux
	rm -rf $@ && cp -R $(APP) $@ && cp build/selftest/nmux $@/Contents/MacOS/nmux

build/nmux.metallib: Sources/Terminal/Render/Shaders.metal
	mkdir -p build && xcrun metal -Wall -o $@ $<

# iconutil takes every size at 1x and 2x.
build/logo.icns: assets/logo.svg
	rm -rf build/logo.iconset && mkdir -p build/logo.iconset
	for s in 16 32 128 256 512; do \
		sips -s format png -z $$s $$s $< --out build/logo.iconset/icon_$${s}x$${s}.png >/dev/null && \
		sips -s format png -z $$((s * 2)) $$((s * 2)) $< \
			--out build/logo.iconset/icon_$${s}x$${s}@2x.png >/dev/null || exit 1; \
	done
	iconutil -c icns -o $@ build/logo.iconset

$(APP): build/nmux build/nmux.metallib build/logo.icns Resources/Info.plist LICENSE NOTICE vendor/LICENSE-ghostty \
		$(wildcard Resources/Fonts/*) vendor/iTerm2-Color-Schemes/COMMIT vendor/iTerm2-Color-Schemes/LICENSE \
		Resources/themes/Fuwafuwa\ Sakura
	rm -rf $@
	mkdir -p $@/Contents/MacOS $@/Contents/Resources/Licenses $@/Contents/Resources/Fonts $@/Contents/Resources/themes
	# nmux's own themes go last, so one of a bundled name would take its place; the bump replaces the folder and COMMIT.
	cp vendor/iTerm2-Color-Schemes/ghostty/* Resources/themes/* $@/Contents/Resources/themes/
	cp Resources/Fonts/*.ttf $@/Contents/Resources/Fonts/
	cp Resources/Fonts/MapleMono-OFL.txt $@/Contents/Resources/Licenses/maple-mono-OFL
	cp build/nmux $@/Contents/MacOS/
	cp Resources/Info.plist $@/Contents/
	cp build/logo.icns build/nmux.metallib $@/Contents/Resources/
	cp LICENSE $@/Contents/Resources/Licenses/nmux-LICENSE
	cp NOTICE $@/Contents/Resources/Licenses/NOTICE
	cp vendor/LICENSE-ghostty $@/Contents/Resources/Licenses/ghostty-LICENSE
	cp Resources/Fonts/SymbolsNerdFont-LICENSE.txt $@/Contents/Resources/Licenses/symbols-nerd-font-LICENSE
	cp vendor/iTerm2-Color-Schemes/LICENSE $@/Contents/Resources/Licenses/iterm2-color-schemes-LICENSE
