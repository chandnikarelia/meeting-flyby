import Cocoa

/// Draws the flying character towing a ribbon banner, animated per-frame: the character bobs,
/// tilts and squash-stretches, little speed puffs trail behind it, and the ribbon ripples
/// along its whole length like real cloth.
final class BannerContentView: NSView {
    private let character: String
    private let message: String
    private let accent: NSColor
    private let accentDeep: NSColor
    private var phase: CGFloat = 0
    private var timer: Timer?

    init(character: String, message: String) {
        self.character = character
        self.message = message
        self.accent = Theme.accent(for: character)
        self.accentDeep = Theme.accentDeep(for: character)
        super.init(frame: .zero)
        wantsLayer = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.phase += 0.09
            self.needsDisplay = true
        }
    }

    required init?(coder: NSCoder) { fatalError("unavailable") }

    func stopAnimating() {
        timer?.invalidate()
        timer = nil
    }

    deinit { timer?.invalidate() }

    // Layout constants — the character rides on the left, banner trails to the right.
    private let charSize: CGFloat = 44
    private let charX: CGFloat = 10
    private let ropeLength: CGFloat = 22

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let bob = sin(phase) * 6
        let tilt = sin(phase * 0.9 + 0.4) * 7 // degrees
        let centerY = bounds.height / 2 + bob
        let charCenter = CGPoint(x: charX + charSize / 2, y: centerY)

        drawSpeedPuffs(ctx, around: charCenter)

        let bannerX = charX + charSize + ropeLength
        let bannerRect = NSRect(x: bannerX, y: bounds.height / 2 - 21, width: bounds.width - bannerX - 8, height: 42)
        drawTowRope(ctx, from: CGPoint(x: charX + charSize - 4, y: centerY), to: bannerRect)
        drawRibbon(ctx, in: bannerRect)
        drawCharacter(ctx, center: charCenter, tilt: tilt)
    }

    /// Little trailing puffs that make the character read as moving, not just floating.
    private func drawSpeedPuffs(_ ctx: CGContext, around center: CGPoint) {
        for i in 0..<3 {
            let offset = CGFloat(i)
            let travel = (phase * 22 + offset * 26).truncatingRemainder(dividingBy: 60)
            let x = center.x - 12 - travel
            guard x > -14 else { continue }
            let fade = max(0, 1 - travel / 60)
            let radius = 3.5 - offset * 0.6
            let y = center.y - 10 + sin(phase * 1.6 + offset) * 5
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.30 * fade).cgColor)
            ctx.fillEllipse(in: CGRect(x: x, y: y, width: radius * 2, height: radius * 2))
        }
    }

    private func drawTowRope(_ ctx: CGContext, from start: CGPoint, to bannerRect: NSRect) {
        let end = CGPoint(x: bannerRect.minX + 1, y: bannerRect.midY + sin(phase * 1.3) * 3)
        let sag = 5 + sin(phase * 1.1) * 2
        let control = CGPoint(x: (start.x + end.x) / 2, y: min(start.y, end.y) - sag)

        ctx.saveGState()
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
        ctx.setLineWidth(2)
        ctx.setLineCap(.round)
        ctx.move(to: start)
        ctx.addQuadCurve(to: end, control: control)
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func drawRibbon(_ ctx: CGContext, in rect: NSRect) {
        let path = ribbonPath(in: rect)

        // Soft drop shadow so the ribbon lifts off whatever is behind it.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 10, color: NSColor.black.withAlphaComponent(0.28).cgColor)
        ctx.addPath(path)
        ctx.setFillColor(accent.cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        // Gradient wash for depth.
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [accent.cgColor, accentDeep.cgColor] as CFArray,
            locations: [0, 1]
        ) {
            ctx.drawLinearGradient(gradient,
                                   start: CGPoint(x: rect.minX, y: rect.maxY),
                                   end: CGPoint(x: rect.maxX, y: rect.minY),
                                   options: [])
        }
        // Glossy highlight along the top half.
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.16).cgColor)
        ctx.fill(CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2))
        ctx.restoreGState()

        // Crisp edge.
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.55).cgColor)
        ctx.setLineWidth(1.5)
        ctx.strokePath()
        ctx.restoreGState()

        drawMessage(in: rect)
    }

    private func drawMessage(in rect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -1)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: Theme.rounded(16, weight: .bold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
            .shadow: shadow
        ]
        let size = message.size(withAttributes: attrs)
        let textRect = NSRect(
            x: rect.minX + 14,
            y: rect.midY - size.height / 2 + sin(phase * 1.5) * 1.5,
            width: rect.width - 28,
            height: size.height
        )
        message.draw(in: textRect, withAttributes: attrs)
    }

    /// A ribbon whose top and bottom edges ripple along the full length, with notched
    /// swallowtail ends like a real towed banner.
    private func ribbonPath(in rect: NSRect) -> CGPath {
        let path = CGMutablePath()
        let segments = 40
        let amplitude: CGFloat = 4.5
        let notch: CGFloat = 10

        func edgeY(_ frac: CGFloat, top: Bool) -> CGFloat {
            let wave = sin(frac * .pi * 2.2 - phase * 1.6 + (top ? 0 : 0.5)) * amplitude
            let taper = sin(frac * .pi) * 2
            return top ? rect.maxY - taper + wave : rect.minY + taper + wave
        }

        // Top edge, left to right.
        for i in 0...segments {
            let frac = CGFloat(i) / CGFloat(segments)
            let point = CGPoint(x: rect.minX + frac * rect.width, y: edgeY(frac, top: true))
            i == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        // Swallowtail notch on the trailing edge.
        path.addLine(to: CGPoint(x: rect.maxX - notch, y: rect.midY + edgeWave()))
        path.addLine(to: CGPoint(x: rect.maxX, y: edgeY(1, top: false)))
        // Bottom edge, right to left.
        for i in stride(from: segments, through: 0, by: -1) {
            let frac = CGFloat(i) / CGFloat(segments)
            path.addLine(to: CGPoint(x: rect.minX + frac * rect.width, y: edgeY(frac, top: false)))
        }
        path.closeSubpath()
        return path
    }

    private func edgeWave() -> CGFloat {
        sin(phase * 1.6) * 3
    }

    private func drawCharacter(_ ctx: CGContext, center: CGPoint, tilt: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: charSize)]
        let size = character.size(withAttributes: attrs)

        // Squash and stretch on the bob cycle — the classic trick that makes motion feel alive.
        let squash = 1 + sin(phase * 2) * 0.06

        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: tilt * .pi / 180)
        ctx.scaleBy(x: 1 / squash, y: squash)
        ctx.translateBy(x: -size.width / 2, y: -size.height / 2)
        character.draw(at: .zero, withAttributes: attrs)
        ctx.restoreGState()
    }
}

/// Drives one flyby window's position by hand, one frame at a time. Deliberately avoids
/// NSAnimationContext / window.animator().setFrame — that path creates an internal
/// _NSWindowTransformAnimation which is prone to a use-after-free crash on dealloc for
/// borderless, always-on-top windows like this one.
private final class FlightDriver {
    private let window: NSWindow
    private let contentView: BannerContentView
    private let startX: CGFloat
    private let endX: CGFloat
    private let y: CGFloat
    private let duration: TimeInterval
    private let startTime = Date()
    private var timer: Timer?

    // Keeps every in-flight driver alive until it finishes, so ARC can't tear a window
    // down mid-animation.
    private static var active: [FlightDriver] = []

    static func launch(character: String, message: String, screen: NSScreen, duration: TimeInterval) {
        let width: CGFloat = 520
        let height: CGFloat = 96
        let y = screen.frame.maxY - 140
        let startX = screen.frame.maxX
        let endX = screen.frame.minX - width

        let contentView = BannerContentView(character: character, message: message)
        let window = NSWindow(
            contentRect: NSRect(x: startX, y: y, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(Int(CGWindowLevelForKey(.maximumWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.contentView = contentView
        window.orderFrontRegardless()

        let driver = FlightDriver(window: window, contentView: contentView, startX: startX, endX: endX, y: y, duration: duration)
        active.append(driver)
        driver.start()
    }

    private init(window: NSWindow, contentView: BannerContentView, startX: CGFloat, endX: CGFloat, y: CGFloat, duration: TimeInterval) {
        self.window = window
        self.contentView = contentView
        self.startX = startX
        self.endX = endX
        self.y = y
        self.duration = duration
    }

    private func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        let elapsed = Date().timeIntervalSince(startTime)
        let progress = min(1.0, elapsed / duration)
        let x = startX + (endX - startX) * CGFloat(progress)
        window.setFrameOrigin(NSPoint(x: x, y: y))

        if progress >= 1.0 {
            timer?.invalidate()
            timer = nil
            contentView.stopAnimating()
            window.orderOut(nil)
            window.contentView = nil
            Self.active.removeAll { $0 === self }
        }
    }
}

enum FlybyOverlay {
    /// Sends a character towing a banner flying right-to-left across every screen, above all
    /// windows — including fullscreen apps in their own Space.
    static func fly(character: String, message: String, durationPerScreen: TimeInterval = 14.0) {
        AnimalSound.play(for: character)
        for screen in NSScreen.screens {
            FlightDriver.launch(character: character, message: message, screen: screen, duration: durationPerScreen)
        }
    }
}
