import Foundation

/// Mid/side stereo widener tuned for speakers.
///
/// Only the side signal above `crossoverHz` is widened, so bass stays centred and punchy and mono
/// material (dialogue, vocals) is untouched. `width` 1 = unchanged, 2 = side doubled.
public struct StereoWidener: Sendable {
    public var width: Float
    private var lowSide: Float = 0
    private let alpha: Float

    public init(sampleRate: Double, crossoverHz: Double = 250, width: Float = 1) {
        self.width = width
        alpha = Float(1 - exp(-2 * Double.pi * crossoverHz / sampleRate))
    }

    public mutating func process(_ left: Float, _ right: Float) -> (left: Float, right: Float) {
        let mid = (left + right) * 0.5
        let side = (left - right) * 0.5
        lowSide += alpha * (side - lowSide)          // low-passed side: kept as is
        let highSide = side - lowSide                // widened part
        let wideSide = lowSide + highSide * width
        return (mid + wideSide, mid - wideSide)
    }

    /// Gentle limiter so a widened mix never hard-clips: linear below the knee, soft above it.
    @inline(__always)
    public static func softLimit(_ x: Float) -> Float {
        let knee: Float = 0.85
        let a = abs(x)
        if a <= knee { return x }
        let over = (a - knee) / (1 - knee)
        let shaped = knee + (1 - knee) * tanhf(over)
        return x < 0 ? -shaped : shaped
    }
}
