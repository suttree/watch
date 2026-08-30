import AppKit

/// How a theme paints a surface — the pattern vocabulary carried over from the
/// host app, so a palette that reads as stripes there reads as stripes here.
///
/// Ported rather than shared: the two apps are separate packages, and this is
/// the whole of what Read needs from the ~800-line original. The drawing is
/// kept faithful to host's so the same seed produces the same artwork in both.
enum ThemePatternStyle {
    /// One flat colour. Not a pattern at all, which is exactly what the
    /// window's title bar wants — the artwork belongs on the icon.
    case solid(NSColor)
    /// Solid diagonal bands, in the order given, running top-left to
    /// bottom-right. Bold and flat, the way fork does it.
    case stripes([NSColor])
    /// A smooth ramp through the given stops along the same diagonal.
    case gradient([NSColor])
    /// Two broad diagonal colour fields.
    case twoTone([NSColor])
    case polkaDots(background: NSColor, dots: [NSColor])
    case finePolkaDots(background: NSColor, dots: [NSColor])
    case packedCircles(background: NSColor, circles: [NSColor], seed: UInt64)
    case triangles([NSColor], seed: UInt64)
    /// An irregular triangulation rather than a repeating pattern.
    case mesh([NSColor], seed: UInt64)
    /// Dense, freely scattered dots of widely varying size.
    case kusamaDots(background: NSColor, dots: [NSColor], seed: UInt64)
    /// Soft overlapping radial washes that bleed into one another.
    case watercolour(background: NSColor, washes: [NSColor], seed: UInt64)
    case diamonds(background: NSColor, diamonds: [NSColor])
    case waves(background: NSColor, waves: [NSColor], spacing: CGFloat, amplitude: CGFloat)
    case bubbles(background: NSColor, bubbles: [NSColor], seed: UInt64)
    case radial([NSColor])
    case grain(background: NSColor, shades: [NSColor], seed: UInt64)
}

enum ThemePatternRenderer {
    /// `stripeWidth` nil fits the whole palette across the shape exactly once,
    /// which is what an icon wants — tiling makes the pale first band reappear
    /// in the bottom-right corner and the sunset stops reading as a sunset. A
    /// width tiles the palette, which is what a long strip wants.
    static func fill(_ style: ThemePatternStyle, in path: NSBezierPath, stripeWidth: CGFloat?, starSeed: UInt64? = nil) {
        switch style {
        case .solid(let colour):
            colour.setFill()
            path.fill()

        case .gradient(let colours):
            let locations = (0..<colours.count).map { CGFloat($0) / CGFloat(max(1, colours.count - 1)) }
            locations.withUnsafeBufferPointer {
                NSGradient(colors: colours, atLocations: $0.baseAddress, colorSpace: .sRGB)?
                    .draw(in: path, angle: -45)
            }

        case .twoTone(let colours):
            guard colours.count >= 2 else {
                colours.first?.setFill()
                path.fill()
                return
            }
            colours[0].setFill()
            path.fill()
            guard let context = NSGraphicsContext.current else { return }
            context.saveGraphicsState()
            path.addClip()

            let bounds = path.bounds
            let transform = NSAffineTransform()
            transform.translateX(by: bounds.midX, yBy: bounds.midY)
            transform.rotate(byDegrees: -45)
            transform.concat()

            let extent = (bounds.width + bounds.height) / 2.0.squareRoot()
            let height = extent * 2
            colours[1].setFill()
            CGRect(x: 0, y: -height / 2, width: extent, height: height).fill()
            context.restoreGraphicsState()

        case .stripes(let colours):
            colours.first?.setFill()
            path.fill()
            guard let context = NSGraphicsContext.current else { return }
            context.saveGraphicsState()
            path.addClip()

            // Rotating the context and laying down plain vertical bars is much
            // easier to reason about than working out where each diagonal band
            // meets the edges of a squircle.
            let bounds = path.bounds
            let transform = NSAffineTransform()
            transform.translateX(by: bounds.midX, yBy: bounds.midY)
            transform.rotate(byDegrees: -45)
            transform.concat()

            // Extent of the shape measured along the rotated axis: for a W by H
            // rect turned 45 degrees that is (W + H) / sqrt(2).
            let extent = (bounds.width + bounds.height) / 2.0.squareRoot()
            let height = extent * 2

            if let stripeWidth {
                let total = stripeWidth * CGFloat(colours.count)
                var offset = -extent
                while offset < extent {
                    for (index, colour) in colours.enumerated() {
                        colour.setFill()
                        CGRect(x: offset + CGFloat(index) * stripeWidth, y: -height / 2,
                               width: stripeWidth + 0.5, height: height).fill()
                    }
                    offset += total
                }
            } else {
                let width = extent / CGFloat(colours.count)
                for (index, colour) in colours.enumerated() {
                    colour.setFill()
                    CGRect(x: -extent / 2 + CGFloat(index) * width, y: -height / 2,
                           width: width + 0.5, height: height).fill()
                }
            }
            context.restoreGraphicsState()

        case .polkaDots(let background, let dots):
            drawPolkaDots(in: path, background: background, dots: dots, tiled: stripeWidth != nil)
        case .finePolkaDots(let background, let dots):
            drawPolkaDots(in: path, background: background, dots: dots, explicitSpacing: 15)
        case .packedCircles(let background, let circles, let seed):
            drawPackedCircles(in: path, background: background, colours: circles, seed: seed, tiled: stripeWidth != nil)
        case .triangles(let colours, let seed):
            drawTriangles(in: path, colours: colours, seed: seed, tiled: stripeWidth != nil)
        case .mesh(let colours, let seed):
            drawMesh(in: path, colours: colours, seed: seed, tiled: stripeWidth != nil)
        case .kusamaDots(let background, let dots, let seed):
            drawKusamaDots(in: path, background: background, dots: dots, seed: seed, tiled: stripeWidth != nil)
        case .watercolour(let background, let washes, let seed):
            drawWatercolour(in: path, background: background, washes: washes, seed: seed, tiled: stripeWidth != nil)
        case .diamonds(let background, let diamonds):
            drawDiamonds(in: path, background: background, colours: diamonds, tiled: stripeWidth != nil)
        case .waves(let background, let waves, let spacing, let amplitude):
            drawWaves(in: path, background: background, colours: waves, spacingScale: spacing, amplitudeScale: amplitude, tiled: stripeWidth != nil)
        case .bubbles(let background, let bubbles, let seed):
            drawBubbles(in: path, background: background, colours: bubbles, seed: seed, tiled: stripeWidth != nil)

        case .radial(let colours):
            guard let context = NSGraphicsContext.current else { return }
            context.saveGraphicsState()
            path.addClip()
            let locations = (0..<colours.count).map { CGFloat($0) / CGFloat(max(1, colours.count - 1)) }
            locations.withUnsafeBufferPointer {
                let gradient = NSGradient(colors: colours, atLocations: $0.baseAddress, colorSpace: .sRGB)
                let bounds = path.bounds
                gradient?.draw(fromCenter: CGPoint(x: bounds.midX * 0.82, y: bounds.midY * 1.18), radius: 0,
                               toCenter: CGPoint(x: bounds.midX, y: bounds.midY),
                               radius: hypot(bounds.width, bounds.height) * 0.62, options: [])
            }
            context.restoreGraphicsState()

        case .grain(let background, let shades, let seed):
            drawGrain(in: path, background: background, shades: shades, seed: seed, tiled: stripeWidth != nil)
        }

        if let starSeed {
            scatterStars(in: path, seed: starSeed)
        }
    }

    /// A superellipse, not a rounded rectangle. macOS icon corners are
    /// continuous curves, and a circular-cornered rect next to real app icons
    /// looks wrong.
    static func squircle(in rect: CGRect, exponent: CGFloat = 5) -> NSBezierPath {
        let path = NSBezierPath()
        let a = rect.width / 2, b = rect.height / 2
        let steps = 240
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps) * 2 * .pi
            let ct = cos(t), st = sin(t)
            let x = rect.midX + a * pow(abs(ct), 2 / exponent) * (ct < 0 ? -1 : 1)
            let y = rect.midY + b * pow(abs(st), 2 / exponent) * (st < 0 ? -1 : 1)
            if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.line(to: CGPoint(x: x, y: y)) }
        }
        path.close()
        return path
    }

    // MARK: - Patterns

    /// A small linear congruential generator, seeded per theme: the artwork has
    /// to be identical on every redraw or the icon shimmers.
    private static func generator(_ initialSeed: UInt64) -> () -> CGFloat {
        var seed = initialSeed
        return {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((seed >> 33) % 100_000) / 100_000
        }
    }

    private static func clipped(_ path: NSBezierPath, background: NSColor, draw: (CGRect) -> Void) {
        background.setFill()
        path.fill()
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        path.addClip()
        draw(path.bounds)
        context.restoreGraphicsState()
    }

    private static func drawPolkaDots(in path: NSBezierPath, background: NSColor, dots: [NSColor], tiled: Bool = false, explicitSpacing: CGFloat? = nil) {
        clipped(path, background: background) { bounds in
            let spacing = explicitSpacing ?? (tiled ? CGFloat(24) : bounds.width / 7)
            let radius = spacing * (explicitSpacing == nil ? 0.22 : 0.14)
            var row = 0
            var y = bounds.minY - spacing
            while y < bounds.maxY + spacing {
                var column = 0
                var x = bounds.minX - spacing + (row.isMultiple(of: 2) ? 0 : spacing / 2)
                while x < bounds.maxX + spacing {
                    dots[(row + column) % dots.count].setFill()
                    NSBezierPath(ovalIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)).fill()
                    column += 1
                    x += spacing
                }
                row += 1
                y += spacing
            }
        }
    }

    private static func drawPackedCircles(in path: NSBezierPath, background: NSColor, colours: [NSColor], seed: UInt64, tiled: Bool) {
        clipped(path, background: background) { bounds in
            let random = generator(seed)
            let scale = tiled ? max(bounds.height, 44) : bounds.width
            let target = max(20, Int(bounds.width * bounds.height / (scale * scale) * 90))
            var circles: [(CGPoint, CGFloat)] = []
            for _ in 0..<(target * 12) where circles.count < target {
                let radius = scale * (0.025 + random() * 0.07)
                let centre = CGPoint(x: bounds.minX + random() * bounds.width, y: bounds.minY + random() * bounds.height)
                guard circles.allSatisfy({ hypot($0.0.x - centre.x, $0.0.y - centre.y) > $0.1 + radius + 1 }) else { continue }
                colours[circles.count % colours.count].setFill()
                NSBezierPath(ovalIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)).fill()
                circles.append((centre, radius))
            }
        }
    }

    private static func drawTriangles(in path: NSBezierPath, colours: [NSColor], seed: UInt64, tiled: Bool) {
        clipped(path, background: colours[0]) { bounds in
            let random = generator(seed)
            let cell = tiled ? CGFloat(38) : bounds.width / 5
            var row = 0
            var y = bounds.minY - cell
            while y < bounds.maxY + cell {
                var column = 0
                var x = bounds.minX - cell
                while x < bounds.maxX + cell {
                    let skew = (random() - 0.5) * cell * 0.45
                    let points = [CGPoint(x: x, y: y), CGPoint(x: x + cell, y: y),
                                  CGPoint(x: x + cell + skew, y: y + cell), CGPoint(x: x + skew, y: y + cell)]
                    for indices in [[0, 1, 2], [0, 2, 3]] {
                        colours[(row * 2 + column + indices[1]) % colours.count].setFill()
                        let triangle = NSBezierPath()
                        triangle.move(to: points[indices[0]])
                        triangle.line(to: points[indices[1]])
                        triangle.line(to: points[indices[2]])
                        triangle.close()
                        triangle.fill()
                    }
                    column += 1
                    x += cell
                }
                row += 1
                y += cell
            }
        }
    }

    /// A triangular mesh: a grid of points, each pushed off its lattice
    /// position, with the quad between them split along a diagonal chosen at
    /// random. Jittering the points rather than the cells is what stops it
    /// reading as a pattern — neighbouring triangles share the displaced
    /// corners, so the seams run continuously across the surface.
    private static func drawMesh(in path: NSBezierPath, colours: [NSColor], seed: UInt64, tiled: Bool) {
        clipped(path, background: colours[0]) { bounds in
            let random = generator(seed)
            let cell = tiled ? CGFloat(26) : bounds.width / 7
            let columns = Int(ceil(bounds.width / cell)) + 2
            let rows = Int(ceil(bounds.height / cell)) + 2

            var points: [[CGPoint]] = []
            for row in 0...rows {
                var line: [CGPoint] = []
                for column in 0...columns {
                    line.append(CGPoint(
                        x: bounds.minX - cell + CGFloat(column) * cell + (random() - 0.5) * cell * 0.8,
                        y: bounds.minY - cell + CGFloat(row) * cell + (random() - 0.5) * cell * 0.8))
                }
                points.append(line)
            }

            for row in 0..<rows {
                for column in 0..<columns {
                    let a = points[row][column], b = points[row][column + 1]
                    let c = points[row + 1][column], d = points[row + 1][column + 1]
                    let triangles = random() < 0.5 ? [[a, b, d], [a, d, c]] : [[a, b, c], [b, d, c]]
                    for triangle in triangles {
                        colours[Int(random() * CGFloat(colours.count)) % colours.count].setFill()
                        let shape = NSBezierPath()
                        shape.move(to: triangle[0])
                        shape.line(to: triangle[1])
                        shape.line(to: triangle[2])
                        shape.close()
                        shape.fill()
                        // Stroked in its own colour so the seams close: adjacent
                        // fills otherwise leave hairline gaps where they meet.
                        shape.lineWidth = 0.7
                        shape.stroke()
                    }
                }
            }
        }
    }

    /// Kusama rather than a tablecloth: no lattice, and a size distribution
    /// weighted so most dots are small and a few are very large.
    private static func drawKusamaDots(in path: NSBezierPath, background: NSColor, dots: [NSColor], seed: UInt64, tiled: Bool) {
        clipped(path, background: background) { bounds in
            let random = generator(seed)
            let scale = tiled ? max(bounds.height, 44) : bounds.width
            let count = max(90, Int(bounds.width * bounds.height / (scale * scale) * 380))
            for dot in 0..<count {
                // Raising a uniform value to a power biases it towards zero,
                // giving a field of small dots punctuated by occasional big ones.
                let radius = scale * (0.006 + pow(random(), 2.4) * 0.085)
                let centre = CGPoint(x: bounds.minX + random() * bounds.width, y: bounds.minY + random() * bounds.height)
                dots[dot % dots.count].setFill()
                NSBezierPath(ovalIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)).fill()
            }
        }
    }

    /// Overlapping radial washes, each fading to nothing at its edge, so where
    /// two meet the colour pools the way wet pigment does.
    private static func drawWatercolour(in path: NSBezierPath, background: NSColor, washes: [NSColor], seed: UInt64, tiled: Bool) {
        clipped(path, background: background) { bounds in
            let random = generator(seed)
            let scale = tiled ? max(bounds.height, 44) : bounds.width
            let count = max(16, Int(bounds.width * bounds.height / (scale * scale) * 30))
            for wash in 0..<count {
                let colour = washes[wash % washes.count]
                let radius = scale * (0.12 + random() * 0.30)
                let centre = CGPoint(x: bounds.minX + random() * bounds.width, y: bounds.minY + random() * bounds.height)
                let gradient = NSGradient(colors: [colour.withAlphaComponent(0.30 + random() * 0.24), colour.withAlphaComponent(0)])
                gradient?.draw(fromCenter: centre, radius: 0, toCenter: centre, radius: radius, options: [])
            }
        }
    }

    private static func drawDiamonds(in path: NSBezierPath, background: NSColor, colours: [NSColor], tiled: Bool) {
        clipped(path, background: background) { bounds in
            let width = tiled ? CGFloat(34) : bounds.width / 5
            let height = width * 0.72
            var row = 0
            var y = bounds.minY - height
            while y < bounds.maxY + height {
                var column = 0
                var x = bounds.minX - width + (row.isMultiple(of: 2) ? 0 : width / 2)
                while x < bounds.maxX + width {
                    colours[(row + column) % colours.count].setFill()
                    let diamond = NSBezierPath()
                    diamond.move(to: CGPoint(x: x, y: y + height / 2))
                    diamond.line(to: CGPoint(x: x + width / 2, y: y + height))
                    diamond.line(to: CGPoint(x: x + width, y: y + height / 2))
                    diamond.line(to: CGPoint(x: x + width / 2, y: y))
                    diamond.close()
                    diamond.fill()
                    column += 1
                    x += width
                }
                row += 1
                y += height / 2
            }
        }
    }

    private static func drawWaves(in path: NSBezierPath, background: NSColor, colours: [NSColor], spacingScale: CGFloat, amplitudeScale: CGFloat, tiled: Bool) {
        clipped(path, background: background) { bounds in
            let baseSpacing = tiled ? CGFloat(13) : bounds.height / 11
            let spacing = baseSpacing * spacingScale
            let amplitude = spacing * 0.42 * amplitudeScale
            for row in -2...Int(bounds.height / spacing) + 2 {
                let wave = NSBezierPath()
                wave.lineWidth = max(2, baseSpacing * 0.52)
                var x = bounds.minX - 10
                while x <= bounds.maxX + 10 {
                    let y = bounds.minY + CGFloat(row) * spacing + sin((x - bounds.minX) / spacing * .pi) * amplitude
                    if x == bounds.minX - 10 { wave.move(to: CGPoint(x: x, y: y)) } else { wave.line(to: CGPoint(x: x, y: y)) }
                    x += 4
                }
                colours[(row + colours.count * 2) % colours.count].setStroke()
                wave.stroke()
            }
        }
    }

    private static func drawBubbles(in path: NSBezierPath, background: NSColor, colours: [NSColor], seed: UInt64, tiled: Bool) {
        clipped(path, background: background) { bounds in
            let random = generator(seed)
            let scale = tiled ? max(bounds.height, 44) : bounds.width
            let count = max(24, Int(bounds.width * bounds.height / (scale * scale) * 120))
            for bubble in 0..<count {
                let radius = scale * (0.012 + random() * 0.055)
                let x = bounds.minX + random() * bounds.width
                let y = bounds.minY + random() * bounds.height
                let circle = NSBezierPath(ovalIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                circle.lineWidth = max(1, radius * 0.18)
                colours[bubble % colours.count].setStroke()
                circle.stroke()
            }
        }
    }

    private static func drawGrain(in path: NSBezierPath, background: NSColor, shades: [NSColor], seed: UInt64, tiled: Bool) {
        clipped(path, background: background) { bounds in
            let random = generator(seed)
            let divisor: CGFloat = tiled ? 65 : 220
            let count = Int(bounds.width * bounds.height / divisor)
            let scale = max(1, min(bounds.width, bounds.height) * 0.004)
            for speck in 0..<count {
                let size = scale * (0.4 + random() * 1.8)
                shades[speck % shades.count].withAlphaComponent(0.08 + random() * 0.30).setFill()
                CGRect(x: bounds.minX + random() * bounds.width, y: bounds.minY + random() * bounds.height, width: size, height: size).fill()
            }
        }
    }

    /// Deterministic, so the icon does not shimmer between redraws.
    private static func scatterStars(in path: NSBezierPath, seed: UInt64) {
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        defer { context.restoreGraphicsState() }
        path.addClip()
        let bounds = path.bounds
        let random = generator(seed)
        let count = Int((bounds.width * bounds.height) / 2000)
        for index in 0..<count {
            let x = bounds.minX + random() * bounds.width
            let y = bounds.minY + random() * bounds.height
            let scale = min(bounds.width, max(bounds.height, 300))
            let radius = scale * (0.0012 + random() * 0.0015)
            NSColor(white: 1, alpha: 0.45 + random() * 0.55).setFill()
            if index.isMultiple(of: 4) {
                starPath(at: CGPoint(x: x, y: y), outerRadius: radius * 1.6).fill()
            } else {
                NSBezierPath(ovalIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)).fill()
            }
        }
    }

    private static func starPath(at centre: CGPoint, outerRadius: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let innerRadius = outerRadius * 0.42
        for point in 0..<10 {
            let radius = point.isMultiple(of: 2) ? outerRadius : innerRadius
            let angle = -.pi / 2 + CGFloat(point) * .pi / 5
            let position = CGPoint(x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius)
            if point == 0 { path.move(to: position) } else { path.line(to: position) }
        }
        path.close()
        return path
    }
}
