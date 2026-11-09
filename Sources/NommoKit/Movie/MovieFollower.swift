import Foundation

public struct MovieSettings: Codable, Equatable, Sendable {
    /// 0...1. How strongly the lights show the scene: brighter and more saturated as it rises.
    public var intensity: Double
    /// 0...1. How slowly the lights settle after a change. Flashes still rise at once.
    public var smoothness: Double

    public static let standard = MovieSettings()

    public init(intensity: Double = 0.5, smoothness: Double = 0.5) {
        self.intensity = intensity
        self.smoothness = smoothness
    }
}

/// What is driving the lights.
public enum MovieSource: Equatable, Sendable {
    /// Colours taken from the screen.
    case picture
    /// The screen cannot be read (protected video, or nothing on it), so the lights follow the soundtrack.
    case soundtrack
}

public struct MovieFrame: Equatable, Sendable {
    public var left: RGB
    public var right: RGB
    public var source: MovieSource
}

/// Turns a stream of `SceneSample`s (and audio levels as a fallback) into smooth colours for the two speakers.
///
/// - Brightness rises almost instantly and falls slowly; colour settles more slowly than brightness.
/// - A hard cut in the picture snaps to the new look instead of fading through the old one.
/// - Dark scenes dim the light and keep their colour, rather than switching it off.
/// - A flash limiter caps how much the brightness can swing in a second.
/// - When the screen reads as blank for a moment, the lights follow the soundtrack: left and right levels drive
///   each speaker, and loud low-frequency impacts flare from a cool ambient blue through amber to white.
public struct MovieFollower: Sendable {
    public var settings: MovieSettings
    /// The most the brightness of one speaker may move, in total, over any second (1 = one full swing up or down).
    public var flashLimit: Float = 6
    /// LEDs are driven roughly linearly, so linear light is encoded with this gamma on the way out.
    public var ledGamma: Float = 1.8
    /// Seconds the screen must stay blank before the soundtrack takes over.
    public var blankHold: Double = 1.5

    private struct Side: Sendable {
        var level: Float = 0
        var direction = SIMD3<Float>(1, 1, 1)
        var swings: [(time: Double, amount: Float)] = []
    }

    private struct Target {
        var level: Float
        /// Colour with its brightest channel at 1, or nil when too dark to tell.
        var direction: SIMD3<Float>?
    }

    private var left = Side()
    private var right = Side()
    private var clock = 0.0
    private var previous: SceneSample?
    private var blankFor = 0.0
    private var primed = false
    private var source = MovieSource.picture

    public init(settings: MovieSettings = .standard) {
        self.settings = settings
    }

    public mutating func step(scene: SceneSample?, audio: AudioLevels, dt rawDt: Double) -> MovieFrame {
        let dt = min(max(rawDt, 0.005), 0.25)
        clock += dt

        let readable = scene.map { !$0.isBlank } ?? false
        blankFor = readable ? 0 : blankFor + dt
        if blankFor >= blankHold { source = .soundtrack } else if readable { source = .picture }

        let intensity = Float(min(max(settings.intensity, 0), 1))
        var targets: (Target?, Target?) = (nil, nil)
        var cut = false
        if source == .soundtrack {
            targets = (
                Self.soundtrack(audio.left, intensity: intensity), Self.soundtrack(audio.right, intensity: intensity)
            )
        } else if let scene, readable {
            targets = (Self.picture(scene.left, intensity: intensity), Self.picture(scene.right, intensity: intensity))
            cut = isCut(scene)
            previous = scene
        }

        let smoothness = min(max(settings.smoothness, 0), 1)
        let releaseTau = 0.15 + 0.9 * smoothness
        let directionTau = source == .soundtrack ? 0.1 : 0.1 + 0.8 * smoothness
        left = advance(left, to: targets.0, cut: cut, dt: dt, releaseTau: releaseTau, directionTau: directionTau)
        right = advance(right, to: targets.1, cut: cut, dt: dt, releaseTau: releaseTau, directionTau: directionTau)
        primed = true
        return MovieFrame(left: render(left), right: render(right), source: source)
    }

    // MARK: Targets

    /// A film frame averages to a dim, muted colour (a mid-grey scene is only about 5% as much light in linear
    /// terms), so showing it as it is looks dull on a light. A soft knee lifts the mid-tones: `gain` rises with
    /// intensity, near-black stays near-black, and the brightest scenes still reach full.
    static func tone(_ light: Float, intensity: Float) -> Float {
        let gain = 1 + 12 * intensity
        return (1 - expf(-gain * light)) / (1 - expf(-gain))
    }

    private static func picture(_ c: LinearColor, intensity: Float) -> Target {
        let p = c.peak
        return Target(level: tone(p, intensity: intensity), direction: p > 0.004 ? SIMD3(c.r, c.g, c.b) / p : nil)
    }

    private static let ramp: [(at: Float, color: SIMD3<Float>)] = [
        (0, SIMD3(0.15, 0.35, 1.0)), // quiet: cool ambient blue
        (0.45, SIMD3(1.0, 0.42, 0.05)), // impact: amber
        (0.8, SIMD3(1.0, 0.82, 0.5)), // big impact: warm white
        (1, SIMD3(1.0, 0.95, 0.85)),
    ]

    private static func soundtrack(_ s: SpeakerLevel, intensity: Float) -> Target {
        let energy = min(1, 0.6 * s.bass + 0.3 * s.overall + 0.1 * s.treble)
        let floor: Float = s.overall < 0.02 ? 0.04 : 0.10
        let level = min(1, (floor + (1 - floor) * powf(energy, 1.4)) * (1 + intensity))
        var color = ramp[ramp.count - 1].color
        for i in 1 ..< ramp.count where energy <= ramp[i].at {
            let (a, b) = (ramp[i - 1], ramp[i])
            color = a.color + (b.color - a.color) * ((energy - a.at) / (b.at - a.at))
            break
        }
        return Target(level: level, direction: color)
    }

    private func isCut(_ scene: SceneSample) -> Bool {
        guard let p = previous else { return false }
        func distance(_ a: LinearColor, _ b: LinearColor) -> Float {
            (abs(SRGB.encode(a.r) - SRGB.encode(b.r)) + abs(SRGB.encode(a.g) - SRGB.encode(b.g))
                + abs(SRGB.encode(a.b) - SRGB.encode(b.b))) / 3
        }
        return (distance(scene.left, p.left) + distance(scene.right, p.right)) / 2 > 0.25
    }

    // MARK: Smoothing

    private func advance(
        _ side: Side, to target: Target?, cut: Bool, dt: Double, releaseTau: Double, directionTau: Double
    ) -> Side {
        guard let target else { return side }
        var s = side

        // Brightness: near-instant attack, slow release, snap on a cut.
        let tau = target.level > s.level ? 0.03 : releaseTau
        var delta = (target.level - s.level) * Float(1 - exp(-dt / tau))
        if cut { delta = target.level - s.level }

        // Flash limiter: total movement over the last second is capped, but never frozen completely.
        s.swings.removeAll { clock - $0.time > 1 }
        let used = s.swings.reduce(0) { $0 + $1.amount }
        let budget = max(flashLimit - used, 0.2 * Float(dt))
        if abs(delta) > budget { delta = delta < 0 ? -budget : budget }
        s.level = min(max(s.level + delta, 0), 1)
        s.swings.append((clock, abs(delta)))

        // Colour: settles more slowly than brightness; held while too dark to judge.
        if let direction = target.direction {
            if cut || !primed {
                s.direction = direction
            } else {
                s.direction += (direction - s.direction) * Float(1 - exp(-dt / directionTau))
            }
        }
        return s
    }

    // MARK: Output

    private func render(_ side: Side) -> RGB {
        let intensity = Float(min(max(settings.intensity, 0), 1))
        let linear = side.direction * side.level
        var encoded = SIMD3(
            powf(linear.x, 1 / ledGamma), powf(linear.y, 1 / ledGamma), powf(linear.z, 1 / ledGamma)
        )

        // Vibrance: a weak tint is pushed further than a strong one, so a warm or cool cast on a muted scene
        // reads as colour rather than off-white, and an already saturated colour barely changes. Truly neutral
        // light stays white, so a grey scene does not pick up a random tint. The brightest channel is kept.
        let peak = max(encoded.x, encoded.y, encoded.z)
        if peak > 0.001 {
            let saturation = 1 - min(encoded.x, encoded.y, encoded.z) / peak
            if saturation > 0.0001 {
                let boosted = 1 - powf(1 - saturation, 1 + 4 * intensity)
                let fadeIn = min(max((saturation - 0.015) / 0.045, 0), 1)
                let gain = 1 + (boosted / saturation - 1) * fadeIn
                encoded = SIMD3(repeating: peak) - (SIMD3(repeating: peak) - encoded) * gain
            }
        }
        func byte(_ v: Float) -> UInt8 { UInt8((min(max(v, 0), 1) * 255).rounded()) }
        return RGB(byte(encoded.x), byte(encoded.y), byte(encoded.z))
    }
}
