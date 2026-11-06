import Foundation
import os

public enum SpatialMode: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Crosstalk cancellation plus a little widening: the sound extends past the speakers.
    case immersive
    /// Plain mid/side widening of the upper frequencies.
    case widen

    public var id: String { rawValue }
    public var title: String { self == .immersive ? "Immersive" : "Widen" }
}

/// Bridges the capture callback and the playback callback: a small stereo ring buffer with the
/// widener applied on the way out. Both callbacks run on audio threads, so everything is under one lock.
public final class SpatialProcessor: AudioTapConsumer, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var ring: [Float]
    private let capacityFrames: Int
    private var readIndex = 0
    private var count = 0
    private var primed = false
    private var widener: StereoWidener
    private var canceller: CrosstalkCanceller
    private var mode: SpatialMode

    /// Frames to accumulate before playback starts (cushion against jitter), and the fill level we
    /// trim back to if the capture clock runs ahead of playback.
    private let primeFrames: Int
    private let maxFrames: Int

    public init(sampleRate: Double, mode: SpatialMode, amount: Float) {
        capacityFrames = Int(sampleRate) // one second
        ring = [Float](repeating: 0, count: capacityFrames * 2)
        primeFrames = max(256, Int(sampleRate * 0.020))
        maxFrames = Int(sampleRate * 0.120)
        widener = StereoWidener(sampleRate: sampleRate)
        canceller = CrosstalkCanceller(sampleRate: sampleRate)
        self.mode = mode
        configure(mode: mode, amount: amount)
    }

    /// `amount` is 0...1 and means "how much", whichever mode is active.
    public func setParameters(mode: SpatialMode, amount: Float) {
        lock.withLockUnchecked { configure(mode: mode, amount: amount) }
    }

    private func configure(mode: SpatialMode, amount: Float) {
        let a = min(max(amount, 0), 1)
        self.mode = mode
        switch mode {
        case .immersive:
            canceller.strength = a
            widener.width = 1 + 0.5 * a
        case .widen:
            canceller.strength = 0
            widener.width = 1 + 1.5 * a
        }
    }

    // MARK: Capture side

    public func push(interleaved: UnsafePointer<Float>, frames: Int) {
        lock.withLockUnchecked {
            for i in 0 ..< frames { write(interleaved[2 * i], interleaved[2 * i + 1]) }
        }
    }

    public func push(left: UnsafePointer<Float>, right: UnsafePointer<Float>, frames: Int) {
        lock.withLockUnchecked {
            for i in 0 ..< frames { write(left[i], right[i]) }
        }
    }

    private func write(_ l: Float, _ r: Float) {
        if count == capacityFrames { // overflow: drop the oldest frame
            readIndex = (readIndex + 1) % capacityFrames
            count -= 1
        }
        let w = (readIndex + count) % capacityFrames
        ring[2 * w] = l
        ring[2 * w + 1] = r
        count += 1
    }

    // MARK: Playback side

    public func pull(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        lock.withLockUnchecked {
            if count > maxFrames { // playback fell behind: trim to keep latency bounded
                let drop = count - primeFrames
                readIndex = (readIndex + drop) % capacityFrames
                count -= drop
            }
            if !primed {
                if count >= primeFrames { primed = true } else {
                    for i in 0 ..< frames { left[i] = 0; right[i] = 0 }
                    return
                }
            }
            for i in 0 ..< frames {
                guard count > 0 else {
                    left[i] = 0; right[i] = 0
                    primed = false // underrun: re-prime before resuming
                    continue
                }
                let l = ring[2 * readIndex]
                let r = ring[2 * readIndex + 1]
                readIndex = (readIndex + 1) % capacityFrames
                count -= 1
                var out = (left: l, right: r)
                if mode == .immersive { out = canceller.process(out.left, out.right) }
                out = widener.process(out.left, out.right)
                left[i] = StereoWidener.softLimit(out.left)
                right[i] = StereoWidener.softLimit(out.right)
            }
        }
    }
}
