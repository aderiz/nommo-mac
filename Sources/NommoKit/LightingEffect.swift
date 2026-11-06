import Foundation

public enum MusicStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Each speaker's brightness follows its own channel, in the chosen colour.
    case pulse
    /// Bass drives red, mids green and treble blue, per speaker.
    case colorMix

    public var id: String { rawValue }
    public var title: String { self == .pulse ? "Pulse" : "Colour mix" }
}

/// A lighting effect, rendered on the Mac and streamed to the speaker as frames
/// (the speaker has no effect engine of its own; Synapse works the same way).
public enum LightingEffect: Codable, Equatable, Sendable {
    /// Stop streaming: the speaker returns to its built-in colour cycle.
    case builtIn
    case solid(left: RGB, right: RGB)
    /// Fades one colour up and down, then the other, and repeats. `period` is seconds per breath.
    case breathing(first: RGB, second: RGB, period: Double)
    /// Hue sweep. `period` is seconds per full cycle; `offset` shifts the right speaker's phase (0...1).
    case spectrum(period: Double, offset: Double)
    case off
    /// Reacts to the music playing on the Mac. `sensitivity` scales the response (1 = normal).
    case music(left: RGB, right: RGB, style: MusicStyle, sensitivity: Double)

    public static let `default` = LightingEffect.solid(left: RGB(0, 120, 255), right: RGB(0, 120, 255))

    /// True when frames change over time and need a fast stream.
    public var isAnimated: Bool {
        switch self {
        case .breathing, .spectrum, .music: true
        case .builtIn, .solid, .off: false
        }
    }

    /// True when the app should be streaming frames at all.
    public var streams: Bool {
        if case .builtIn = self { return false }
        return true
    }

    /// True for effects that need the system audio levels.
    public var reactsToAudio: Bool {
        if case .music = self { return true }
        return false
    }

    /// Colours for the given moment, `t` seconds since the effect started.
    public func colors(at t: TimeInterval, levels: AudioLevels = .silent) -> (left: RGB, right: RGB) {
        switch self {
        case let .music(left, right, style, sensitivity):
            let gain = Float(min(max(sensitivity, 0.2), 3))
            switch style {
            case .pulse:
                func lit(_ c: RGB, _ level: SpeakerLevel) -> RGB {
                    c.scaled(by: Double(0.05 + 0.95 * min(1, level.overall * gain)))
                }
                return (lit(left, levels.left), lit(right, levels.right))
            case .colorMix:
                func mix(_ level: SpeakerLevel) -> RGB {
                    func byte(_ v: Float) -> UInt8 { UInt8((min(1, v * gain) * 255).rounded()) }
                    return RGB(byte(level.bass), byte(level.mid), byte(level.treble))
                }
                return (mix(levels.left), mix(levels.right))
            }
        case .builtIn, .off:
            return (.black, .black)
        case let .solid(left, right):
            return (left, right)
        case let .breathing(first, second, period):
            // Each breath is a smooth 0 -> 1 -> 0 with a short dark gap at the bottom; breaths alternate colours.
            let p = max(period, 0.5)
            let breath = Int((max(t, 0) / p).rounded(.down))
            let phase = (max(t, 0) - Double(breath) * p) / p
            let level = max(0, (1 - cos(phase * 2 * .pi)) / 2 * 1.08 - 0.04)
            let color = (breath % 2 == 0 ? first : second).scaled(by: level)
            return (color, color)
        case let .spectrum(period, offset):
            let p = max(period, 1)
            let base = (t / p).truncatingRemainder(dividingBy: 1)
            return (Self.hue(base), Self.hue((base + offset).truncatingRemainder(dividingBy: 1)))
        }
    }

    /// Fully saturated colour for a hue in 0...1.
    static func hue(_ h: Double) -> RGB {
        let h6 = h * 6
        let x = 1 - abs(h6.truncatingRemainder(dividingBy: 2) - 1)
        let (r, g, b): (Double, Double, Double) = switch Int(h6) % 6 {
        case 0: (1, x, 0)
        case 1: (x, 1, 0)
        case 2: (0, 1, x)
        case 3: (0, x, 1)
        case 4: (x, 0, 1)
        default: (1, 0, x)
        }
        return RGB(UInt8((r * 255).rounded()), UInt8((g * 255).rounded()), UInt8((b * 255).rounded()))
    }
}
