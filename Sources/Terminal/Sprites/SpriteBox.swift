import CoreGraphics

// Box drawing, U+2500 to U+257F, and branch drawing, U+F5D0 to U+F60D. Adapted from Ghostty's
// `src/font/sprite/draw/box.zig` and `src/font/sprite/draw/branch.zig` at commit 22f100c6.
// Ghostty: MIT License, Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors; see vendor/LICENSE-ghostty.

/// The style of line from each edge to the centre, Ghostty's `Lines`.
struct Lines {
    enum Style { case none, light, heavy, double }
    var up = Style.none, right = Style.none, down = Style.none, left = Style.none

    /// Up, right, down and left, each `.`, `l`ight, `h`eavy or `d`ouble.
    init(_ spec: String) {
        let s = spec.map { c -> Style in c == "l" ? .light : c == "h" ? .heavy : c == "d" ? .double : .none }
        (up, right, down, left) = (s[0], s[1], s[2], s[3])
    }
}

/// The lines of each codepoint `linesChar` draws: up, right, down, left.
private let boxLines: [UInt32: String] = [
    0x2500: ".l.l", 0x2501: ".h.h", 0x2502: "l.l.", 0x2503: "h.h.", 0x250C: ".ll.", 0x250D: ".hl.", 0x250E: ".lh.",
    0x250F: ".hh.", 0x2510: "..ll", 0x2511: "..lh", 0x2512: "..hl", 0x2513: "..hh", 0x2514: "ll..", 0x2515: "lh..",
    0x2516: "hl..", 0x2517: "hh..", 0x2518: "l..l", 0x2519: "l..h", 0x251A: "h..l", 0x251B: "h..h", 0x251C: "lll.",
    0x251D: "lhl.", 0x251E: "hll.", 0x251F: "llh.", 0x2520: "hlh.", 0x2521: "hhl.", 0x2522: "lhh.", 0x2523: "hhh.",
    0x2524: "l.ll", 0x2525: "l.lh", 0x2526: "h.ll", 0x2527: "l.hl", 0x2528: "h.hl", 0x2529: "h.lh", 0x252A: "l.hh",
    0x252B: "h.hh", 0x252C: ".lll", 0x252D: ".llh", 0x252E: ".hll", 0x252F: ".hlh", 0x2530: ".lhl", 0x2531: ".lhh",
    0x2532: ".hhl", 0x2533: ".hhh", 0x2534: "ll.l", 0x2535: "ll.h", 0x2536: "lh.l", 0x2537: "lh.h", 0x2538: "hl.l",
    0x2539: "hl.h", 0x253A: "hh.l", 0x253B: "hh.h", 0x253C: "llll", 0x253D: "lllh", 0x253E: "lhll", 0x253F: "lhlh",
    0x2540: "hlll", 0x2541: "llhl", 0x2542: "hlhl", 0x2543: "hllh", 0x2544: "hhll", 0x2545: "llhh", 0x2546: "lhhl",
    0x2547: "hhlh", 0x2548: "lhhh", 0x2549: "hlhh", 0x254A: "hhhl", 0x254B: "hhhh", 0x2550: ".d.d", 0x2551: "d.d.",
    0x2552: ".dl.", 0x2553: ".ld.", 0x2554: ".dd.", 0x2555: "..ld", 0x2556: "..dl", 0x2557: "..dd", 0x2558: "ld..",
    0x2559: "dl..", 0x255A: "dd..", 0x255B: "l..d", 0x255C: "d..l", 0x255D: "d..d", 0x255E: "ldl.", 0x255F: "dld.",
    0x2560: "ddd.", 0x2561: "l.ld", 0x2562: "d.dl", 0x2563: "d.dd", 0x2564: ".dld", 0x2565: ".ldl", 0x2566: ".ddd",
    0x2567: "ld.d", 0x2568: "dl.l", 0x2569: "dd.d", 0x256A: "ldld", 0x256B: "dldl", 0x256C: "dddd", 0x2574: "...l",
    0x2575: "l...", 0x2576: ".l..", 0x2577: "..l.", 0x2578: "...h", 0x2579: "h...", 0x257A: ".h..", 0x257B: "..h.",
    0x257C: ".h.l", 0x257D: "l.h.", 0x257E: ".l.h", 0x257F: "h.l.",
]

func drawBox(_ cp: UInt32, _ c: inout Canvas, _ cell: Cell) {
    if let lines = boxLines[cp] { return linesChar(cell, &c, Lines(lines)) }
    let light = cell.line(.light), heavy = cell.line(.heavy)
    switch cp {
    case 0x2504: dashHorizontal(cell, &c, 3, light, max(4, light))
    case 0x2505: dashHorizontal(cell, &c, 3, heavy, max(4, light))
    case 0x2506: dashVertical(cell, &c, 3, light, max(4, light))
    case 0x2507: dashVertical(cell, &c, 3, heavy, max(4, light))
    case 0x2508: dashHorizontal(cell, &c, 4, light, max(4, light))
    case 0x2509: dashHorizontal(cell, &c, 4, heavy, max(4, light))
    case 0x250A: dashVertical(cell, &c, 4, light, max(4, light))
    case 0x250B: dashVertical(cell, &c, 4, heavy, max(4, light))
    case 0x254C: dashHorizontal(cell, &c, 2, light, light)
    case 0x254D: dashHorizontal(cell, &c, 2, heavy, heavy)
    case 0x254E: dashVertical(cell, &c, 2, light, heavy)
    case 0x254F: dashVertical(cell, &c, 2, heavy, heavy)
    case 0x256D: arc(cell, &c, .br, .light)
    case 0x256E: arc(cell, &c, .bl, .light)
    case 0x256F: arc(cell, &c, .tl, .light)
    case 0x2570: arc(cell, &c, .tr, .light)
    case 0x2571: lightDiagonalUpperRightToLowerLeft(cell, &c)
    case 0x2572: lightDiagonalUpperLeftToLowerRight(cell, &c)
    case 0x2573: lightDiagonalCross(cell, &c)
    default: break
    }
}

/// Each line from its edge to the centre, where the lines meet so that heavy covers light and double lines join.
func linesChar(_ cell: Cell, _ c: inout Canvas, _ lines: Lines) {
    let light = cell.line(.light), heavy = cell.line(.heavy)
    let (w, h) = (cell.width, cell.height)

    let hLightTop = centred(h, light), hLightBottom = hLightTop + light
    let hHeavyTop = centred(h, heavy), hHeavyBottom = hHeavyTop + heavy
    // The outer edges of the doubled strokes; the inner ones are the light stroke's.
    let hDoubleTop = max(hLightTop - light, 0), hDoubleBottom = hLightBottom + light
    let vLightLeft = centred(w, light), vLightRight = vLightLeft + light
    let vHeavyLeft = centred(w, heavy), vHeavyRight = vHeavyLeft + heavy
    let vDoubleLeft = max(vLightLeft - light, 0), vDoubleRight = vLightRight + light

    let (up, right, down, left) = (lines.up, lines.right, lines.down, lines.left)
    let upBottom = left == .heavy || right == .heavy ? hHeavyBottom
        : left != right || down == up ? (left == .double || right == .double ? hDoubleBottom : hLightBottom)
        : left == .none && right == .none ? hLightBottom : hLightTop
    let downTop = left == .heavy || right == .heavy ? hHeavyTop
        : left != right || up == down ? (left == .double || right == .double ? hDoubleTop : hLightTop)
        : left == .none && right == .none ? hLightTop : hLightBottom
    let leftRight = up == .heavy || down == .heavy ? vHeavyRight
        : up != down || left == right ? (up == .double || down == .double ? vDoubleRight : vLightRight)
        : up == .none && down == .none ? vLightRight : vLightLeft
    let rightLeft = up == .heavy || down == .heavy ? vHeavyLeft
        : up != down || right == left ? (up == .double || down == .double ? vDoubleLeft : vLightLeft)
        : up == .none && down == .none ? vLightLeft : vLightRight

    switch up {
    case .none: break
    case .light: c.box(vLightLeft, 0, vLightRight, upBottom)
    case .heavy: c.box(vHeavyLeft, 0, vHeavyRight, upBottom)
    case .double:
        c.box(vDoubleLeft, 0, vLightLeft, left == .double ? hLightTop : upBottom)
        c.box(vLightRight, 0, vDoubleRight, right == .double ? hLightTop : upBottom)
    }
    switch right {
    case .none: break
    case .light: c.box(rightLeft, hLightTop, w, hLightBottom)
    case .heavy: c.box(rightLeft, hHeavyTop, w, hHeavyBottom)
    case .double:
        c.box(up == .double ? vLightRight : rightLeft, hDoubleTop, w, hLightTop)
        c.box(down == .double ? vLightRight : rightLeft, hLightBottom, w, hDoubleBottom)
    }
    switch down {
    case .none: break
    case .light: c.box(vLightLeft, downTop, vLightRight, h)
    case .heavy: c.box(vHeavyLeft, downTop, vHeavyRight, h)
    case .double:
        c.box(vDoubleLeft, left == .double ? hLightBottom : downTop, vLightLeft, h)
        c.box(vLightRight, right == .double ? hLightBottom : downTop, vDoubleRight, h)
    }
    switch left {
    case .none: break
    case .light: c.box(0, hLightTop, leftRight, hLightBottom)
    case .heavy: c.box(0, hHeavyTop, leftRight, hHeavyBottom)
    case .double:
        c.box(0, hDoubleTop, up == .double ? vLightLeft : leftRight, hLightTop)
        c.box(0, hLightBottom, down == .double ? vLightLeft : leftRight, hDoubleBottom)
    }
}

/// The diagonals overshoot the corners a little along their slope, so they join their neighbours across corners.
func lightDiagonalUpperRightToLowerLeft(_ cell: Cell, _ c: inout Canvas) {
    let (w, h) = (Double(cell.width), Double(cell.height))
    let sx = min(1, w / h), sy = min(1, h / w)
    c.line(w + 0.5 * sx, -0.5 * sy, -0.5 * sx, h + 0.5 * sy, thickness: Double(cell.line(.light)))
}

func lightDiagonalUpperLeftToLowerRight(_ cell: Cell, _ c: inout Canvas) {
    let (w, h) = (Double(cell.width), Double(cell.height))
    let sx = min(1, w / h), sy = min(1, h / w)
    c.line(-0.5 * sx, -0.5 * sy, w + 0.5 * sx, h + 0.5 * sy, thickness: Double(cell.line(.light)))
}

func lightDiagonalCross(_ cell: Cell, _ c: inout Canvas) {
    lightDiagonalUpperRightToLowerLeft(cell, &c)
    lightDiagonalUpperLeftToLowerRight(cell, &c)
}

/// A rounded corner joining the centre lines of the two edges away from `corner`'s opposite: `.br` runs from the
/// bottom edge round to the right one.
func arc(_ cell: Cell, _ c: inout Canvas, _ corner: Corner, _ thickness: Thickness) {
    let t = cell.line(thickness)
    let (w, h, thick) = (Double(cell.width), Double(cell.height), Double(t))
    let cx = Double(centred(cell.width, t)) + thick / 2, cy = Double(centred(cell.height, t)) + thick / 2
    let r = min(w, h) / 2
    // How far from the centre the middle control points sit.
    let s = 0.25
    // Toward the vertical edge, then toward the horizontal one.
    let (vy, edgeY): (Double, Double) = corner == .tl || corner == .tr ? (-1, 0) : (1, h)
    let (hx, edgeX): (Double, Double) = corner == .tl || corner == .bl ? (-1, 0) : (1, w)
    let path = CGMutablePath()
    path.move(to: CGPoint(x: cx, y: edgeY))
    path.addLine(to: CGPoint(x: cx, y: cy + vy * r))
    path.addCurve(to: CGPoint(x: cx + hx * r, y: cy), control1: CGPoint(x: cx, y: cy + vy * s * r),
                  control2: CGPoint(x: cx + hx * s * r, y: cy))
    path.addLine(to: CGPoint(x: edgeX, y: cy))
    c.stroke(path, width: thick)
}

/// `count` dashes that tile across cells with even gaps: half a gap at each side. A cell too narrow for them draws a
/// solid line.
private func dashHorizontal(_ cell: Cell, _ c: inout Canvas, _ count: Int, _ thick: Int, _ desiredGap: Int) {
    guard cell.width >= 2 * count else { return hlineMiddle(cell, &c, .light) }
    // Gaps never take more than half the space.
    let gap = min(desiredGap, cell.width / (2 * count))
    let dashes = cell.width - count * gap
    let dash = dashes / count
    var extra = dashes % count
    let y = centred(cell.height, thick)
    var x = gap / 2
    for _ in 0..<count {
        // The leftover pixels widen the dashes, where they show least.
        var x1 = x + dash
        if extra > 0 { extra -= 1; x1 += 1 }
        hline(&c, x, x1, y, thick)
        x = x1 + gap
    }
}

/// `count` dashes that tile down cells: a whole gap at the bottom, so they join a solid line above without a half gap.
private func dashVertical(_ cell: Cell, _ c: inout Canvas, _ count: Int, _ thick: Int, _ desiredGap: Int) {
    guard cell.height >= 2 * count else { return vlineMiddle(cell, &c, .light) }
    let gap = min(desiredGap, cell.height / (2 * count))
    let dashes = cell.height - count * gap
    let dash = dashes / count
    var extra = dashes % count
    let x = centred(cell.width, thick)
    var y = 0
    for _ in 0..<count {
        var y1 = y + dash
        if extra > 0 { extra -= 1; y1 += 1 }
        vline(&c, y, y1, x, thick)
        y = y1 + gap
    }
}

func drawBranch(_ cp: UInt32, _ c: inout Canvas, _ cell: Cell) {
    switch cp {
    case 0xF5D0: hlineMiddle(cell, &c, .light)
    case 0xF5D1: vlineMiddle(cell, &c, .light)
    case 0xF5D2: fadingLine(cell, &c, .right)
    case 0xF5D3: fadingLine(cell, &c, .left)
    case 0xF5D4: fadingLine(cell, &c, .bottom)
    case 0xF5D5: fadingLine(cell, &c, .top)
    case 0xF5D6...0xF5ED:
        // Each draws a centre line, `|` or `-`, and arcs.
        let parts: [(line: Character?, arcs: [Corner])] = [
            (nil, [.br]), (nil, [.bl]), (nil, [.tr]), (nil, [.tl]),
            ("|", [.tr]), ("|", [.br]), (nil, [.tr, .br]), ("|", [.tl]), ("|", [.bl]), (nil, [.tl, .bl]),
            ("-", [.bl]), ("-", [.br]), (nil, [.br, .bl]), ("-", [.tl]), ("-", [.tr]), (nil, [.tr, .tl]),
            ("|", [.tl, .tr]), ("|", [.bl, .br]), ("-", [.bl, .tl]), ("-", [.tr, .br]),
            ("|", [.tl, .br]), ("|", [.tr, .bl]), ("-", [.tl, .br]), ("-", [.tr, .bl]),
        ]
        let part = parts[Int(cp - 0xF5D6)]
        if part.line == "|" { vlineMiddle(cell, &c, .light) }
        if part.line == "-" { hlineMiddle(cell, &c, .light) }
        for corner in part.arcs { arc(cell, &c, corner, .light) }
    case 0xF5EE...0xF60D:
        // In pairs, filled then outlined: none, right, left, left and right, down, up, up and down, right and down,
        // left and down, up and right, up and left, up down and right, up down and left, down left and right,
        // up left and right, all four.
        let edges = ["", "r", "l", "lr", "d", "u", "ud", "rd", "ld", "ur", "ul", "udr", "udl", "dlr", "ulr", "udlr"]
        let i = Int(cp - 0xF5EE), e = edges[i / 2]
        branchNode(cell, &c, edges: e, filled: i % 2 == 0)
    default: break
    }
}

/// A branch node: lines from the circle to the edges named `u`p, `r`ight, `d`own and `l`eft, and the circle filled or
/// as an outline.
private func branchNode(_ cell: Cell, _ c: inout Canvas, edges: String, filled: Bool) {
    let t = cell.line(.light)
    let (w, h, thick) = (Double(cell.width), Double(cell.height), Double(t))
    let hTop = centred(cell.height, t), hBottom = hTop + t
    let vLeft = centred(cell.width, t), vRight = vLeft + t
    // The centre sits on the box-drawing lines, which may sit off the cell's centre to stay on whole pixels; the
    // radius reaches the nearest edge.
    let cx = Double(vLeft) + thick / 2, cy = Double(hTop) + thick / 2
    let r = min(min(cx, cy), min(w - cx, h - cy))
    if edges.contains("u") { c.box(vLeft, 0, vRight, Int((cy - r + thick / 2).rounded(.up))) }
    if edges.contains("r") { c.box(Int((cx + r - thick / 2).rounded(.down)), hTop, cell.width, hBottom) }
    if edges.contains("d") { c.box(vLeft, Int((cy + r - thick / 2).rounded(.down)), vRight, cell.height) }
    if edges.contains("l") { c.box(0, hTop, Int((cx - r + thick / 2).rounded(.up)), hBottom) }
    if filled { c.fill(circlePath(cx, cy, r)) } else { c.stroke(circlePath(cx, cy, r - thick / 2), width: thick) }
}

/// A centre line fading from full coverage at the far edge to none at `to`.
private func fadingLine(_ cell: Cell, _ c: inout Canvas, _ to: Edge) {
    let t = cell.line(.light)
    let hTop = centred(cell.height, t), hBottom = hTop + t
    let vLeft = centred(cell.width, t), vRight = vLeft + t
    var color: Double = to == .top || to == .left ? 0 : 255
    let inc = switch to {
    case .top: 255 / Double(cell.height)
    case .bottom: -255 / Double(cell.height)
    case .left: 255 / Double(cell.width)
    case .right: -255 / Double(cell.width)
    }
    if to == .top || to == .bottom {
        for y in 0..<cell.height {
            for x in vLeft..<vRight { c.pixel(x, y, UInt8(color.rounded())) }
            color += inc
        }
    } else {
        for x in 0..<cell.width {
            for y in hTop..<hBottom { c.pixel(x, y, UInt8(color.rounded())) }
            color += inc
        }
    }
}
