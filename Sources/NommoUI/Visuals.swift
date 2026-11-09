import NommoKit
import SwiftUI

// MARK: - Backdrop

/// Near-black graphite with a quiet wash of each speaker's colour at the top, fading out well before the controls.
struct AuroraBackground: View {
    /// nil means the speakers run their own cycle, so the wash drifts through the spectrum instead.
    let left: Color?
    let right: Color?
    let level: Double

    @Environment(\.isSnapshot) private var isSnapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: isSnapshot || reduceMotion || left != nil)) { context in
            let hue = isSnapshot ? 0.9 : (context.date.timeIntervalSinceReferenceDate / 12).truncatingRemainder(dividingBy: 1)
            let cycle = Color(hue: hue, saturation: 0.8, brightness: 1)
            let l = left ?? cycle
            let r = right ?? cycle
            Canvas { c, size in
                c.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .linearGradient(Gradient(colors: [Theme.baseTop, Theme.baseBottom]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height))
                )
                let strength = 0.30 + 0.30 * level
                for (color, x) in [(l, 0.22), (r, 0.78)] {
                    let center = CGPoint(x: size.width * x, y: 40)
                    let radius = 230.0
                    c.fill(
                        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                        with: .radialGradient(Gradient(colors: [color.opacity(strength), color.opacity(0)]), center: center, startRadius: 0, endRadius: radius)
                    )
                }
            }
        }
    }
}

// MARK: - Stage

/// The two speakers on a glossy floor, lit by whatever colours they are currently showing.
struct StageView: View {
    let left: RGB?              // nil = the speakers are running their own colour cycle
    let right: RGB?
    let brightness: Double
    let connected: Bool
    let status: String

    @Environment(\.isSnapshot) private var isSnapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            if left == nil, !isSnapshot, !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 20)) { context in
                    let hue = context.date.timeIntervalSinceReferenceDate / 12
                    scene(cycleHue: hue.truncatingRemainder(dividingBy: 1))
                }
            } else {
                scene(cycleHue: 0.9)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Nommo V2 Pro").font(Theme.display(20)).foregroundStyle(Theme.text)
                    .help("Unofficial app, not affiliated with Razer")
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(connected ? Color(hex: 0x5BF08A) : Theme.faint).frame(width: 7, height: 7)
                        .shadow(color: connected ? Color(hex: 0x5BF08A) : .clear, radius: 4)
                    Text(status).font(Theme.caption).foregroundStyle(Theme.text.opacity(0.85)).lineLimit(1)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .surface(radius: 14)
            }
            .padding(.top, 14)
            .padding(.horizontal, 18)
        }
        .frame(height: 150)
    }

    private func colors(cycleHue: Double) -> (Color, Color) {
        if let left, let right { return (Color(rgb: left), Color(rgb: right)) }
        let c = Color(hue: cycleHue, saturation: 0.8, brightness: 1)
        return (c, c)
    }

    private func scene(cycleHue: Double) -> some View {
        let (l, r) = colors(cycleHue: cycleHue)
        let level = connected ? brightness : 0
        let top: CGFloat = 42
        let scale: CGFloat = 0.66
        let height = 142 * scale
        return ZStack(alignment: .top) {
            // Light thrown on the floor.
            HStack(spacing: 34) {
                Ellipse().fill(l).frame(width: 130, height: 20).blur(radius: 16).opacity(0.75 * level)
                Ellipse().fill(r).frame(width: 130, height: 20).blur(radius: 16).opacity(0.75 * level)
            }
            .offset(y: top + height - 10)

            HStack(spacing: 34) {
                SpeakerView(glow: l, level: level)
                SpeakerView(glow: r, level: level)
            }
            .scaleEffect(scale, anchor: .top)
            .offset(y: top)

            // Reflection in the glossy floor.
            HStack(spacing: 34) {
                SpeakerView(glow: l, level: level)
                SpeakerView(glow: r, level: level)
            }
            .scaleEffect(x: scale, y: -scale, anchor: .top)
            .opacity(0.18)
            .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom))
            .offset(y: top + height + 2)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150, alignment: .top)
        .opacity(connected ? 1 : 0.5)
    }
}

/// One Nommo V2 Pro speaker: a matte-black pod with a single full-range driver on a short stem and a flat
/// base. The light is never drawn on the face; it spills out from behind the body and onto the floor.
struct SpeakerView: View {
    let glow: Color
    let level: Double

    private let shape = RoundedRectangle(cornerRadius: 52, style: .continuous)

    var body: some View {
        ZStack(alignment: .top) {
            // Light spilling out from behind the speaker.
            shape.fill(glow)
                .frame(width: 104, height: 118)
                .blur(radius: 20)
                .scaleEffect(1.1)
                .opacity(0.75 * level)

            // Base plate and stem.
            Ellipse()
                .fill(LinearGradient(colors: [Color(hex: 0x2A2832), Color(hex: 0x0B0A10)], startPoint: .top, endPoint: .bottom))
                .frame(width: 110, height: 10)
                .overlay(Ellipse().strokeBorder(glow.opacity(0.5 * level + 0.1), lineWidth: 1))
                .shadow(color: glow.opacity(0.9 * level), radius: 9, y: 3)
                .offset(y: 128)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x23212B), Color(hex: 0x0B0A10)], startPoint: .leading, endPoint: .trailing))
                .frame(width: 26, height: 26)
                .offset(y: 106)

            // Matte body with a thin rim of backlight.
            shape.fill(LinearGradient(colors: [Color(hex: 0x2B2933), Color(hex: 0x0D0C12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 102, height: 116)
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.18), glow.opacity(0.25 + 0.65 * level)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1.4
                    )
                }
                .shadow(color: .black.opacity(0.5), radius: 8, y: 6)

            // Front: bezel, surround, cone and dust cap. All neutral black, as on the real speaker.
            ZStack {
                Circle().fill(LinearGradient(colors: [Color(hex: 0x34323D), Color(hex: 0x15141B)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 88, height: 88)
                    .overlay(Circle().strokeBorder(.white.opacity(0.08), lineWidth: 1))
                Circle().fill(Color(hex: 0x0E0D13)).frame(width: 68, height: 68)
                    .overlay(Circle().strokeBorder(.white.opacity(0.10), lineWidth: 1.5))
                Circle().fill(RadialGradient(colors: [Color(hex: 0x25232C), Color(hex: 0x0A090E)], center: .topLeading, startRadius: 0, endRadius: 48))
                    .frame(width: 54, height: 54)
                    .overlay(Circle().strokeBorder(.white.opacity(0.05), lineWidth: 1))
                    .overlay(Circle().strokeBorder(.white.opacity(0.04), lineWidth: 1).padding(9))
                Circle().fill(RadialGradient(colors: [Color(hex: 0x403D4B), Color(hex: 0x0C0B11)], center: .topLeading, startRadius: 0, endRadius: 12))
                    .frame(width: 17, height: 17)
                    .overlay(Circle().strokeBorder(.white.opacity(0.10), lineWidth: 0.8))
            }
            .offset(y: 15)

            Capsule().fill(LinearGradient(colors: [.white.opacity(0.16), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(width: 32, height: 4).rotationEffect(.degrees(-38)).offset(x: -28, y: 13)
        }
        .frame(width: 116, height: 142, alignment: .top)
    }
}

// MARK: - EQ curve

/// The equaliser as a response curve: a glowing line through ten draggable points, over a wash that fades towards the
/// bottom, with the dB range at the left and the band frequencies underneath. Frequency is colour-coded from warm
/// bass to cool treble, like a spectrum analyser.
struct EQCurve: View {
    let values: [Double]
    /// False draws the curve only, for a style the speaker plays but that isn't being edited.
    var editable = true
    @Binding var activeBand: Int?
    let onChange: (Int, Double) -> Void

    /// One colour per band, low to high: red-orange bass, through green and cyan mids, to violet treble.
    static let bandColors: [Color] = [
        Color(hex: 0xFF4D5E), Color(hex: 0xFF7A45), Color(hex: 0xFFA630), Color(hex: 0xFFD23F), Color(hex: 0x7BE15C),
        Color(hex: 0x2FD6A5), Color(hex: 0x2EC4F5), Color(hex: 0x4C8DFF), Color(hex: 0x8A6BFF), Color(hex: 0xD35CFF),
    ]

    private let maxDB = EQ.maxDecibels
    /// Room above +12 dB and below -12 dB for the points and the glow.
    private let inset: CGFloat = 12
    /// Room at the left for the dB labels.
    private let gutter: CGFloat = 46

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in plot(size: geo.size) }
            HStack(spacing: 0) {
                ForEach(Array(EQ.frequencies.enumerated()), id: \.offset) { index, hz in
                    Text(EQ.label(for: hz))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Self.bandColors[index].opacity(activeBand == index ? 1 : 0.85))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.leading, gutter)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Equaliser curve")
        .accessibilityValue(zip(EQ.frequencies, values).map { "\(EQ.label(for: $0)) Hz \(Int($1)) dB" }.joined(separator: ", "))
    }

    private func plot(size: CGSize) -> some View {
        let column = (size.width - gutter) / CGFloat(values.count)
        let midY = size.height / 2
        let travel = midY - inset

        return ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                let colors = Self.bandColors
                let top = inset, bottom = size.height - inset
                let points = values.indices.map { i in
                    CGPoint(x: gutter + column * (CGFloat(i) + 0.5), y: midY - CGFloat(values[i] / maxDB) * travel)
                }

                var zero = Path()
                zero.move(to: CGPoint(x: gutter, y: midY)); zero.addLine(to: CGPoint(x: size.width, y: midY))
                context.stroke(zero, with: .color(.white.opacity(0.16)), lineWidth: 1)

                for (i, p) in points.enumerated() {
                    var line = Path()
                    line.move(to: CGPoint(x: p.x, y: top - 4)); line.addLine(to: CGPoint(x: p.x, y: bottom + 4))
                    context.stroke(line, with: .color(colors[i].opacity(activeBand == i ? 0.7 : 0.16)), lineWidth: 1)
                }

                guard let first = points.first, let last = points.last, points.count > 1, colors.count == points.count else { return }
                let curve = Self.smoothPath(points)
                // One gradient runs along the curve from the first band to the last, so frequency is its colour.
                let spectrum = GraphicsContext.Shading.linearGradient(
                    Gradient(stops: colors.enumerated().map { .init(color: $1, location: CGFloat($0) / CGFloat(colors.count - 1)) }),
                    startPoint: CGPoint(x: first.x, y: 0), endPoint: CGPoint(x: last.x, y: 0)
                )

                // The wash takes the spectrum colours and fades towards the bottom: fill it, then erase more of it lower down.
                var wash = curve
                wash.addLine(to: CGPoint(x: last.x, y: bottom)); wash.addLine(to: CGPoint(x: first.x, y: bottom)); wash.closeSubpath()
                context.drawLayer { layer in
                    layer.fill(wash, with: spectrum)
                    layer.blendMode = .destinationOut
                    layer.fill(Path(CGRect(x: 0, y: top, width: size.width, height: bottom - top)), with: .linearGradient(
                        Gradient(stops: [
                            .init(color: .black.opacity(0.22), location: 0),
                            .init(color: .black.opacity(0.56), location: 0.5),
                            .init(color: .black, location: 1),
                        ]),
                        startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom)
                    ))
                }

                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: 6))
                    layer.opacity = 0.85
                    layer.stroke(curve, with: spectrum, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                }
                context.stroke(curve, with: spectrum, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))

                for (i, p) in points.enumerated() {
                    let r: CGFloat = activeBand == i ? 7.5 : 5.5
                    if activeBand == i {
                        context.fill(Path(ellipseIn: CGRect(x: p.x - r - 5, y: p.y - r - 5, width: (r + 5) * 2, height: (r + 5) * 2)), with: .color(colors[i].opacity(0.35)))
                    }
                    let dot = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: dot), with: .color(.white))
                    context.stroke(Path(ellipseIn: dot.insetBy(dx: 0.5, dy: 0.5)), with: .color(colors[i]), lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let band = activeBand ?? band(at: drag.startLocation.x, column: column)
                        activeBand = band
                        let db = Double((midY - drag.location.y) / travel) * maxDB
                        onChange(band, min(max(db, -maxDB), maxDB).rounded())
                    }
                    .onEnded { _ in activeBand = nil },
                including: editable ? .all : .none
            )
            .simultaneousGesture(
                SpatialTapGesture(count: 2).onEnded { tap in onChange(band(at: tap.location.x, column: column), 0) },
                including: editable ? .all : .none
            )

            axisLabel("+12 dB").position(x: (gutter - 8) / 2, y: inset)
            axisLabel("0").position(x: (gutter - 8) / 2, y: midY)
            axisLabel("\u{2212}12 dB").position(x: (gutter - 8) / 2, y: size.height - inset)
        }
        .allowsHitTesting(editable)
    }

    private func axisLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(Theme.dim)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: gutter - 8, alignment: .trailing)
            .allowsHitTesting(false)
    }

    private func band(at x: CGFloat, column: CGFloat) -> Int {
        min(max(Int((x - gutter) / column), 0), values.count - 1)
    }

    /// Catmull-Rom spline through the points, as cubic Béziers.
    static func smoothPath(_ p: [CGPoint]) -> Path {
        var path = Path()
        path.move(to: p[0])
        for i in 0 ..< p.count - 1 {
            let p0 = i > 0 ? p[i - 1] : p[i], p1 = p[i], p2 = p[i + 1], p3 = i + 2 < p.count ? p[i + 2] : p[i + 1]
            path.addCurve(
                to: p2,
                control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            )
        }
        return path
    }
}

// MARK: - Stereo image

/// A top-down view: you at the bottom, the speakers at the top, and the width of the sound stage between
/// them. It grows as the effect gets stronger.
struct SpaceDiagram: View {
    let enabled: Bool
    let mode: SpatialMode
    let amount: Double
    @Environment(\.accent) private var accent

    var body: some View {
        Canvas { context, size in
            let cx = size.width / 2
            let spread: CGFloat = 70
            let speakerY: CGFloat = 18
            let listener = CGPoint(x: cx, y: size.height - 14)
            let alpha: Double = enabled ? 1 : 0.35
            let color = accent.color

            // Sound radiating from each speaker.
            for side in [-1.0, 1.0] {
                let origin = CGPoint(x: cx + CGFloat(side) * spread, y: speakerY + 4)
                for ring in 1 ... 4 {
                    var arc = Path()
                    arc.addArc(center: origin, radius: CGFloat(ring) * 24, startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false)
                    context.stroke(arc, with: .color(color.opacity((0.34 - 0.07 * Double(ring)) * alpha)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                }
            }

            // The stage: how far left and right the sound appears to come from.
            let reach = mode == .immersive ? 1.1 : 0.45
            let half = min(size.width / 2 - 10, spread * (1 + CGFloat(amount * reach)))
            let baseY = speakerY + 56
            var stage = Path()
            stage.move(to: CGPoint(x: cx - half, y: baseY + 6))
            stage.addQuadCurve(to: CGPoint(x: cx + half, y: baseY + 6), control: CGPoint(x: cx, y: baseY - 28))
            context.stroke(stage, with: .linearGradient(
                Gradient(colors: [color.opacity(0), color.opacity(alpha), color.opacity(0)]),
                startPoint: CGPoint(x: cx - half, y: 0), endPoint: CGPoint(x: cx + half, y: 0)
            ), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            for t in stride(from: 0.1, through: 0.9, by: 0.16) {
                let tt = CGFloat(t)
                let x = cx - half + tt * 2 * half
                let y = (1 - tt) * (1 - tt) * (baseY + 6) + 2 * (1 - tt) * tt * (baseY - 28) + tt * tt * (baseY + 6)
                context.fill(Path(ellipseIn: CGRect(x: x - 2.5, y: y - 2.5, width: 5, height: 5)), with: .color(.white.opacity(0.9 * alpha)))
            }

            // Speakers and listener.
            for side in [-1.0, 1.0] {
                let rect = CGRect(x: cx + CGFloat(side) * spread - 11, y: speakerY - 11, width: 22, height: 22)
                context.fill(Path(ellipseIn: rect), with: .color(Color(hex: 0x1D1E24)))
                context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.35 * alpha)), lineWidth: 1.2)
                context.fill(Path(ellipseIn: rect.insetBy(dx: 7, dy: 7)), with: .color(.white.opacity(0.25 * alpha)))
                var line = Path()
                line.move(to: listener)
                line.addLine(to: CGPoint(x: cx + CGFloat(side) * spread, y: speakerY + 12))
                context.stroke(line, with: .color(.white.opacity(0.12 * alpha)), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
            }
            context.stroke(Path(ellipseIn: CGRect(x: listener.x - 6, y: listener.y - 6, width: 12, height: 12)), with: .color(.white.opacity(0.85)), lineWidth: 1.6)
            context.fill(Path(ellipseIn: CGRect(x: listener.x - 2.5, y: listener.y - 2.5, width: 5, height: 5)), with: .color(.white))
        }
        .frame(height: 104)
        .accessibilityHidden(true)
    }
}
