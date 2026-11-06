import AVFAudio
import AudioToolbox
import CoreAudio
import Foundation

/// Spatial audio for the Nommo: captures all system audio with a muting tap, processes it (crosstalk
/// cancellation and/or widening), and plays it to the speaker. If the app quits or crashes the tap
/// disappears and normal audio resumes on its own.
public final class SpatialAudio: @unchecked Sendable {
    private var tap: SystemAudioTap?
    private var engine: AVAudioEngine?
    private var processor: SpatialProcessor?

    public private(set) var isRunning = false

    public init() {}

    deinit { stop() }

    public func setParameters(mode: SpatialMode, amount: Float) {
        processor?.setParameters(mode: mode, amount: amount)
    }

    public func start(mode: SpatialMode, amount: Float) throws {
        guard !isRunning else { setParameters(mode: mode, amount: amount); return }
        do {
            try startUnchecked(mode: mode, amount: amount)
            isRunning = true
        } catch {
            stop()
            throw error
        }
    }

    public func stop() {
        tap?.stop()
        tap = nil
        engine?.stop()
        engine = nil
        processor = nil
        isRunning = false
    }

    private func startUnchecked(mode: SpatialMode, amount: Float) throws {
        guard let output = AudioDevices.findNommoOutput() else { throw SpatialAudioError.outputDeviceNotFound }
        let processor = SpatialProcessor(sampleRate: output.sampleRate, mode: mode, amount: amount)
        self.processor = processor

        // Playback: an engine pinned to the Nommo, pulling processed frames.
        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: output.sampleRate, channels: 2)!
        let source = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard buffers.count >= 2,
                  let l = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let r = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            processor.pull(left: l, right: r, frames: Int(frameCount))
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        try engine.outputNode.auAudioUnit.setDeviceID(output.id)
        self.engine = engine
        try engine.start()

        // Capture: muting tap feeding the processor.
        let tap = SystemAudioTap(consumer: processor, mute: true, label: "spatial")
        self.tap = tap
        try tap.start(output: output)
    }
}
