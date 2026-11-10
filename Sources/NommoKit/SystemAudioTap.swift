import AVFAudio
import AudioToolbox
import CoreAudio
import Foundation

public enum SpatialAudioError: Error, CustomStringConvertible {
    case outputDeviceNotFound
    case coreAudio(String, OSStatus)

    public var description: String {
        switch self {
        case .outputDeviceNotFound: "Nommo output device not found"
        case let .coreAudio(what, status): "\(what) failed (\(status))"
        }
    }
}

/// Receives system audio from a `SystemAudioTap` on a real-time thread.
public protocol AudioTapConsumer: AnyObject, Sendable {
    func push(interleaved: UnsafePointer<Float>, frames: Int)
    func push(left: UnsafePointer<Float>, right: UnsafePointer<Float>, frames: Int)
}

struct OutputDevice {
    var id: AudioDeviceID
    var uid: String
    var sampleRate: Double
}

/// A Core Audio process tap on all system audio (except this process), delivered to a consumer.
/// With `mute: true` the original audio is silenced so only a processed copy is heard; with `mute: false`
/// the tap just listens. Requires macOS 14.2+ and the "System Audio Recording" permission.
final class SystemAudioTap: @unchecked Sendable {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private let consumer: any AudioTapConsumer
    private let mute: Bool
    private let queue: DispatchQueue

    init(consumer: any AudioTapConsumer, mute: Bool, label: String) {
        self.consumer = consumer
        self.mute = mute
        queue = DispatchQueue(label: "ai.amplified.nommo.tap.\(label)", qos: .userInteractive)
    }

    deinit { stop() }

    func start(output: OutputDevice) throws {
        do {
            try startUnchecked(output: output)
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if let procID = ioProcID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        ioProcID = nil
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    private func startUnchecked(output: OutputDevice) throws {
        let selfObject = try AudioDevices.processObject(for: getpid())
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [selfObject])
        description.name = mute ? "Nommo Spatial" : "Nommo Levels"
        description.isPrivate = true
        description.muteBehavior = mute ? .muted : .unmuted
        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else { throw SpatialAudioError.coreAudio("Create system audio tap", status) }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: description.name,
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: output.uid,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: output.uid]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
        guard status == noErr else { throw SpatialAudioError.coreAudio("Create aggregate device", status) }

        let consumer = consumer
        status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, queue) { _, inputData, _, _, _ in
            let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
            // The tap is the last input; skip any hardware input streams ahead of it.
            if list.count >= 2, list[list.count - 1].mNumberChannels == 1, list[list.count - 2].mNumberChannels == 1 {
                let l = list[list.count - 2], r = list[list.count - 1]
                guard let lp = l.mData?.assumingMemoryBound(to: Float.self),
                      let rp = r.mData?.assumingMemoryBound(to: Float.self) else { return }
                consumer.push(left: lp, right: rp, frames: Int(l.mDataByteSize) / MemoryLayout<Float>.size)
            } else if let last = list.last, last.mNumberChannels == 2,
                      let data = last.mData?.assumingMemoryBound(to: Float.self) {
                consumer.push(interleaved: data, frames: Int(last.mDataByteSize) / (2 * MemoryLayout<Float>.size))
            }
        }
        guard status == noErr else { throw SpatialAudioError.coreAudio("Create capture callback", status) }
        status = AudioDeviceStart(aggregateID, ioProcID)
        guard status == noErr else { throw SpatialAudioError.coreAudio("Start capture", status) }
    }
}

// MARK: - Core Audio lookups

/// What the speaker lookup needs to know about one Core Audio device.
struct AudioDeviceInfo: Equatable {
    var id: AudioDeviceID
    var name: String
    var uid: String
    var transport: UInt32
    var hasOutput: Bool
    var sampleRate: Double
}

enum AudioDevices {
    /// Aggregate and virtual devices are never the speaker. This matters because this process creates private
    /// aggregates of its own ("Nommo Levels", "Nommo Spatial") that carry "Nommo" in their name and the
    /// speaker's output; they are visible to this process, and picking one of them as the playback device
    /// sends the processed sound nowhere while the muting tap has already silenced everything else.
    static func isPhysical(transport: UInt32) -> Bool {
        transport != kAudioDeviceTransportTypeAggregate
            && transport != kAudioDeviceTransportTypeAutoAggregate
            && transport != kAudioDeviceTransportTypeVirtual
    }

    /// The first real output device whose name says Nommo.
    static func chooseNommo(from devices: [AudioDeviceInfo]) -> AudioDeviceInfo? {
        devices.first { $0.hasOutput && isPhysical(transport: $0.transport) && $0.name.localizedCaseInsensitiveContains("nommo") }
    }

    static func findNommoOutput() -> OutputDevice? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
        else { return nil }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
        else { return nil }

        let devices = ids.compactMap { id -> AudioDeviceInfo? in
            guard let name = string(id, kAudioObjectPropertyName), let uid = string(id, kAudioDevicePropertyDeviceUID)
            else { return nil }
            return AudioDeviceInfo(
                id: id, name: name, uid: uid, transport: transportType(id),
                hasOutput: hasOutputStreams(id), sampleRate: nominalSampleRate(id)
            )
        }
        guard let device = chooseNommo(from: devices) else { return nil }
        return OutputDevice(id: device.id, uid: device.uid, sampleRate: device.sampleRate)
    }

    static func transportType(_ device: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        var type: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        _ = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &type)
        return type
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    static func hasOutputStreams(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    static func nominalSampleRate(_ device: AudioDeviceID) -> Double {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        var rate = Float64(48000)
        var size = UInt32(MemoryLayout<Float64>.size)
        _ = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &rate)
        return rate
    }

    static func processObject(for pid: pid_t) throws -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        var pid = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address,
            UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object
        )
        guard status == noErr else { throw SpatialAudioError.coreAudio("Look up own audio process", status) }
        return object
    }
}
