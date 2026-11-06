import Foundation

/// Recursive crosstalk canceller for a pair of close desktop speakers.
///
/// Each speaker's sound also reaches the far ear a fraction of a millisecond later and slightly
/// duller (head shadow). Playing an inverted, equally delayed and filtered copy of each channel out of
/// the *other* speaker cancels most of that leakage, so the stereo image can extend past the speakers.
///
///     yL[n] = xL[n] - a * shadow(yR[n - D])
///     yR[n] = xR[n] - a * shadow(yL[n - D])
///
/// Only the band above `bassCutoffHz` goes through the canceller (bass is left alone, otherwise centred
/// bass would be thinned out), and the loop gain `a` is kept below 1 so the feedback is always stable.
public struct CrosstalkCanceller: Sendable {
    /// 0 = transparent, 1 = strongest cancellation.
    public var strength: Float

    private static let historySize = 64 // power of two, > delay
    private let delay: Int
    private let shadowAlpha: Float
    private let bassAlpha: Float
    private var historyL = [Float](repeating: 0, count: historySize)
    private var historyR = [Float](repeating: 0, count: historySize)
    private var position = 0
    private var shadowL: Float = 0
    private var shadowR: Float = 0
    private var bassL: Float = 0
    private var bassR: Float = 0

    /// - Parameters:
    ///   - pathDifference: extra travel time to the far ear, about 0.2 ms for speakers ~±15° apart.
    ///   - shadowCutoffHz: head-shadow low-pass on the leakage path.
    public init(
        sampleRate: Double, strength: Float = 0, pathDifference: Double = 0.0002,
        shadowCutoffHz: Double = 2500, bassCutoffHz: Double = 200
    ) {
        self.strength = strength
        delay = max(1, min(Self.historySize - 1, Int((pathDifference * sampleRate).rounded())))
        shadowAlpha = Float(1 - exp(-2 * Double.pi * shadowCutoffHz / sampleRate))
        bassAlpha = Float(1 - exp(-2 * Double.pi * bassCutoffHz / sampleRate))
    }

    public mutating func process(_ left: Float, _ right: Float) -> (left: Float, right: Float) {
        // Split off the bass; only the rest is processed.
        bassL += bassAlpha * (left - bassL)
        bassR += bassAlpha * (right - bassR)
        let highL = left - bassL
        let highR = right - bassR

        let gain = 0.9 * min(max(strength, 0), 1)
        let mask = Self.historySize - 1
        let delayedL = historyL[(position - delay) & mask]
        let delayedR = historyR[(position - delay) & mask]
        shadowL += shadowAlpha * (delayedR - shadowL) // leakage reaching the left ear comes from the right speaker
        shadowR += shadowAlpha * (delayedL - shadowR)

        let outL = highL - gain * shadowL
        let outR = highR - gain * shadowR
        historyL[position & mask] = outL
        historyR[position & mask] = outR
        position &+= 1

        // The canceller lowers centred (mono) content a little; make some of it back.
        let makeup = 1 + 0.35 * gain
        return (bassL + outL * makeup, bassR + outR * makeup)
    }
}
