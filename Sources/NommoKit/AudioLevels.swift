import Foundation
import os

/// Normalised (0...1) loudness of one speaker's channel, overall and in three bands.
public struct SpeakerLevel: Equatable, Sendable {
    public var overall: Float
    public var bass: Float
    public var mid: Float
    public var treble: Float

    public static let silent = SpeakerLevel(overall: 0, bass: 0, mid: 0, treble: 0)

    public init(overall: Float, bass: Float, mid: Float, treble: Float) {
        self.overall = overall
        self.bass = bass
        self.mid = mid
        self.treble = treble
    }

    /// Moves towards `target`: fast attack, slower release, so lights punch in and fade out.
    public func smoothed(towards target: SpeakerLevel, attack: Float = 0.7, release: Float = 0.16) -> SpeakerLevel {
        func step(_ current: Float, _ goal: Float) -> Float {
            current + (goal - current) * (goal > current ? attack : release)
        }
        return SpeakerLevel(
            overall: step(overall, target.overall), bass: step(bass, target.bass),
            mid: step(mid, target.mid), treble: step(treble, target.treble)
        )
    }
}

public struct AudioLevels: Equatable, Sendable {
    public var left: SpeakerLevel
    public var right: SpeakerLevel

    public static let silent = AudioLevels(left: .silent, right: .silent)

    public init(left: SpeakerLevel, right: SpeakerLevel) {
        self.left = left
        self.right = right
    }

    public func smoothed(towards target: AudioLevels) -> AudioLevels {
        AudioLevels(left: left.smoothed(towards: target.left), right: right.smoothed(towards: target.right))
    }
}

/// Measures system audio loudness per channel and per band (bass < 150 Hz < mid < 2.5 kHz < treble),
/// with automatic gain so the output is useful at any listening volume.
public final class AudioLevelAnalyzer: AudioTapConsumer, @unchecked Sendable {
    private struct Channel {
        var lowPass150: Float = 0
        var lowPass2500: Float = 0
        var sums: [Float] = [0, 0, 0, 0] // overall, bass, mid, treble
    }

    private let shared = OSAllocatedUnfairLock(initialState: AudioLevels.silent)
    private let alpha150: Float
    private let alpha2500: Float
    // Touched only from the capture thread.
    private var left = Channel()
    private var right = Channel()
    private var references: [Float] = [0, 0, 0, 0]

    public init(sampleRate: Double) {
        alpha150 = Float(1 - exp(-2 * Double.pi * 150 / sampleRate))
        alpha2500 = Float(1 - exp(-2 * Double.pi * 2500 / sampleRate))
    }

    /// Latest normalised levels (safe to call from any thread).
    public var levels: AudioLevels { shared.withLock { $0 } }

    public func push(interleaved: UnsafePointer<Float>, frames: Int) {
        for i in 0 ..< frames { accumulate(interleaved[2 * i], interleaved[2 * i + 1]) }
        finishBuffer(frames: frames)
    }

    public func push(left l: UnsafePointer<Float>, right r: UnsafePointer<Float>, frames: Int) {
        for i in 0 ..< frames { accumulate(l[i], r[i]) }
        finishBuffer(frames: frames)
    }

    @inline(__always)
    private func accumulate(_ l: Float, _ r: Float) {
        Self.step(&left, l, alpha150, alpha2500)
        Self.step(&right, r, alpha150, alpha2500)
    }

    @inline(__always)
    private static func step(_ c: inout Channel, _ x: Float, _ a150: Float, _ a2500: Float) {
        c.lowPass150 += a150 * (x - c.lowPass150)
        c.lowPass2500 += a2500 * (x - c.lowPass2500)
        let bass = c.lowPass150
        let mid = c.lowPass2500 - c.lowPass150
        let treble = x - c.lowPass2500
        c.sums[0] += x * x
        c.sums[1] += bass * bass
        c.sums[2] += mid * mid
        c.sums[3] += treble * treble
    }

    private func finishBuffer(frames: Int) {
        guard frames > 0 else { return }
        let n = Float(frames)
        let rmsL = left.sums.map { ($0 / n).squareRoot() }
        let rmsR = right.sums.map { ($0 / n).squareRoot() }
        left.sums = [0, 0, 0, 0]
        right.sums = [0, 0, 0, 0]

        // Slowly-decaying running peak per metric = automatic gain control.
        var normalisedL = [Float](repeating: 0, count: 4)
        var normalisedR = [Float](repeating: 0, count: 4)
        for k in 0 ..< 4 {
            references[k] = max(references[k] * 0.9997, max(rmsL[k], rmsR[k]), 1e-6)
            // A band can't be boosted past ~7x its share of the overall peak: otherwise filter leakage
            // (a little treble in a pure bass note) would be amplified to full scale.
            if k > 0 { references[k] = max(references[k], 0.15 * references[0]) }
            // Below this share of the recent peak counts as silence (bands need a higher floor than overall).
            let floor = references[k] * (k == 0 ? 0.05 : 0.2)
            func norm(_ v: Float) -> Float {
                guard references[k] > 2e-4, v > floor else { return 0 }
                return min(1, powf((v - floor) / (references[k] - floor), 0.65))
            }
            normalisedL[k] = norm(rmsL[k])
            normalisedR[k] = norm(rmsR[k])
        }
        let result = AudioLevels(
            left: SpeakerLevel(overall: normalisedL[0], bass: normalisedL[1], mid: normalisedL[2], treble: normalisedL[3]),
            right: SpeakerLevel(overall: normalisedR[0], bass: normalisedR[1], mid: normalisedR[2], treble: normalisedR[3])
        )
        shared.withLock { $0 = result }
    }
}

/// Listens to system audio (without muting anything) and publishes `AudioLevels`.
public final class AudioLevelMonitor: @unchecked Sendable {
    private var tap: SystemAudioTap?
    private var analyzer: AudioLevelAnalyzer?

    public init() {}

    deinit { stop() }

    public var isRunning: Bool { tap != nil }

    /// Latest levels, or silence when not running.
    public var levels: AudioLevels { analyzer?.levels ?? .silent }

    public func start() throws {
        guard tap == nil else { return }
        guard let output = AudioDevices.findNommoOutput() else { throw SpatialAudioError.outputDeviceNotFound }
        let analyzer = AudioLevelAnalyzer(sampleRate: output.sampleRate)
        let tap = SystemAudioTap(consumer: analyzer, mute: false, label: "levels")
        self.analyzer = analyzer
        self.tap = tap
        do { try tap.start(output: output) } catch {
            stop()
            throw error
        }
    }

    public func stop() {
        tap?.stop()
        tap = nil
        analyzer = nil
    }
}
