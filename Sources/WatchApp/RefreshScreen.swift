import SwiftUI

/// The full-window curtain that goes up while a refresh runs — the reading
/// equivalent of a title card. A refresh clears `stories` and refills it a
/// source at a time, so without this the feed visibly empties, shuffles as
/// each source lands, and reshuffles again when the ranker scores the batch;
/// covering that and revealing a settled page 1 at the end turns a minute of
/// churn into one deliberate pause.
///
/// The scene is drawn rather than shipped as artwork: a single `Canvas`
/// costs nothing next to bundling images, recolors itself from whatever
/// theme is active, and scales to any window size. Everything animates off
/// one clock so the drift stays coherent — clouds and seeds crossing at
/// their own speeds, nothing looping in lockstep.
struct RefreshScreen: View {
    let status: String?
    let progress: Double
    let skip: () -> Void

    @Environment(\.readerTheme) private var theme
    @State private var startedAt = Date()

    var body: some View {
        ZStack {
            theme.texturedPaper
                .ignoresSafeArea()

            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                Canvas { context, size in
                    let elapsed = timeline.date.timeIntervalSince(startedAt)
                    draw(in: &context, size: size, time: elapsed)
                } symbols: {
                    // Resolved as a symbol rather than stroked by hand: it
                    // keeps the tint and weight of a real view while still
                    // being positioned off the same clock as everything else.
                    CandleMark(height: 74, opacity: 0.8)
                        .tag(Self.horseSymbol)
                }
            }
            .ignoresSafeArea()

            statusPanel
        }
        .preferredColorScheme(.light)
    }

    private var statusPanel: some View {
        VStack(spacing: 14) {
                Text("Gathering your stories")
                    .font(ReaderTheme.serif(24, weight: .semibold))
                    .embossedText()
                .foregroundStyle(theme.ink)

                Text(status ?? "Waking up the sources…")
                    .font(ReaderTheme.sans(13))
                    .embossedText()
                .foregroundStyle(theme.inkSecondary)
                .animation(nil, value: status)

            ProgressTrack(progress: progress)
                .frame(width: 220, height: 4)

            // A refresh can sit on a slow source for a while, and a curtain
            // with no way out is a worse deal than a half-filled feed —
            // this drops you straight to the stories already in, and the
            // rest keep filling in behind you the way they always did.
            Button("Skip to the feed", action: skip)
                .buttonStyle(.plain)
                .font(ReaderTheme.sans(12, weight: .medium))
                .foregroundStyle(theme.inkSecondary)
                .padding(.top, 2)
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 30)
        .background(theme.paper.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(theme.rule.opacity(0.7), lineWidth: 1)
        )
    }

    // MARK: - Scene

    private func draw(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let horizon = size.height * 0.72
        drawStars(in: &context, size: size, horizon: horizon, time: time)
        drawSun(in: &context, size: size, time: time)
        drawPlanet(in: &context, size: size, time: time)
        drawHills(in: &context, size: size, horizon: horizon)
        drawTrees(in: &context, size: size, horizon: horizon, time: time)
        drawDandelions(in: &context, size: size, horizon: horizon, time: time)
        drawHorse(in: &context, size: size, horizon: horizon, time: time)
        drawDust(in: &context, size: size, time: time)
    }

    /// Fixed pseudo-random layout from a plain hash rather than `random()`:
    /// the scene has to land in the same place on every frame, and a seeded
    /// hash gives scattered-looking positions that are still stable.
    private func jitter(_ seed: Int, _ salt: Int = 0) -> Double {
        let value = sin(Double(seed) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return value - value.rounded(.down)
    }

    private func drawStars(in context: inout GraphicsContext, size: CGSize, horizon: Double, time: TimeInterval) {
        for index in 0..<26 {
            let x = jitter(index, 1) * size.width
            let y = jitter(index, 2) * horizon * 0.8
            let twinkle = 0.18 + 0.22 * (0.5 + 0.5 * sin(time * 1.4 + Double(index)))
            let radius = 1.0 + jitter(index, 3) * 1.4
            context.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius)),
                with: .color(theme.inkSecondary.opacity(twinkle))
            )
        }
    }

    private func drawSun(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let center = CGPoint(x: size.width * 0.79, y: size.height * 0.2)
        let radius = min(size.width, size.height) * 0.055

        // The glow is drawn in `rule` rather than `headerTint`: in the
        // greyscale theme the header tint *is* the paper colour, so a
        // tint-on-paper glow renders as nothing at all.
        for ring in stride(from: 3.0, through: 1.0, by: -1.0) {
            let glow = radius * (1 + ring * 0.55)
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - glow, y: center.y - glow, width: glow * 2, height: glow * 2)),
                with: .color(theme.rule.opacity(0.13))
            )
        }

        var rays = Path()
        let rayCount = 12
        for index in 0..<rayCount {
            let angle = Double(index) / Double(rayCount) * 2 * .pi + time * 0.12
            let inner = radius * 1.35
            let outer = radius * (1.75 + 0.12 * sin(time * 1.1 + Double(index)))
            rays.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
            rays.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
        }
        context.stroke(rays, with: .color(theme.inkSecondary.opacity(0.5)), style: StrokeStyle(lineWidth: 2, lineCap: .round))

        context.fill(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .color(theme.headerTint)
        )
        context.stroke(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .color(theme.inkSecondary.opacity(0.55)),
            lineWidth: 1.5
        )
    }

    private func drawPlanet(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let center = CGPoint(x: size.width * 0.16, y: size.height * 0.15 + sin(time * 0.5) * 4)
        let radius = min(size.width, size.height) * 0.028

        context.drawLayer { layer in
            layer.translateBy(x: center.x, y: center.y)
            layer.rotate(by: .degrees(-18))
            let ring = CGRect(x: -radius * 2.1, y: -radius * 0.42, width: radius * 4.2, height: radius * 0.84)
            layer.stroke(Path(ellipseIn: ring), with: .color(theme.inkSecondary.opacity(0.55)), lineWidth: 1.6)
        }

        context.fill(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .color(theme.rule)
        )
        context.stroke(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .color(theme.inkSecondary.opacity(0.55)),
            lineWidth: 1.5
        )
    }

    private func drawHills(in context: inout GraphicsContext, size: CGSize, horizon: Double) {
        var back = Path()
        back.move(to: CGPoint(x: 0, y: horizon + 26))
        back.addQuadCurve(to: CGPoint(x: size.width * 0.52, y: horizon + 14), control: CGPoint(x: size.width * 0.26, y: horizon - 46))
        back.addQuadCurve(to: CGPoint(x: size.width, y: horizon + 22), control: CGPoint(x: size.width * 0.8, y: horizon - 38))
        back.addLine(to: CGPoint(x: size.width, y: size.height))
        back.addLine(to: CGPoint(x: 0, y: size.height))
        back.closeSubpath()
        context.fill(back, with: .color(theme.rule.opacity(0.5)))

        var front = Path()
        front.move(to: CGPoint(x: 0, y: horizon + 64))
        front.addQuadCurve(to: CGPoint(x: size.width * 0.62, y: horizon + 52), control: CGPoint(x: size.width * 0.3, y: horizon + 6))
        front.addQuadCurve(to: CGPoint(x: size.width, y: horizon + 70), control: CGPoint(x: size.width * 0.85, y: horizon + 18))
        front.addLine(to: CGPoint(x: size.width, y: size.height))
        front.addLine(to: CGPoint(x: 0, y: size.height))
        front.closeSubpath()
        context.fill(front, with: .color(theme.rule.opacity(0.8)))
    }

    private func drawTrees(in context: inout GraphicsContext, size: CGSize, horizon: Double, time: TimeInterval) {
        let pines: [(Double, Double)] = [(0.08, 1.0), (0.15, 0.72), (0.72, 0.86), (0.88, 1.05)]
        for (index, (fraction, scale)) in pines.enumerated() {
            let base = CGPoint(x: size.width * fraction, y: horizon + 30 - jitter(index, 21) * 8)
            drawPine(in: &context, base: base, scale: scale, sway: sin(time * 0.7 + Double(index)) * 0.9)
        }

        let rounds: [(Double, Double)] = [(0.3, 0.9), (0.45, 0.66), (0.6, 0.8)]
        for (index, (fraction, scale)) in rounds.enumerated() {
            let base = CGPoint(x: size.width * fraction, y: horizon + 34 - jitter(index, 22) * 6)
            drawRoundTree(in: &context, base: base, scale: scale, sway: sin(time * 0.6 + Double(index) * 1.7) * 1.1)
        }
    }

    private func drawPine(in context: inout GraphicsContext, base: CGPoint, scale: Double, sway: Double) {
        let height = 58.0 * scale
        let width = 30.0 * scale

        var trunk = Path()
        trunk.addRect(CGRect(x: base.x - 2 * scale, y: base.y - height * 0.22, width: 4 * scale, height: height * 0.22))
        context.fill(trunk, with: .color(theme.inkSecondary.opacity(0.75)))

        for tier in 0..<3 {
            let tierScale = 1.0 - Double(tier) * 0.22
            let tierBase = base.y - height * (0.18 + Double(tier) * 0.26)
            let tierHeight = height * 0.42 * tierScale
            var triangle = Path()
            triangle.move(to: CGPoint(x: base.x + sway * Double(tier + 1) * 0.5, y: tierBase - tierHeight))
            triangle.addLine(to: CGPoint(x: base.x - width * tierScale / 2, y: tierBase))
            triangle.addLine(to: CGPoint(x: base.x + width * tierScale / 2, y: tierBase))
            triangle.closeSubpath()
            context.fill(triangle, with: .color(theme.inkSecondary.opacity(0.62)))
        }
    }

    private func drawRoundTree(in context: inout GraphicsContext, base: CGPoint, scale: Double, sway: Double) {
        let trunkHeight = 22.0 * scale
        var trunk = Path()
        trunk.addRect(CGRect(x: base.x - 2.2 * scale, y: base.y - trunkHeight, width: 4.4 * scale, height: trunkHeight))
        context.fill(trunk, with: .color(theme.inkSecondary.opacity(0.75)))

        let radius = 20.0 * scale
        let center = CGPoint(x: base.x + sway, y: base.y - trunkHeight - radius * 0.7)
        var canopy = Path()
        canopy.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius * 0.9, width: radius * 2, height: radius * 1.8))
        canopy.addEllipse(in: CGRect(x: center.x - radius * 1.1, y: center.y - radius * 0.2, width: radius * 1.2, height: radius * 1.1))
        canopy.addEllipse(in: CGRect(x: center.x + radius * 0.1, y: center.y - radius * 0.3, width: radius * 1.15, height: radius * 1.1))
        context.fill(canopy, with: .color(theme.inkSecondary.opacity(0.55)))
    }

    private func drawDandelions(in context: inout GraphicsContext, size: CGSize, horizon: Double, time: TimeInterval) {
        // Rooted just below the horizon and only as tall as the foreground
        // band. Earlier versions ran a hairline stem up from the very bottom
        // of the window, which at any real window height drew a wire from
        // floor to sky rather than a flower standing in the grass.
        let stems: [(Double, Double)] = [(0.13, 0.9), (0.21, 1.0), (0.33, 0.66), (0.71, 0.78), (0.86, 1.0)]
        for (index, (fraction, scale)) in stems.enumerated() {
            let base = CGPoint(x: size.width * fraction, y: size.height * 0.97)
            let height = (size.height - horizon) * 0.62 * scale
            let sway = sin(time * 0.9 + Double(index) * 2.1) * 5 * scale
            let head = CGPoint(x: base.x + sway, y: base.y - height)

            var stem = Path()
            stem.move(to: base)
            stem.addQuadCurve(to: head, control: CGPoint(x: base.x + sway * 0.3, y: base.y - height * 0.55))
            context.stroke(stem, with: .color(theme.inkSecondary.opacity(0.72)), style: StrokeStyle(lineWidth: 3.2 * scale, lineCap: .round))

            for side in [-1.0, 1.0] {
                let leafRoot = CGPoint(x: base.x + sway * 0.1, y: base.y - height * (0.16 + 0.1 * (side + 1) / 2))
                var leaf = Path()
                leaf.move(to: leafRoot)
                leaf.addQuadCurve(
                    to: CGPoint(x: leafRoot.x + side * 22 * scale, y: leafRoot.y - 4 * scale),
                    control: CGPoint(x: leafRoot.x + side * 12 * scale, y: leafRoot.y - 15 * scale)
                )
                leaf.addQuadCurve(
                    to: leafRoot,
                    control: CGPoint(x: leafRoot.x + side * 11 * scale, y: leafRoot.y + 5 * scale)
                )
                context.fill(leaf, with: .color(theme.inkSecondary.opacity(0.5)))
            }

            // A half-blown clock: seeds still attached on one side, gaps on
            // the other where the ones drifting up the screen came from.
            let radius = 17.0 * scale
            var filaments = Path()
            for spoke in 0..<16 {
                let angle = Double(spoke) / 16 * 2 * .pi
                guard jitter(index * 31 + spoke, 41) > 0.28 else {
                    continue
                }
                let tip = CGPoint(x: head.x + cos(angle) * radius, y: head.y + sin(angle) * radius)
                filaments.move(to: head)
                filaments.addLine(to: tip)
                filaments.addEllipse(in: CGRect(x: tip.x - 1.3 * scale, y: tip.y - 1.3 * scale, width: 2.6 * scale, height: 2.6 * scale))
            }
            context.stroke(filaments, with: .color(theme.inkSecondary.opacity(0.45)), lineWidth: 1)
            context.fill(
                Path(ellipseIn: CGRect(x: head.x - 2.4 * scale, y: head.y - 2.4 * scale, width: 4.8 * scale, height: 4.8 * scale)),
                with: .color(theme.inkSecondary.opacity(0.8))
            )
        }
    }

    private static let horseSymbol = "horse"

    /// One horse in the foreground grass, at a canter. It sits between the
    /// dandelions rather than on the ridge line, so it reads as near the
    /// viewer and doesn't collide with the trees along the back hill.
    private func drawHorse(in context: inout GraphicsContext, size: CGSize, horizon: Double, time: TimeInterval) {
        guard let horse = context.resolveSymbol(id: Self.horseSymbol) else {
            return
        }
        let stride = abs(sin(time * 0.9)) * 3.5
        // Low in the foreground, so it lands at roughly the same height in the
        // window as the horse on the lock screen.
        let ground = horizon + (size.height - horizon) * 0.88
        context.draw(horse, at: CGPoint(x: size.width * 0.52, y: ground - stride), anchor: .bottom)
    }

    /// Dust motes: a slow upward drift of very small specks, closer to
    /// moving film grain than to anything in the scene. Enough of them, small
    /// enough and faint enough, that they read as texture over the whole
    /// window rather than as objects — each on its own speed and phase so the
    /// field never pulses in unison.
    private func drawDust(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let travel = size.height + 60
        for index in 0..<220 {
            let speed = 3.5 + jitter(index, 51) * 11.0
            let raw = (jitter(index, 52) * travel + time * speed).truncatingRemainder(dividingBy: travel)
            let y = size.height + 30 - raw
            let drift = sin(time * 0.35 + Double(index) * 0.7) * 12
            let x = (jitter(index, 53) * size.width + drift).truncatingRemainder(dividingBy: size.width)
            // Weighted towards the small end rather than spread evenly, so
            // the field still reads as grain but has the occasional larger
            // mote drifting through it instead of one uniform speck size.
            let radius = 0.6 + pow(jitter(index, 54), 1.9) * 2.9
            // Fades in off the bottom edge and out again at the top, so motes
            // arrive and leave instead of popping.
            let edgeFade = min(1, raw / 120) * min(1, (travel - raw) / 160)
            let shimmer = 0.55 + 0.45 * sin(time * 1.6 + Double(index) * 2.3)
            let opacity = (0.1 + jitter(index, 55) * 0.26) * edgeFade * shimmer

            context.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
                with: .color(theme.inkSecondary.opacity(opacity))
            )
        }
    }
}

/// A plain two-layer capsule rather than `ProgressView` — the system bar
/// brings its own blue-tinted material that fights every theme palette.
private struct ProgressTrack: View {
    let progress: Double

    @Environment(\.readerTheme) private var theme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.rule.opacity(0.6))
                Capsule()
                    .fill(theme.ink.opacity(0.55))
                    .frame(width: max(4, geo.size.width * min(max(progress, 0), 1)))
            }
        }
        .animation(.easeOut(duration: 0.25), value: progress)
    }
}
