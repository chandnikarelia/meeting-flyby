import Cocoa

// Renders the Meeting Flyby app icon: a pet flying with a towed banner over a sunset sky,
// inside the standard macOS squircle. Exports every iconset size, ready for iconutil.

let canvas: CGFloat = 1024
// Apple's Big Sur+ app icon grid: the rounded rect is 824/1024 wide with a ~185pt radius.
let plateInset: CGFloat = (canvas - 824) / 2
let plateRadius: CGFloat = 185.4

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: 1)
}

let sunsetTop = color(255, 183, 77)     // amber
let sunsetMid = color(255, 107, 74)     // coral
let sunsetLow = color(240, 78, 138)     // pink
let cream = color(255, 249, 240)

func drawIcon(into ctx: CGContext) {
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let plate = CGRect(x: plateInset, y: plateInset, width: canvas - 2*plateInset, height: canvas - 2*plateInset)
    let platePath = CGPath(roundedRect: plate, cornerWidth: plateRadius, cornerHeight: plateRadius, transform: nil)

    // --- sky ---
    ctx.saveGState()
    ctx.addPath(platePath)
    ctx.clip()
    if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [sunsetTop.cgColor, sunsetMid.cgColor, sunsetLow.cgColor] as CFArray,
                          locations: [0, 0.55, 1]) {
        ctx.drawLinearGradient(g,
            start: CGPoint(x: plate.minX, y: plate.maxY),
            end: CGPoint(x: plate.maxX, y: plate.minY),
            options: [])
    }

    // soft sun glow, upper left
    if let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: [NSColor.white.withAlphaComponent(0.55).cgColor,
                                      NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
                             locations: [0, 1]) {
        ctx.drawRadialGradient(glow,
            startCenter: CGPoint(x: plate.minX + 200, y: plate.maxY - 170), startRadius: 10,
            endCenter: CGPoint(x: plate.minX + 200, y: plate.maxY - 170), endRadius: 330,
            options: [])
    }

    // --- clouds: puffs on a flat base, so they read as clouds rather than scattered dots ---
    func cloud(cx: CGFloat, cy: CGFloat, w: CGFloat, alpha: CGFloat) {
        let h = w * 0.42
        let path = CGMutablePath()
        path.addRoundedRect(in: CGRect(x: cx - w/2, y: cy - h*0.18, width: w, height: h*0.40),
                            cornerWidth: h*0.20, cornerHeight: h*0.20)
        for (fx, fy, fr) in [(CGFloat(-0.26), CGFloat(0.06), CGFloat(0.22)),
                             (0.0, 0.20, 0.30),
                             (0.27, 0.08, 0.20)] {
            let r = w * fr
            path.addEllipse(in: CGRect(x: cx + w*fx - r, y: cy + h*fy - r, width: r*2, height: r*2))
        }
        ctx.setFillColor(NSColor.white.withAlphaComponent(alpha).cgColor)
        ctx.addPath(path)
        ctx.fillPath()
    }
    // kept away from the subject so they stay background texture
    cloud(cx: plate.minX + 150, cy: plate.minY + 165, w: 300, alpha: 0.26)
    cloud(cx: plate.maxX - 120, cy: plate.maxY - 175, w: 210, alpha: 0.20)

    // Composition: pet up-left, banner down-right, clearly separated and tilted together so
    // it reads as "towing" rather than the banner sprouting from the dog's mouth.
    let petCenter = CGPoint(x: canvas/2 - 95, y: canvas/2 + 150)
    let bannerCenter = CGPoint(x: canvas/2 + 105, y: canvas/2 - 165)
    let tilt: CGFloat = -11 * .pi / 180

    // --- tow rope (drawn first so the banner and pet sit on top of its ends) ---
    ctx.saveGState()
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.95).cgColor)
    ctx.setLineWidth(14)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: petCenter.x + 118, y: petCenter.y - 62))
    ctx.addQuadCurve(to: CGPoint(x: bannerCenter.x - 215, y: bannerCenter.y + 40),
                     control: CGPoint(x: petCenter.x + 120, y: bannerCenter.y + 80))
    ctx.strokePath()
    ctx.restoreGState()

    // --- banner ---
    ctx.saveGState()
    ctx.translateBy(x: bannerCenter.x, y: bannerCenter.y)
    ctx.rotate(by: tilt)

    let bw: CGFloat = 430, bh: CGFloat = 132
    let bannerRect = CGRect(x: -bw/2, y: -bh/2, width: bw, height: bh)
    let ribbon = CGMutablePath()
    let steps = 40
    func edge(_ frac: CGFloat, top: Bool) -> CGFloat {
        let wave = sin(frac * .pi * 2.0 + (top ? 0 : 0.5)) * 11
        return top ? bannerRect.maxY + wave : bannerRect.minY + wave
    }
    for i in 0...steps {
        let f = CGFloat(i)/CGFloat(steps)
        let p = CGPoint(x: bannerRect.minX + f*bw, y: edge(f, top: true))
        i == 0 ? ribbon.move(to: p) : ribbon.addLine(to: p)
    }
    ribbon.addLine(to: CGPoint(x: bannerRect.maxX - 42, y: 0))   // swallowtail notch
    ribbon.addLine(to: CGPoint(x: bannerRect.maxX, y: edge(1, top: false)))
    for i in stride(from: steps, through: 0, by: -1) {
        let f = CGFloat(i)/CGFloat(steps)
        ribbon.addLine(to: CGPoint(x: bannerRect.minX + f*bw, y: edge(f, top: false)))
    }
    ribbon.closeSubpath()

    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30,
                  color: NSColor.black.withAlphaComponent(0.26).cgColor)
    ctx.addPath(ribbon)
    ctx.setFillColor(cream.cgColor)
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // two bars standing in for the meeting title
    ctx.setFillColor(sunsetMid.cgColor)
    ctx.addPath(CGPath(roundedRect: CGRect(x: -152, y: 14, width: 236, height: 28),
                       cornerWidth: 14, cornerHeight: 14, transform: nil))
    ctx.fillPath()
    ctx.setFillColor(sunsetLow.withAlphaComponent(0.6).cgColor)
    ctx.addPath(CGPath(roundedRect: CGRect(x: -152, y: -36, width: 150, height: 24),
                       cornerWidth: 12, cornerHeight: 12, transform: nil))
    ctx.fillPath()
    ctx.restoreGState()

    // --- the pet ---
    let pet = "🐶" as NSString
    let font = NSFont.systemFont(ofSize: 360)
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    let petSize = pet.size(withAttributes: attrs)

    ctx.saveGState()
    ctx.translateBy(x: petCenter.x, y: petCenter.y)
    ctx.rotate(by: tilt)
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28,
                  color: NSColor.black.withAlphaComponent(0.28).cgColor)
    let gc = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gc
    pet.draw(at: CGPoint(x: -petSize.width/2, y: -petSize.height/2), withAttributes: attrs)
    NSGraphicsContext.restoreGraphicsState()
    ctx.restoreGState()

    ctx.restoreGState() // un-clip the plate


    // subtle inner highlight along the top edge, so the plate reads as glossy
    ctx.saveGState()
    ctx.addPath(platePath)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.30).cgColor)
    ctx.setLineWidth(5)
    ctx.strokePath()
    ctx.restoreGState()
}

// --- render + export ---
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(size: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0),
          let gc = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gc
    let ctx = gc.cgContext
    let s = CGFloat(size) / canvas
    ctx.scaleBy(x: s, y: s)
    drawIcon(into: ctx)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let sizes: [(Int, String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"),
    (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"),
    (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]
for (px, name) in sizes {
    guard let data = render(size: px) else { print("failed \(name)"); continue }
    try? data.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}
// a standalone preview for the README / sharing
if let data = render(size: 512) {
    try? data.write(to: URL(fileURLWithPath: "\(outDir)/../icon-preview.png"))
}
print("wrote \(sizes.count) sizes to \(outDir)")
