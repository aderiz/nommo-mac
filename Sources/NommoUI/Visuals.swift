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

// MARK: - EQ faders

/// Ten faders in the accent colour, with the response curve drawn smoothly through their thumbs.
struct FaderBank: View {
    let values: [Double]
    @Binding var activeBand: Int?
    let onChange: (Int, Double) -> Void
    @Environment(\.accent) private var accent

    private let maxDB = EQ.maxDecibels
    private let inset: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let columnWidth = size.width / CGFloat(values.count)
            let color = accent.color

            Canvas { context, _ in
                let midY = size.height / 2
                let travel = midY - inset
                func position(_ i: Int) -> CGPoint {
                    CGPoint(x: columnWidth * (CGFloat(i) + 0.5), y: midY - CGFloat(values[i] / maxDB) * travel)
                }

                for (db, alpha) in [(6.0, 0.05), (0.0, 0.20), (-6.0, 0.05)] {
                    var line = Path()
                    let y = midY - CGFloat(db / maxDB) * travel
                    line.move(to: CGPoint(x: 2, y: y)); line.addLine(to: CGPoint(x: size.width - 2, y: y))
                    context.stroke(line, with: .color(.white.opacity(alpha)), style: StrokeStyle(lineWidth: 1, dash: db == 0 ? [] : [2, 5]))
                }

                for i in values.indices {
                    let p = position(i)
                    var track = Path()
                    track.move(to: CGPoint(x: p.x, y: inset - 6)); track.addLine(to: CGPoint(x: p.x, y: size.height - inset + 6))
                    context.stroke(track, with: .color(.white.opacity(0.07)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    var fill = Path()
                    fill.move(to: CGPoint(x: p.x, y: midY)); fill.addLine(to: p)
                    context.stroke(fill, with: .color(color), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                }

                let points = values.indices.map(position)
                if points.count > 1 {
                    let curve = Self.smoothPath(points)
                    var wash = curve
                    wash.addLine(to: CGPoint(x: points[points.count - 1].x, y: midY)); wash.addLine(to: CGPoint(x: points[0].x, y: midY)); wash.closeSubpath()
                    var washLayer = context
                    washLayer.opacity = 0.14
                    washLayer.fill(wash, with: .color(color))
                    context.stroke(curve, with: .color(color.opacity(0.9)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                }

                for i in values.indices {
                    let p = position(i)
                    let r: CGFloat = (activeBand == i) ? 8.5 : 7
                    let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                    if activeBand == i {
                        context.fill(Path(ellipseIn: rect.insetBy(dx: -5, dy: -5)), with: .color(color.opacity(0.28)))
                    }
                    context.fill(Path(ellipseIn: rect), with: .color(.white))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let band = activeBand ?? min(max(Int(drag.startLocation.x / columnWidth), 0), values.count - 1)
                        activeBand = band
                        let midY = size.height / 2
                        let db = Double((midY - drag.location.y) / (midY - inset)) * maxDB
                        onChange(band, min(max(db, -maxDB), maxDB).rounded())
                    }
                    .onEnded { _ in activeBand = nil }
            )
            .simultaneousGesture(
                SpatialTapGesture(count: 2).onEnded { tap in
                    onChange(min(max(Int(tap.location.x / columnWidth), 0), values.count - 1), 0)
                }
            )
        }
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
